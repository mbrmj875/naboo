import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  ensureEvolutionInstance,
  ensureEvolutionWebhook,
  evolutionInstanceNameForUser,
  evolutionSendText,
  extractQrPayload,
  fetchEvolutionConnectQr,
  fetchEvolutionOwnerDigits,
  normalizeIraqWhatsappDigits,
  purgeAndRecreateEvolutionSession,
  readEvolutionLiveState,
  softReconnectEvolutionSession,
  type PurgeRecreateResult,
} from './waha.ts';
import * as Evo from './evolution.ts';
import { cloudSendText } from './cloud_api.ts';
import { sharedSenderConfig } from './shared_sender.ts';
import {
  parseWhats360Credentials,
  whats360SendText,
} from './whats360.ts';
import {
  cleanupOtherEngines,
  parseProvider,
  readProvider,
  type WhatsappProvider,
} from './provider.ts';
import {
  jidTypeFromRemote,
  newCorrelationId,
  writeDiagnostic,
} from './diagnostics.ts';
import { writeOpsFact } from '../whatsapp-ops-analyst/facts.ts';
import {
  connectedEmailCopy,
  notifyOwnerEmail,
} from '../whatsapp-events/owner_email_notify.ts';
import {
  completeOfficialConnect,
  startOfficialConnect,
} from './lifecycle/connect_service.ts';
import {
  computeReadyState,
  readyStateMessageAr,
} from './lifecycle/ready_state.ts';
import { syncTemplateStatusesForTenant } from './lifecycle/template_lifecycle_service.ts';
import { ensureDefaultTemplatesForTenant } from './lifecycle/template_lifecycle_service.ts';
import { notifyOilChangeCard } from './notifications/notifiers/oil_change_card_notifier.ts';
import { writeClient } from './admin_client.ts';
import { getWhatsAppProvider } from './providers/registry.ts';
import {
  claimSendLogRow,
  debitWalletForSend,
  gateProviderSendAfterWallet,
  walletRejectResponse,
  type ProviderSendGate,
} from './wallet.ts';
import { codeFromGatewayDetail, formatWaLogError } from './wa_log_error.ts';

function providerGateResponse(
  gate: ProviderSendGate,
  extras: Record<string, unknown>,
): Response | null {
  if (gate.action === 'send') return null;
  if (gate.action === 'idempotent_hit') {
    return Response.json({
      ok: true,
      reason: 'idempotent_hit',
      detail: 'idempotent_hit',
      provider_message_id: gate.providerMessageId ?? undefined,
      ...extras,
    });
  }
  // نتيجة غير معروفة بعد خصم سابق — لا تُرسل للمزود مرة ثانية.
  // ok:false حتى لا يُزال من Outbox المحلي كـ «أُرسل» بينما التسليم غير مؤكد.
  return Response.json({
    ok: false,
    reason: 'previous_attempt_pending',
    detail: 'wallet_duplicate_pending',
    provider_message_id: gate.providerMessageId ?? undefined,
    message_ar: 'طلب إرسال سابق ما زال قيد المعالجة — لن يُعاد الإرسال تلقائياً.',
    ...extras,
  });
}

type GatewayAction =
  | 'provision'
  | 'qr'
  | 'status'
  | 'report_disconnected'
  | 'disconnect'
  | 'send_text'
  | 'set_provider'
  | 'configure_whats360'
  | 'connect_official'
  | 'complete_official_connect'
  | 'ready_status'
  | 'sync_templates'
  | 'send_oil_change_card'
  | 'dismiss_failed_message';

type ResetSource =
  | 'user_disconnect'
  | 'user_force_reset'
  | 'server_qr_fallback';

type RequestBody = {
  action?: GatewayAction;
  /** عند true يصفّر الجلسة قبل جلب QR — يُتجاهل إذا الجلسة open/connecting. */
  force_reset?: boolean;
  /** إرسال نص عبر المحرك النشط — رقم الزبون ونص الرسالة فقط. */
  customer_phone?: string;
  message_text?: string;
  /** إعداد واتس360: توكن + معرّف الجهاز */
  whats360_token?: string;
  whats360_instance_id?: string;
  order_id?: number | string | null;
  /** مزود واتساب: evolution (QR) | cloud_api (رسمي) | waha (احتياطي) */
  provider?: string;
  /** إكمال الربط الرسمي */
  waba_id?: string;
  phone_number_id?: string;
  from_phone?: string;
  connection_id?: string;
  oauth_code?: string;
  /** بطاقة غيار عبر NotificationDispatcher */
  customer_name?: string;
  shop_name?: string;
  details_block?: string;
  /** حقول البطاقة الطويلة بأسماء متغيّرات القالب (car، oil_brand، total…). */
  template_params?: Record<string, unknown>;
  /** اسم الفني — يُحفظ في سجل الرسالة ليُسنَد تقييم العميل إليه. */
  employee_name?: string;
  /** إعادة إرسال يدوية من سجل الرسائل — لا يمنعها مفتاح التكرار. */
  resend?: boolean;
};

const FORCE_RESET_COOLDOWN_MS = 10 * 60 * 1000;
const DISCONNECT_COOLDOWN_MS = 2 * 60 * 1000;
/** يمنع عاصفة provision من التطبيق أثناء connecting/repair. */
const PROVISION_COOLDOWN_MS = 45 * 1000;
const LOCK_TTL_SECONDS = 45;

/** CORS للمتصفح — بدون OPTIONS ينجح الموبايل ويفشل الويب بـ timeout. */
function corsHeaders(req: Request): HeadersInit {
  const origin = req.headers.get('Origin') ?? '*';
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

function withCors(req: Request, res: Response): Response {
  const headers = new Headers(res.headers);
  for (const [key, value] of Object.entries(corsHeaders(req))) {
    headers.set(key, String(value));
  }
  return new Response(res.body, {
    status: res.status,
    statusText: res.statusText,
    headers,
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }

  const res = await (async (): Promise<Response> => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) {
    return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userErr } = await supabase.auth.getUser();
  const user = userData?.user;
  if (userErr || !user) {
    return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return Response.json({ ok: false, error: 'invalid_json' }, { status: 400 });
  }

  const action = body.action;
  if (!action) {
    return Response.json({ ok: false, error: 'missing_action' }, { status: 400 });
  }

  // Instance دائماً من JWT — لا يقبل العميل اسم instance (منع IDOR).
  const instanceName = evolutionInstanceNameForUser(user.id);
  const now = new Date().toISOString();

  if (action === 'connect_official') {
    const result = await startOfficialConnect(supabase, user.id);
    return Response.json(result, { status: result.ok ? 200 : 503 });
  }

  if (action === 'complete_official_connect') {
    const result = await completeOfficialConnect(supabase, {
      tenantUserId: user.id,
      wabaId: body.waba_id,
      phoneNumberId: body.phone_number_id,
      fromPhoneE164: body.from_phone,
      connectionId: body.connection_id,
      oauthCode: body.oauth_code,
    });
    return Response.json(result, { status: result.ok ? 200 : 400 });
  }

  if (action === 'ready_status') {
    // إن وُجد WABA ولم تُنشأ القوالب بعد — أنشرها ثم زامن الحالة.
    await ensureDefaultTemplatesForTenant(supabase, user.id);
    await syncTemplateStatusesForTenant(supabase, user.id);
    const ready = await computeReadyState(supabase, user.id);
    return Response.json({
      ok: true,
      ready_state: ready.readyState,
      connected: ready.connected,
      phone: ready.phone,
      provider: ready.provider,
      message_ar: readyStateMessageAr(ready.readyState),
    });
  }

  if (action === 'sync_templates') {
    await ensureDefaultTemplatesForTenant(supabase, user.id);
    await syncTemplateStatusesForTenant(supabase, user.id);
    const ready = await computeReadyState(supabase, user.id);
    return Response.json({
      ok: true,
      ready_state: ready.readyState,
      message_ar: readyStateMessageAr(ready.readyState),
    });
  }

  if (action === 'send_oil_change_card') {
    const phoneRaw = (body.customer_phone ?? '').toString().trim();
    const phone = normalizeIraqWhatsappDigits(phoneRaw);
    const orderId = (body.order_id ?? '').toString().trim();
    const employeeName = (body.employee_name ?? '').toString().trim();
    const isResend = body.resend === true;
    const attemptId = (body.attempt_id ?? '').toString().trim();

    if (!phone) {
      // يظهر في «لم يتم الإرسال» حتى لو الرقم غير صالح — ليس outbox قابل للإعادة.
      try {
        const cardProvider = await readProvider(supabase, user.id);
        await writeClient(supabase).from('whatsapp_message_logs').insert({
          tenant_user_id: user.id,
          channel: 'whatsapp',
          provider: cardProvider,
          template_key: 'oil_change_card',
          to_phone: phoneRaw || null,
          status: 'failed',
          provider_message_id: null,
          error: formatWaLogError({
            source: 'gateway',
            code: 'invalid_phone',
            title: 'Invalid phone',
            message: 'invalid_phone',
          }),
          order_ref: orderId || null,
          employee_name: employeeName || null,
          body: (body.details_block ?? body.message_text ?? '').toString() || null,
          card_payload: body.template_params ?? null,
          idempotency_key: orderId
            ? `oil_card:${user.id}:${orderId}:invalid_phone:${Date.now()}`
            : `oil_card:${user.id}:invalid_phone:${Date.now()}`,
        });
      } catch (e) {
        console.warn('invalid_phone log insert failed', e);
      }
      return Response.json({
        ok: false,
        error: 'invalid_phone',
        message_ar: 'رقم الزبون غير صالح.',
      }, { status: 400 });
    }

    // مفتاح موحّد للمحفظة والسجل: عند resend يجب attempt_id ثابت لنفس المحاولة.
    // تضمين الرقم يمنع idempotent_hit عند تصحيح هاتف خاطئ على نفس order_id.
    let idem: string;
    if (isResend) {
      if (!attemptId) {
        return Response.json({
          ok: false,
          error: 'missing_attempt_id',
          message_ar: 'تعذّرت إعادة الإرسال — أعد المحاولة.',
        }, { status: 400 });
      }
      const orderPart = orderId || phone;
      idem = `oil_card:${user.id}:${orderPart}:resend:${attemptId}`;
    } else if (orderId) {
      idem = `oil_card:${user.id}:${orderId}:${phone}`;
    } else {
      idem = `oil_card:${user.id}:${phone}:${Date.now()}`;
    }

    const cardProvider = await readProvider(supabase, user.id);
    const wallet = await debitWalletForSend(supabase, {
      tenantUserId: user.id,
      idempotencyKey: idem,
      provider: cardProvider,
      sendKind: 'oil_change_card',
    });
    if (!wallet.ok) return walletRejectResponse(wallet);

    const walletGate = await gateProviderSendAfterWallet(supabase, {
      tenantUserId: user.id,
      idempotencyKey: idem,
      wallet,
    });
    {
      const early = providerGateResponse(walletGate, {
        mode: 'oil_change_card',
        sent_to: phone,
      });
      if (early) return early;
    }

    const claimGate = await claimSendLogRow(supabase, {
      tenantUserId: user.id,
      idempotencyKey: idem,
      toPhone: phone,
      provider: cardProvider,
      templateKey: 'oil_change_card',
      orderRef: orderId || null,
      employeeName: employeeName || null,
      body: (body.details_block ?? body.message_text ?? '').toString() || null,
    });
    {
      const early = providerGateResponse(claimGate, {
        mode: 'oil_change_card',
        sent_to: phone,
      });
      if (early) return early;
    }

    const templateParams: Record<string, string> = {};
    for (const [key, value] of Object.entries(body.template_params ?? {})) {
      const text = String(value ?? '').trim();
      if (text) templateParams[key] = text;
    }
    const dispatched = await notifyOilChangeCard(supabase, {
      tenantUserId: user.id,
      customerPhone: phone,
      customerName: (body.customer_name ?? '').toString(),
      shopName: (body.shop_name ?? '').toString(),
      detailsBlock: (body.details_block ?? body.message_text ?? '').toString(),
      orderId: body.order_id,
      employeeName: employeeName,
      templateParams,
      resend: isResend,
      idempotencyKey: idem,
      originalLogId: (body.original_log_id ?? '').toString().trim() || null,
    });

    const originalLogId = (body.original_log_id ?? '').toString().trim();
    // بعد نجاح إعادة الإرسال: سَوِّ السجل الأصلي المرتبط فقط — لا كل سجلات الطلب/الرقم.
    if (dispatched.ok && originalLogId) {
      try {
        const db = writeClient(supabase);
        const { error: updErr } = await db
          .from('whatsapp_message_logs')
          .update({
            status: 'sent',
            error: null,
            provider_message_id: null,
          })
          .eq('id', originalLogId)
          .eq('tenant_user_id', user.id)
          .eq('status', 'failed');
        if (updErr) {
          console.warn('resolve original failed log', updErr.message);
        }
      } catch (e) {
        console.warn('resolve original failed log after resend', e);
      }
    }

    // دائماً 200 لجسم JSON واضح — 409 يجعل supabase_flutter على الويب
    // يرمي FunctionException وقد يُفسَّر خطأً كـ timeout دون سجل إرسال.
    return Response.json({
      ok: dispatched.ok,
      ready_state: dispatched.readyState,
      provider_message_id: dispatched.providerMessageId,
      reason: dispatched.ok ? undefined : (dispatched.detail ?? 'send_failed'),
      detail: dispatched.detail,
      resolved_original: dispatched.ok && !!originalLogId,
      message_ar: dispatched.ok
        ? 'تم إرسال بطاقة الغيار.'
        : dispatched.readyState === 'preparing'
        ? 'جاري تجهيز خدمة الرسائل — أعد المحاولة بعد قليل.'
        : dispatched.readyState === 'disconnected'
        ? 'واتساب غير متصل. اربط الرقم أولاً.'
        : 'تعذّر إرسال بطاقة الغيار.',
    });
  }

  if (action === 'dismiss_failed_message') {
    const logId = (body.log_id ?? body.original_log_id ?? '').toString().trim();
    if (!logId) {
      return Response.json({
        ok: false,
        error: 'missing_log_id',
        message_ar: 'تعذّر إسقاط الرسالة.',
      }, { status: 400 });
    }
    // rejected ضمن CHECK ولا يظهر في «تم الإرسال» ولا «لم يتم الإرسال».
    const { data, error } = await writeClient(supabase)
      .from('whatsapp_message_logs')
      .update({
        status: 'rejected',
        error: formatWaLogError({
          source: 'gateway',
          code: 'dismissed_by_user',
          title: 'Dismissed',
          message: 'user_dismissed',
          retryable: false,
        }),
        provider_message_id: null,
      })
      .eq('id', logId)
      .eq('tenant_user_id', user.id)
      .eq('status', 'failed')
      .select('id')
      .maybeSingle();
    if (error) {
      console.warn('dismiss_failed_message', error.message);
      return Response.json({
        ok: false,
        error: 'dismiss_failed',
        message_ar: 'تعذّر إسقاط الرسالة.',
      }, { status: 500 });
    }
    if (!data?.id) {
      return Response.json({
        ok: false,
        error: 'not_found',
        message_ar: 'الرسالة غير موجودة أو أُسقطت مسبقاً.',
      }, { status: 404 });
    }
    return Response.json({
      ok: true,
      message_ar: 'تم إسقاط الرسالة من القائمة.',
    });
  }

  if (action === 'set_provider') {
    const next = parseProvider(body.provider);
    const locked = await acquireLock(supabase);
    if (!locked.ok) {
      return Response.json({
        ok: false,
        error: locked.error,
        retry_after_seconds: locked.retryAfterSeconds,
        message_ar: 'عملية أخرى جارية. انتظر لحظات ثم غيّر طريقة الربط.',
      }, { status: 409 });
    }
    try {
      const prev = await readProvider(supabase, user.id);

      // لا تسمح بالتحويل من رقم المحل الخاص (cloud_api) إلى رقم نابو المشترك
      // إن وُجد phone_number_id مختلف عن SHARED_SENDER — يمنع مسح الربط بالخطأ.
      if (prev === 'cloud_api' && (next === 'dualhook' || next === 'ycloud')) {
        const shared = sharedSenderConfig();
        const { data: gateRow } = await supabase
          .from('tenant_whatsapp_gateways')
          .select('cloud_phone_number_id, whatsapp_phone, status, cloud_setup_status')
          .eq('user_id', user.id)
          .maybeSingle();
        const dedicatedId = String(gateRow?.cloud_phone_number_id ?? '').trim();
        const sharedId = String(shared?.phoneNumberId ?? '').trim();
        const dedicatedReady =
          dedicatedId.length > 0 &&
          dedicatedId !== sharedId &&
          String(gateRow?.status ?? '') === 'connected' &&
          String(gateRow?.cloud_setup_status ?? '') === 'ready';
        if (dedicatedReady) {
          return Response.json({
            ok: false,
            error: 'dedicated_cloud_number_locked',
            provider: prev,
            phone: gateRow?.whatsapp_phone ?? null,
            message_ar:
              'هذا الحساب مربوط برقم واتساب خاص بالمحل. لا يمكن التبديل إلى رقم نابو المشترك من التطبيق. تواصل مع الدعم إن أردت تغيير الرقم.',
          }, { status: 409 });
        }
      }

      const cleanup = await cleanupOtherEngines({
        userId: user.id,
        next,
      });

      const cloudSetup = next === 'cloud_api' || next === 'whats360' ||
          next === 'ycloud' || next === 'dualhook'
        ? 'pending'
        : 'none';
      const noQr = next === 'cloud_api' || next === 'whats360' ||
        next === 'ycloud' || next === 'dualhook';
      // عند تبديل المزود: امسح أصول الربط السابقة حتى لا يظهر «متصل» كاذب
      // (مثل رقم نابو المشترك عند اختيار Meta مباشرة لرقم المحل).
      const providerChanged = prev !== next;
      const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
        {
          user_id: user.id,
          evolution_instance_name: instanceName,
          whatsapp_provider: next,
          cloud_setup_status: cloudSetup,
          status: noQr ? 'disconnected' : 'connecting',
          updated_at: now,
          repair_needed: !noQr,
          ...(providerChanged
            ? {
              cloud_waba_id: null,
              cloud_phone_number_id: null,
              provider_connection_id: null,
              ycloud_from_phone: null,
              whatsapp_phone: null,
              last_connected_at: null,
            }
            : {}),
        },
        { onConflict: 'user_id' },
      );
      if (error) {
        return Response.json({ ok: false, error: error.message }, { status: 500 });
      }

      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'set_provider',
        source: 'client',
        detail: `${prev}->${next}`,
        meta: { cleanup, next },
      });

      if (next === 'evolution') {
        try {
          await Evo.ensureEvolutionInstance(instanceName);
          await Evo.ensureEvolutionWebhook(instanceName);
        } catch (e) {
          console.warn('ensure evolution after set_provider', e);
        }
      } else if (next === 'waha') {
        await ensureEvolutionInstance(instanceName);
        await ensureEvolutionWebhook(instanceName);
      }

      return Response.json({
        ok: true,
        provider: next,
        previous_provider: prev,
        cleanup,
        message_ar: next === 'dualhook' || next === 'ycloud'
          ? 'تم اختيار الإرسال من رقم نابو الرسمي عبر Meta. اضغط ربط واتساب لإكمال الخطوات.'
          : next === 'cloud_api'
          ? 'تم اختيار الربط الرسمي عبر Meta مباشرة. أكمل Embedded Signup من التطبيق.'
          : next === 'whats360'
          ? 'تم اختيار واتس360. أدخل التوكن ومعرّف الجهاز من لوحة whats360.'
          : next === 'evolution'
          ? 'تم اختيار الربط بمسح QR عبر Evolution. امسح الرمز مرة واحدة فقط.'
          : 'تم اختيار محرك QR الاحتياطي (WAHA).',
      });
    } finally {
      await releaseLock(supabase);
    }
  }

  if (action === 'configure_whats360') {
    const parsed = parseWhats360Credentials({
      token: body.whats360_token,
      instanceId: body.whats360_instance_id,
    });
    if (parsed.errorAr || !parsed.token || !parsed.instanceId) {
      return Response.json({
        ok: false,
        error: 'invalid_whats360_credentials',
        message_ar: parsed.errorAr ??
          'بيانات واتس360 غير مكتملة.',
      }, { status: 400 });
    }
    const token = parsed.token;
    const w360Instance = parsed.instanceId;

    await cleanupOtherEngines({ userId: user.id, next: 'whats360' });

    const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
      {
        user_id: user.id,
        evolution_instance_name: instanceName,
        whatsapp_provider: 'whats360',
        whats360_access_token: token,
        whats360_instance_id: w360Instance,
        cloud_setup_status: 'ready',
        status: 'connected',
        repair_needed: false,
        disconnect_cause: null,
        updated_at: now,
        last_connected_at: now,
      },
      { onConflict: 'user_id' },
    );
    if (error) {
      return Response.json({
        ok: false,
        error: error.message,
        message_ar:
          'تعذّر حفظ إعداد واتس360. تأكد من تطبيق ترحيل قاعدة البيانات ثم أعد المحاولة.',
      }, { status: 500 });
    }

    await writeAudit(supabase, {
      userId: user.id,
      instanceName,
      action: 'configure_whats360',
      source: 'client',
      detail: `instance:${w360Instance.slice(0, 24)}`,
      meta: { token_len: token.length },
    });

    return Response.json({
      ok: true,
      provider: 'whats360',
      connected: true,
      message_ar: 'تم ربط واتس360. يمكنك إرسال إشعارات الزبائن الآن.',
    });
  }

  const activeProvider = await readProvider(supabase, user.id);

  if (
    (activeProvider === 'cloud_api' ||
      activeProvider === 'whats360' ||
      activeProvider === 'ycloud' ||
      activeProvider === 'dualhook') &&
    (action === 'qr' || action === 'provision')
  ) {
    if (action === 'provision') {
      return Response.json({
        ok: true,
        provider: activeProvider,
        skipped: true,
        message_ar: activeProvider === 'whats360'
          ? 'واتس360 لا يحتاج provision من نابو.'
          : 'الربط الرسمي لا يحتاج provision من نابو.',
      });
    }
    return Response.json({
      ok: false,
      error: activeProvider === 'whats360'
        ? 'whats360_no_qr'
        : 'official_no_qr',
      provider: activeProvider,
      message_ar: activeProvider === 'whats360'
        ? 'حسابك على واتس360. لا يُستخدم مسح QR من نابو — اربط الجهاز من لوحة whats360.'
        : 'الربط الرسمي لا يستخدم مسح QR. استخدم زر ربط واتساب.',
    }, { status: 400 });
  }

  if (action === 'provision') {
    // لا تُسقط repair_needed عند بدء QR بعد فصل دائم — وإلا يلتقطها الكرون كـ temporary.
    const { data: existingGate } = await supabase
      .from('tenant_whatsapp_gateways')
      .select('repair_needed, disconnect_cause, status, updated_at, last_hard_reset_at')
      .eq('user_id', user.id)
      .maybeSingle();

    // كبح عاصفة provision أثناء connecting / بعد تصفير حديث.
    const statusNow = String(existingGate?.status ?? '');
    if (statusNow === 'connecting' || existingGate?.repair_needed === true) {
      const stampRaw =
        (existingGate?.last_hard_reset_at as string | null | undefined) ??
        (existingGate?.updated_at as string | null | undefined);
      if (stampRaw) {
        const elapsed = Date.now() - Date.parse(stampRaw);
        if (!Number.isNaN(elapsed) && elapsed < PROVISION_COOLDOWN_MS) {
          const retryAfterSeconds = Math.ceil(
            (PROVISION_COOLDOWN_MS - elapsed) / 1000,
          );
          await writeOpsFact(supabase, {
            userId: user.id,
            sessionName: instanceName,
            factType: 'provision_storm',
            code: 'provision_rate_limited',
            rawRef: `provision_rl:${now}`,
            meta: { retry_after_seconds: retryAfterSeconds, status: statusNow },
          });
          return Response.json({
            ok: true,
            instance_name: instanceName,
            repair_needed: existingGate?.repair_needed === true,
            rate_limited: true,
            retry_after_seconds: retryAfterSeconds,
            message_ar:
              'جاري تجهيز الربط. انتظر قليلاً قبل إعادة المحاولة — لا تكثر الضغط.',
          });
        }
      }
    }

    const prevCause = String(existingGate?.disconnect_cause ?? '').toLowerCase();
    const causeLooksPermanent =
      prevCause.includes('device_removed') ||
      prevCause.includes('loggedout') ||
      prevCause.includes('logged_out') ||
      prevCause === 'removed' ||
      prevCause.includes('removed') ||
      /(^|[^0-9])401([^0-9]|$)/.test(prevCause);
    const preserveRepair =
      existingGate?.repair_needed === true || causeLooksPermanent;

    // إن repair_needed: لا ensure فوق رفات — المسح الجذري عند qr/force.
    if (!preserveRepair) {
      await ensureEvolutionInstance(instanceName);
      await ensureEvolutionWebhook(instanceName);
    }
    const webhookOk = true;

    const upsertRow: Record<string, unknown> = {
      user_id: user.id,
      evolution_instance_name: instanceName,
      status: 'connecting',
      updated_at: now,
      repair_needed: preserveRepair,
    };
    if (preserveRepair) {
      // أبقِ السبب للتشخيص؛ صفّر عدّاد restart حتى لا يُعاد تشغيل عبثي إن تغيّر العلم لاحقاً.
      upsertRow.restart_attempts = 0;
      if (existingGate?.disconnect_cause) {
        upsertRow.disconnect_cause = existingGate.disconnect_cause;
      } else if (causeLooksPermanent) {
        upsertRow.disconnect_cause = prevCause.slice(0, 120) || 'permanent';
      }
    }

    const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
      upsertRow,
      { onConflict: 'user_id' },
    );
    if (error) {
      console.error('provision upsert failed', error);
      return Response.json({ ok: false, error: error.message }, { status: 500 });
    }

    await writeAudit(supabase, {
      userId: user.id,
      instanceName,
      action: 'provision',
      source: 'client',
      detail: preserveRepair
        ? 'preserved_repair_needed_until_open'
        : 'ok',
      meta: {
        webhook_ok: webhookOk,
        previous_repair_needed: existingGate?.repair_needed === true,
        previous_status: existingGate?.status ?? null,
        previous_disconnect_cause: existingGate?.disconnect_cause ?? null,
        preserved_repair_needed: preserveRepair,
      },
    });
    await writeDiagnostic({
      userId: user.id,
      instanceName,
      eventType: 'provision',
      severity: 'info',
      connectionState: 'connecting',
      outcome: preserveRepair ? 'connecting_repair_needed' : 'accepted',
      reasonCode: preserveRepair ? 'repair_needed' : null,
      meta: {
        webhook_ok: webhookOk,
        preserved_repair_needed: preserveRepair,
      },
    });
    await writeOpsFact(supabase, {
      userId: user.id,
      sessionName: instanceName,
      factType: 'provision_storm',
      code: 'provision',
      rawRef: `provision:${now}`,
      meta: { preserved_repair_needed: preserveRepair },
    });
    return Response.json({
      ok: true,
      instance_name: instanceName,
      repair_needed: preserveRepair,
    });
  }

  if (action === 'status') {
    // المسار الرسمي / المحسوب: ready_state للواجهة
    if (activeProvider === 'ycloud' || activeProvider === 'dualhook') {
      await syncTemplateStatusesForTenant(supabase, user.id);
      const ready = await computeReadyState(supabase, user.id);
      return Response.json({
        ok: true,
        status: ready.connected ? 'connected' : 'disconnected',
        connected: ready.connected,
        ready_state: ready.readyState,
        phone: ready.phone,
        instance_name: instanceName,
        provider: activeProvider,
        message_ar: readyStateMessageAr(ready.readyState),
      });
    }

    // واتس360: الحالة من السحابة (الجلسة تُدار في لوحة whats360).
    if (activeProvider === 'whats360') {
      const { data: gate } = await supabase
        .from('tenant_whatsapp_gateways')
        .select(
          'status, whatsapp_phone, whats360_instance_id, whats360_access_token, cloud_setup_status',
        )
        .eq('user_id', user.id)
        .maybeSingle();
      const hasCreds =
        String(gate?.whats360_instance_id ?? '').trim().length > 0 &&
        String(gate?.whats360_access_token ?? '').trim().length > 0;
      const ready = String(gate?.cloud_setup_status ?? '') === 'ready' && hasCreds;
      const connected =
        ready && String(gate?.status ?? '') === 'connected';
      return Response.json({
        ok: true,
        status: connected ? 'connected' : 'disconnected',
        connected,
        phone: gate?.whatsapp_phone ?? null,
        instance_name: instanceName,
        provider: 'whats360',
        whats360_ready: ready,
        message_ar: connected
          ? 'واتس360 متصل وجاهز للإرسال.'
          : 'أدخل توكن ومعرّف جهاز واتس360 لإكمال الربط.',
      });
    }

    const live = await readEvolutionLiveState(instanceName);
    if (!live.ok) {
      // الجلسة محذوفة نهائياً (REMOVED) — حدّث السحابة إلى «منفصل» فوراً
      // بدل «خطأ مؤقت» الذي يُبقي التطبيق يعرض «مرتبط» وهي ميتة.
      if (live.notFound) {
        await supabase.from('tenant_whatsapp_gateways').upsert(
          {
            user_id: user.id,
            evolution_instance_name: instanceName,
            status: 'disconnected',
            whatsapp_phone: null,
            last_disconnected_at: now,
            updated_at: now,
            repair_needed: true,
            restart_attempts: 0,
            disconnect_cause: 'removed',
          },
          { onConflict: 'user_id' },
        );
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'status_instance_removed',
          source: 'client_status',
          detail: 'instance_not_found_marked_disconnected',
        });
        await writeDiagnostic({
          userId: user.id,
          instanceName,
          eventType: 'connection',
          severity: 'error',
          connectionState: 'removed',
          outcome: 'disconnected',
          reasonCode: 'instance_removed',
          technicalDetail: 'connectionState_404',
        });
        return Response.json({
          ok: true,
          status: 'disconnected',
          connected: false,
          phone: null,
          raw_state: 'removed',
          instance_name: instanceName,
          repair_needed: true,
          message_ar: 'واتساب منفصل — أعد ربط QR من الإعدادات.',
        });
      }
      return Response.json({
        ok: false,
        error: 'evolution_state_unavailable',
        instance_name: instanceName,
      }, { status: 503 });
    }

    const mapped = live.mapped;
    const patch: Record<string, unknown> = {
      user_id: user.id,
      evolution_instance_name: instanceName,
      status: mapped.status === 'unknown' ? 'disconnected' : mapped.status,
      whatsapp_phone: mapped.phone,
      updated_at: now,
    };
    if (mapped.connected) {
      patch.last_connected_at = now;
      patch.repair_needed = false;
      patch.restart_attempts = 0;
      patch.disconnect_cause = null;
    }
    if (mapped.status === 'disconnected') patch.last_disconnected_at = now;

    const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
      patch,
      { onConflict: 'user_id' },
    );
    if (error) {
      return Response.json({ ok: false, error: error.message }, { status: 500 });
    }

    const repairNeeded = mapped.connected
      ? false
      : await readRepairNeeded(supabase, user.id);

    return Response.json({
      ok: true,
      status: mapped.status,
      connected: mapped.connected,
      phone: mapped.phone,
      raw_state: mapped.rawState,
      instance_name: instanceName,
      repair_needed: repairNeeded,
    });
  }

  // بلاغ من العميل (مثلاً بعد فشل إرسال مصنَّف whatsapp_disconnected).
  // لا logout هنا — الفصل الحقيقي فقط عبر action: disconnect (PIN).
  // تحقق حي من Evolution: إن الجلسة open → false_alarm دون تصديق «منفصل»؛
  // إن غير open → حدّث السحابة من الحالة الحية فقط.
  if (action === 'report_disconnected') {
    try {
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'report_disconnected',
        source: 'client_status',
        detail: 'client_reported_disconnected_pending_live_check',
      });

      const live = await readEvolutionLiveState(instanceName);
      if (!live.ok && live.notFound) {
        // الجلسة محذوفة (REMOVED): البلاغ صحيح — صدّقه وحدّث السحابة.
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'report_disconnected_confirmed',
          source: 'client_status',
          detail: 'instance_not_found_marked_disconnected',
        });
        await supabase.from('tenant_whatsapp_gateways').upsert(
          {
            user_id: user.id,
            evolution_instance_name: instanceName,
            status: 'disconnected',
            whatsapp_phone: null,
            last_disconnected_at: now,
            updated_at: now,
          },
          { onConflict: 'user_id' },
        );
        return Response.json({
          ok: true,
          confirmed: true,
          false_alarm: false,
          connected: false,
          status: 'disconnected',
          raw_state: 'removed',
          instance_name: instanceName,
        });
      }
      if (!live.ok) {
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'report_disconnected',
          source: 'client_status',
          detail: 'evolution_unavailable_status_unchanged',
        });
        return Response.json({
          ok: true,
          status_unchanged: true,
          evolution_unavailable: true,
          instance_name: instanceName,
        });
      }

      const mapped = live.mapped;

      // جلسة حية مفتوحة: التصنيف كاذب — لا نكتب disconnected؛ نزامِن الحقيقة المتصلة.
      if (mapped.connected) {
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'report_disconnected_false_alarm',
          source: 'client_status',
          detail: 'false_alarm_evolution_still_open',
          meta: {
            raw_state: mapped.rawState,
            phone: mapped.phone,
          },
        });
        const { error: healErr } = await supabase
          .from('tenant_whatsapp_gateways')
          .upsert(
            {
              user_id: user.id,
              evolution_instance_name: instanceName,
              status: mapped.status === 'unknown' ? 'connected' : mapped.status,
              whatsapp_phone: mapped.phone,
              last_connected_at: now,
              updated_at: now,
            },
            { onConflict: 'user_id' },
          );
        if (healErr) {
          console.warn('report_disconnected false_alarm heal failed', healErr);
        }
        return Response.json({
          ok: true,
          false_alarm: true,
          connected: true,
          status: mapped.status,
          phone: mapped.phone,
          raw_state: mapped.rawState,
          instance_name: instanceName,
        });
      }

      // غير open: إن repair_needed → لا soft-reconnect.
      const repairNeeded = await readRepairNeeded(supabase, user.id);
      if (repairNeeded) {
        const cloudStatus =
          mapped.status === 'unknown' ? 'disconnected' : mapped.status;
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'report_disconnected_confirmed',
          source: 'client_status',
          detail: 'repair_needed_skip_soft_reconnect',
          meta: { raw_state: mapped.rawState, status: cloudStatus },
        });
        await supabase.from('tenant_whatsapp_gateways').upsert(
          {
            user_id: user.id,
            evolution_instance_name: instanceName,
            status: cloudStatus,
            whatsapp_phone: mapped.phone,
            last_disconnected_at: now,
            updated_at: now,
            repair_needed: true,
          },
          { onConflict: 'user_id' },
        );
        return Response.json({
          ok: true,
          confirmed: true,
          false_alarm: false,
          soft_reconnect: false,
          repair_needed: true,
          connected: false,
          status: cloudStatus,
          phone: mapped.phone,
          raw_state: mapped.rawState,
          instance_name: instanceName,
        });
      }

      // غير open: جرّب soft reconnect قبل تصديق الانقطاع (بدون hardReset/QR).
      const soft = await softReconnectEvolutionSession(instanceName);
      await auditSoftReconnect(supabase, {
        userId: user.id,
        instanceName,
        source: 'report_disconnected',
        soft,
      });
      if (soft.ok) {
        const healed = await readEvolutionLiveState(instanceName);
        const phone = healed.mapped.phone ?? mapped.phone;
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'report_disconnected_false_alarm',
          source: 'client_status',
          detail: 'healed_by_soft_reconnect',
          meta: {
            raw_state: healed.mapped.rawState || soft.finalState,
            phone,
            soft_reconnect_ms: soft.elapsedMs,
          },
        });
        await supabase.from('tenant_whatsapp_gateways').upsert(
          {
            user_id: user.id,
            evolution_instance_name: instanceName,
            status: 'connected',
            whatsapp_phone: phone,
            last_connected_at: now,
            updated_at: now,
            repair_needed: false,
            restart_attempts: 0,
            disconnect_cause: null,
          },
          { onConflict: 'user_id' },
        );
        return Response.json({
          ok: true,
          false_alarm: true,
          soft_reconnect: true,
          repair_needed: false,
          connected: true,
          status: 'connected',
          phone,
          raw_state: healed.mapped.rawState || soft.finalState,
          instance_name: instanceName,
        });
      }

      // soft reconnect فشل: صدّق الحالة الحية وحدّث السحابة.
      const cloudStatus =
        mapped.status === 'unknown' ? 'disconnected' : mapped.status;
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'report_disconnected_confirmed',
        source: 'client_status',
        detail: 'confirmed_not_open_after_soft_reconnect',
        meta: {
          raw_state: mapped.rawState,
          status: cloudStatus,
          soft_final_state: soft.finalState,
          soft_elapsed_ms: soft.elapsedMs,
        },
      });
      const { error: confErr } = await supabase
        .from('tenant_whatsapp_gateways')
        .upsert(
          {
            user_id: user.id,
            evolution_instance_name: instanceName,
            status: cloudStatus,
            whatsapp_phone: mapped.phone,
            last_disconnected_at: now,
            updated_at: now,
          },
          { onConflict: 'user_id' },
        );
      if (confErr) {
        console.warn('report_disconnected confirm upsert failed', confErr);
      }
      return Response.json({
        ok: true,
        confirmed: true,
        false_alarm: false,
        soft_reconnect: false,
        connected: false,
        status: cloudStatus,
        phone: mapped.phone,
        raw_state: mapped.rawState,
        instance_name: instanceName,
      });
    } catch (e) {
      console.warn('report_disconnected handler failed', e);
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'report_disconnected',
        source: 'client_status',
        detail: 'handler_error_status_unchanged',
        meta: {
          error: e instanceof Error ? e.message : String(e),
        },
      });
      return Response.json({
        ok: true,
        status_unchanged: true,
        instance_name: instanceName,
      });
    }
  }

  if (action === 'disconnect') {
    const locked = await acquireLock(supabase);
    if (!locked.ok) {
      return Response.json({
        ok: false,
        error: locked.error,
        retry_after_seconds: locked.retryAfterSeconds,
      }, { status: 409 });
    }

    try {
      const rate = await checkHardResetRateLimit(
        supabase,
        user.id,
        DISCONNECT_COOLDOWN_MS,
      );
      if (!rate.ok) {
        return Response.json({
          ok: false,
          error: 'rate_limited',
          retry_after_seconds: rate.retryAfterSeconds,
          message_ar:
            'تم فصل/تصفير الجلسة مؤخراً. انتظر قليلاً قبل المحاولة مرة أخرى.',
        }, { status: 429 });
      }

      // واتس360: قطع من نابو = مسح المفاتيح محلياً (الجلسة تبقى في لوحة whats360).
      if (activeProvider === 'whats360') {
        await supabase.from('tenant_whatsapp_gateways').upsert(
          {
            user_id: user.id,
            evolution_instance_name: instanceName,
            whatsapp_provider: 'whats360',
            whats360_access_token: null,
            whats360_instance_id: null,
            cloud_setup_status: 'pending',
            status: 'disconnected',
            whatsapp_phone: null,
            last_disconnected_at: now,
            updated_at: now,
            repair_needed: false,
            disconnect_cause: 'user_disconnect',
          },
          { onConflict: 'user_id' },
        );
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'disconnect',
          source: 'user_disconnect',
          detail: 'whats360_credentials_cleared',
        });
        return Response.json({
          ok: true,
          provider: 'whats360',
          evolution_ok: true,
          message_ar:
            'تم فصل واتس360 من نابو. أعد إدخال التوكن لاحقاً إن أردت.',
        });
      }

      let evolutionError: string | null = null;
      let purge: PurgeRecreateResult | null = null;
      try {
        // فصل المستخدم = مسح جذري (لا logout+restart فوق رفات).
        purge = await purgeAndRecreateEvolutionSession(instanceName);
        if (!purge.ok) {
          evolutionError = purge.detail;
        }
      } catch (e) {
        evolutionError = e instanceof Error ? e.message : 'purge_failed';
        console.warn('disconnect purge failed', e);
      }

      await markHardReset(supabase, user.id, 'user_disconnect', {
        purgeOk: purge?.ok === true,
        purgeDetail: purge?.detail ?? null,
        evolutionError,
      });
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'hard_reset',
        source: 'user_disconnect',
        detail: evolutionError ?? 'purge_ok',
        meta: {
          mode: 'purge_and_recreate',
          purge,
        },
      });
      await writeDiagnostic({
        userId: user.id,
        instanceName,
        eventType: 'hard_reset',
        severity: 'warn',
        connectionState: 'disconnected',
        outcome: 'disconnected',
        reasonCode: evolutionError ?? 'user_disconnect',
        technicalDetail: purge
          ? `purge_ok=${purge.ok};detail=${purge.detail};elapsed=${purge.elapsedMs}`
          : 'purge_threw',
        meta: { source: 'user_disconnect', mode: 'purge_and_recreate' },
      });
      await writeOpsFact(supabase, {
        userId: user.id,
        sessionName: instanceName,
        factType: 'provision_storm',
        code: 'hard_reset',
        rawRef: `hard_reset:${now}:user_disconnect`,
        meta: { mode: 'purge_and_recreate', purge },
      });

      const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
        {
          user_id: user.id,
          evolution_instance_name: instanceName,
          status: 'disconnected',
          whatsapp_phone: null,
          last_disconnected_at: now,
          updated_at: now,
        },
        { onConflict: 'user_id' },
      );
      if (error) {
        return Response.json({ ok: false, error: error.message }, { status: 500 });
      }

      return Response.json({
        ok: purge?.ok === true,
        status: 'disconnected',
        evolution_ok: purge?.ok === true,
        purge_ok: purge?.ok === true,
        purge_detail: purge?.detail ?? evolutionError,
        evolution_error: evolutionError,
        message_ar: purge?.ok
          ? 'تم إلغاء الربط ومسح الجلسة من الجذور.'
          : 'تعذّر مسح الجلسة بالكامل. أعد المحاولة بعد قليل أو تواصل مع الدعم.',
      });
    } finally {
      await releaseLock(supabase);
    }
  }

  if (action === 'qr') {
    // مسار Evolution: QR عبر Baileys (المحرك السابق)
    if (activeProvider === 'evolution') {
      try {
        await Evo.ensureEvolutionInstance(instanceName);
        await Evo.ensureEvolutionWebhook(instanceName);
      } catch (e) {
        console.warn('evolution ensure on qr', e);
      }
      const live = await Evo.readEvolutionLiveState(instanceName);
      if (live.ok && live.mapped.connected) {
        await supabase.from('tenant_whatsapp_gateways').upsert(
          {
            user_id: user.id,
            evolution_instance_name: instanceName,
            status: 'connected',
            whatsapp_phone: live.mapped.phone,
            last_connected_at: now,
            updated_at: now,
            repair_needed: false,
            whatsapp_provider: 'evolution',
          },
          { onConflict: 'user_id' },
        );
        return Response.json({
          ok: true,
          already_connected: true,
          connected: true,
          base64: null,
          pairing_code: null,
          phone: live.mapped.phone,
          instance_name: instanceName,
          provider: 'evolution',
          message_ar: 'واتساب متصل مسبقاً عبر Evolution.',
        });
      }
      const { ok, data } = await Evo.fetchEvolutionConnectQr(instanceName);
      const extracted = extractQrPayload(data as Record<string, unknown>);
      // extractQrPayload from waha — same shape; evolution has its own too
      const extractedEvo = Evo.extractQrPayload(
        (data ?? {}) as Record<string, unknown>,
      );
      const base64 = extractedEvo.base64 ?? extracted.base64;
      const pairing = extractedEvo.pairingCode ?? extracted.pairingCode;
      await supabase.from('tenant_whatsapp_gateways').upsert(
        {
          user_id: user.id,
          evolution_instance_name: instanceName,
          status: 'connecting',
          updated_at: now,
          whatsapp_provider: 'evolution',
        },
        { onConflict: 'user_id' },
      );
      return Response.json({
        ok: ok && base64 != null,
        already_connected: false,
        connected: false,
        base64,
        pairing_code: pairing,
        expires_hint_seconds: 50,
        instance_name: instanceName,
        provider: 'evolution',
        message_ar: base64 != null
          ? 'امسح الرمز مرة واحدة — مسار Evolution.'
          : 'جاري تجهيز الرمز. انتظر قليلاً.',
      });
    }

    const ensured = await ensureEvolutionInstance(instanceName);
    await ensureEvolutionWebhook(instanceName);

    let live = await readEvolutionLiveState(instanceName);
    // جلسة غير موجودة بعد ensure (أو تأخير إنشاء) — أعد المحاولة ثم تابع لجلب QR
    // بدل 503 الذي يمنع ظهور الرمز في التطبيق.
    if (!live.ok && live.notFound) {
      await ensureEvolutionInstance(instanceName);
      await new Promise((r) => setTimeout(r, 800));
      live = await readEvolutionLiveState(instanceName);
    }
    if (!live.ok && live.notFound) {
      // تابع كمنفصل: fetchConnectQr سيحاول start/restart
      live = {
        ok: true,
        notFound: true,
        mapped: {
          connected: false,
          status: 'disconnected',
          phone: null,
          rawState: 'missing',
          readable: true,
        },
      };
    }
    if (!live.ok) {
      return Response.json({
        ok: false,
        error: 'waha_state_unavailable',
        detail: ensured.detail ?? null,
        message_ar: 'تعذّر قراءة حالة واتساب من السيرفر. أعد المحاولة دون فصل الجلسة.',
        instance_name: instanceName,
      }, { status: 503 });
    }

    // جلسة مفتوحة: لا logout أبداً عبر qr (حتى force_reset من تطبيق قديم).
    if (live.mapped.connected) {
      await supabase.from('tenant_whatsapp_gateways').upsert(
        {
          user_id: user.id,
          evolution_instance_name: instanceName,
          status: 'connected',
          whatsapp_phone: live.mapped.phone,
          last_connected_at: now,
          updated_at: now,
        },
        { onConflict: 'user_id' },
      );
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'qr_ignored_already_connected',
        source: body.force_reset === true ? 'user_force_reset' : 'qr',
        detail: 'ignored_force_reset_while_open',
      });
      return Response.json({
        ok: true,
        already_connected: true,
        connected: true,
        base64: null,
        pairing_code: null,
        phone: live.mapped.phone,
        instance_name: instanceName,
        ignored_force_reset: body.force_reset === true,
        message_ar:
          'واتساب متصل مسبقاً. لتغيير الرقم: إلغاء الربط أولاً ثم امسح QR جديداً.',
      });
    }

    // أثناء connecting: لا hardReset — إلا إن repair_needed أو force_reset (يحتاج مسح جذري).
    const needsRepairEarly = await readRepairNeeded(supabase, user.id);
    if (
      live.mapped.status === 'connecting' &&
      body.force_reset !== true &&
      !needsRepairEarly
    ) {
      await supabase.from('tenant_whatsapp_gateways').upsert(
        {
          user_id: user.id,
          evolution_instance_name: instanceName,
          status: 'connecting',
          updated_at: now,
        },
        { onConflict: 'user_id' },
      );
      const soft = await fetchEvolutionConnectQr(instanceName);
      const extracted = extractQrPayload(soft.data);
      return Response.json({
        ok: extracted.base64 != null,
        already_connected: false,
        connected: false,
        connecting: true,
        base64: extracted.base64,
        pairing_code: extracted.pairingCode,
        expires_hint_seconds: 50,
        instance_name: instanceName,
        message_ar:
          extracted.base64 != null
            ? 'جاري الربط — امسح الرمز. لا تضغط إعادة ربط من جهاز آخر.'
            : 'جاري الربط على السيرفر. انتظر قليلاً ثم حدّث الرمز.',
      });
    }

    const locked = await acquireLock(supabase);
    if (!locked.ok) {
      return Response.json({
        ok: false,
        error: locked.error,
        retry_after_seconds: locked.retryAfterSeconds,
        message_ar: 'عملية ربط أخرى جارية على نفس الحساب. انتظر لحظات.',
      }, { status: 409 });
    }

    try {
      const wantsReset = body.force_reset === true;
      const needsRepair = await readRepairNeeded(supabase, user.id);
      const rawUpper = String(live.mapped.rawState ?? '').toUpperCase();
      const sessionLooksDead =
        live.notFound === true ||
        live.mapped.status === 'disconnected' ||
        rawUpper === 'FAILED' ||
        rawUpper === 'STOPPED';

      // مسح جذري مرة واحدة عند: force_reset (بعد فشل soft) أو repair + جلسة ميتة/ملوّثة.
      // أثناء connecting بعد مسح حديث: لا نُعيد DELETE في كل استطلاع QR.
      let attemptPurge =
        (wantsReset && needsRepair) ||
        (needsRepair && sessionLooksDead) ||
        (wantsReset && !needsRepair); // soft أولاً ثم purge إن فشل

      if (attemptPurge && wantsReset && !needsRepair) {
        const soft = await softReconnectEvolutionSession(instanceName);
        await auditSoftReconnect(supabase, {
          userId: user.id,
          instanceName,
          source: 'user_force_reset',
          soft,
        });
        if (soft.ok) {
          const healed = await readEvolutionLiveState(instanceName);
          const phone = healed.mapped.phone ?? null;
          await supabase.from('tenant_whatsapp_gateways').upsert(
            {
              user_id: user.id,
              evolution_instance_name: instanceName,
              status: 'connected',
              whatsapp_phone: phone,
              last_connected_at: now,
              updated_at: now,
              repair_needed: false,
              restart_attempts: 0,
              disconnect_cause: null,
            },
            { onConflict: 'user_id' },
          );
          return Response.json({
            ok: true,
            already_connected: true,
            connected: true,
            soft_reconnect: true,
            repair_needed: false,
            base64: null,
            pairing_code: null,
            phone,
            instance_name: instanceName,
            ignored_force_reset: true,
            message_ar:
              'تمت إعادة إيقاظ جلسة واتساب الحالية بنجاح — لا حاجة لمسح QR جديد.',
          });
        }
      }

      // repair + connecting بعد مسح سابق: لا purge متكرر
      if (needsRepair && !wantsReset && live.mapped.status === 'connecting') {
        attemptPurge = false;
      }

      if (attemptPurge) {
        const rate = await checkHardResetRateLimit(
          supabase,
          user.id,
          FORCE_RESET_COOLDOWN_MS,
        );
        if (!rate.ok) {
          if (wantsReset && !needsRepair) {
            return Response.json({
              ok: false,
              error: 'rate_limited',
              retry_after_seconds: rate.retryAfterSeconds,
              message_ar:
                'تمت محاولة تصفير الجلسة مؤخراً. انتظر حتى 10 دقائق أو استخدم إلغاء الربط ثم QR.',
            }, { status: 429 });
          }
          // repair ضمن cooldown: تابع لجلب QR فقط (المسح تم سابقاً على الأرجح)
          await writeAudit(supabase, {
            userId: user.id,
            instanceName,
            action: 'purge_skipped_cooldown',
            source: 'qr',
            detail: `retry_after=${rate.retryAfterSeconds}`,
          });
        } else {
          const purge = await purgeAndRecreateEvolutionSession(instanceName);
          await markHardReset(supabase, user.id, 'user_force_reset', {
            purge,
            repair_needed: needsRepair,
          });
          await writeAudit(supabase, {
            userId: user.id,
            instanceName,
            action: 'hard_reset',
            source: wantsReset ? 'user_force_reset' : 'qr',
            detail: needsRepair
              ? `qr_purge_repair_needed:${purge.detail}`
              : `qr_purge_after_soft_reconnect_failed:${purge.detail}`,
            meta: {
              repair_needed: needsRepair,
              mode: 'purge_and_recreate',
              purge,
            },
          });
          await writeOpsFact(supabase, {
            userId: user.id,
            sessionName: instanceName,
            factType: 'provision_storm',
            code: 'hard_reset',
            rawRef: `hard_reset:${now}:purge`,
            meta: { mode: 'purge_and_recreate', purge },
          });

          if (!purge.ok) {
            return Response.json({
              ok: false,
              error: 'purge_failed',
              purge_detail: purge.detail,
              timed_out: purge.timedOut,
              message_ar: purge.timedOut
                ? 'مسح الجلسة استغرق وقتاً طويلاً ولم يُؤكَّد. انتظر دقيقة ثم أعد المحاولة مرة واحدة فقط.'
                : 'تعذّر مسح الجلسة القديمة من الجذور. أعد المحاولة بعد قليل.',
              instance_name: instanceName,
            }, { status: 503 });
          }
        }
      }

      let { ok, data } = await fetchEvolutionConnectQr(instanceName);
      // WORKING/متصل: لا QR ولا hardReset — أعد already_connected فوراً.
      if (data?.already_connected === true) {
        const phone =
          (typeof data.phone === 'string' ? data.phone : null) ??
          (await readEvolutionLiveState(instanceName)).mapped.phone;
        const { data: prevGate } = await supabase
          .from('tenant_whatsapp_gateways')
          .select('status')
          .eq('user_id', user.id)
          .maybeSingle();
        const wasConnected = String(prevGate?.status ?? '') === 'connected';
        await supabase.from('tenant_whatsapp_gateways').upsert(
          {
            user_id: user.id,
            evolution_instance_name: instanceName,
            status: 'connected',
            whatsapp_phone: phone,
            last_connected_at: now,
            updated_at: now,
            repair_needed: false,
            restart_attempts: 0,
            disconnect_cause: null,
          },
          { onConflict: 'user_id' },
        );
        let ownerEmail: { sent: boolean; detail: string } | null = null;
        if (!wasConnected) {
          const copy = connectedEmailCopy(phone);
          ownerEmail = await notifyOwnerEmail(supabase, {
            userId: user.id,
            instanceName,
            kind: 'whatsapp_connected',
            subject: copy.subject,
            bodyAr: copy.bodyAr,
          });
        }
        return Response.json({
          ok: true,
          already_connected: true,
          connected: true,
          base64: null,
          pairing_code: null,
          phone,
          instance_name: instanceName,
          owner_email: ownerEmail,
          message_ar:
            'واتساب متصل مسبقاً. لتغيير الرقم: إلغاء الربط أولاً ثم امسح QR جديداً.',
        });
      }
      let extracted = extractQrPayload(data);

      if (!extracted.base64) {
        const again = await readEvolutionLiveState(instanceName);
        if (again.ok && again.mapped.connected) {
          return Response.json({
            ok: true,
            already_connected: true,
            connected: true,
            base64: null,
            pairing_code: null,
            phone: again.mapped.phone,
            instance_name: instanceName,
          });
        }
        if (again.ok && again.mapped.status === 'connecting') {
          return Response.json({
            ok: false,
            connecting: true,
            error: 'connecting',
            message_ar: 'الجلسة قيد الربط. انتظر ثم حدّث الرمز دون إعادة تصفير.',
            instance_name: instanceName,
          });
        }
        if (!again.ok) {
          return Response.json({
            ok: false,
            error: 'evolution_state_unavailable',
            message_ar: 'تعذّر التأكد من حالة الجلسة — لم يُنفَّذ فصل احتياطي.',
            instance_name: instanceName,
          }, { status: 503 });
        }

        // قبل المسح الاحتياطي: soft reconnect مرة أخرى إن أمكن — إلا repair_needed.
        if (!(await readRepairNeeded(supabase, user.id))) {
          const softFb = await softReconnectEvolutionSession(instanceName);
          await auditSoftReconnect(supabase, {
            userId: user.id,
            instanceName,
            source: 'server_qr_fallback',
            soft: softFb,
          });
          if (softFb.ok) {
            const healed = await readEvolutionLiveState(instanceName);
            await supabase.from('tenant_whatsapp_gateways').upsert(
              {
                user_id: user.id,
                evolution_instance_name: instanceName,
                status: 'connected',
                whatsapp_phone: healed.mapped.phone,
                last_connected_at: now,
                updated_at: now,
                repair_needed: false,
                restart_attempts: 0,
                disconnect_cause: null,
              },
              { onConflict: 'user_id' },
            );
            return Response.json({
              ok: true,
              already_connected: true,
              connected: true,
              soft_reconnect: true,
              repair_needed: false,
              base64: null,
              pairing_code: null,
              phone: healed.mapped.phone,
              instance_name: instanceName,
              message_ar:
                'تمت إعادة إيقاظ جلسة واتساب الحالية — لا حاجة لمسح QR جديد.',
            });
          }
        }

        const rate = await checkHardResetRateLimit(
          supabase,
          user.id,
          FORCE_RESET_COOLDOWN_MS,
        );
        if (!rate.ok) {
          return Response.json({
            ok: false,
            error: 'rate_limited',
            retry_after_seconds: rate.retryAfterSeconds,
            message_ar: 'تعذّر جلب QR وتم تجاوز حد التصفير. انتظر ثم أعد المحاولة.',
          }, { status: 429 });
        }

        const purgeFb = await purgeAndRecreateEvolutionSession(instanceName);
        await markHardReset(supabase, user.id, 'server_qr_fallback', {
          purge: purgeFb,
        });
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'hard_reset',
          source: 'server_qr_fallback',
          detail: `no_base64_purge:${purgeFb.detail}`,
          meta: { mode: 'purge_and_recreate', purge: purgeFb },
        });
        if (!purgeFb.ok) {
          return Response.json({
            ok: false,
            error: 'purge_failed',
            purge_detail: purgeFb.detail,
            timed_out: purgeFb.timedOut,
            message_ar: purgeFb.timedOut
              ? 'مسح الجلسة استغرق وقتاً طويلاً ولم يُؤكَّد. انتظر ثم أعد المحاولة مرة واحدة.'
              : 'تعذّر مسح الجلسة قبل جلب الرمز. أعد المحاولة بعد قليل.',
            instance_name: instanceName,
          }, { status: 503 });
        }
        ({ ok, data } = await fetchEvolutionConnectQr(instanceName));
        extracted = extractQrPayload(data);
      }

      await supabase.from('tenant_whatsapp_gateways').upsert(
        {
          user_id: user.id,
          evolution_instance_name: instanceName,
          status: 'connecting',
          updated_at: now,
        },
        { onConflict: 'user_id' },
      );

      return Response.json({
        ok: ok && extracted.base64 != null,
        already_connected: false,
        connected: false,
        base64: extracted.base64,
        pairing_code: extracted.pairingCode,
        expires_hint_seconds: 50,
        instance_name: instanceName,
      });
    } finally {
      await releaseLock(supabase);
    }
  }

  // إرسال رسالة نصية عبر Evolution — نفس مسار HTTPS الذي يعمل لـ QR/status.
  // يتجنّب اعتماد التطبيق على n8n :5678 الذي تحجبه شبكات الجوال.
  if (action === 'send_text') {
    const phoneRaw = (body.customer_phone ?? '').toString().trim();
    const text = (body.message_text ?? '').toString().trim();
    const phone = normalizeIraqWhatsappDigits(phoneRaw);
    if (!phone) {
      const correlationId = newCorrelationId();
      await writeDiagnostic({
        userId: user.id,
        instanceName,
        eventType: 'send_attempt',
        severity: 'warn',
        correlationId,
        recipientPhone: phoneRaw || null,
        outcome: 'invalid_phone',
        reasonCode: 'invalid_phone',
        technicalDetail: 'empty_or_unparseable_phone',
      });
      return Response.json({
        ok: false,
        reason: 'invalid_phone',
        detail: 'customer_phone',
        mode: 'text',
        sent_to: '',
        correlation_id: correlationId,
      }, { status: 400 });
    }
    if (!text) {
      return Response.json({
        ok: false,
        reason: 'missing_field',
        detail: 'message_text',
        mode: 'text',
        sent_to: phone,
      }, { status: 400 });
    }

    const orderRefForWallet = (body.order_id ?? '').toString().trim();
    const employeeForWallet = (body.employee_name ?? '').toString().trim();
    const textAttemptId = (body.attempt_id ?? '').toString().trim();
    // attempt_id من العميل يثبت المفتاح عبر إعادة المحاولة بعد انقطاع الرد.
    const textIdem = textAttemptId
      ? `text_attempt:${user.id}:${textAttemptId}`
      : orderRefForWallet
      ? `text_card:${user.id}:${orderRefForWallet}`
      : `text:${user.id}:${phone}:${text.slice(0, 48)}:${Date.now()}`;
    // نجاح سابق بنفس المفتاح → لا ترسل ولا تخصم مرة ثانية.
    if (textAttemptId || orderRefForWallet) {
      try {
        const { data: existingText } = await writeClient(supabase)
          .from('whatsapp_message_logs')
          .select('id, status, provider_message_id')
          .eq('tenant_user_id', user.id)
          .eq('idempotency_key', textIdem)
          .maybeSingle();
        const st = String(existingText?.status ?? '');
        if (
          existingText &&
          (st === 'sent' || st === 'delivered' || st === 'read')
        ) {
          return Response.json({
            ok: true,
            reason: 'idempotent_hit',
            detail: 'idempotent_hit',
            mode: 'text',
            sent_to: phone,
            provider_message_id: existingText.provider_message_id ?? undefined,
          });
        }
      } catch (e) {
        console.warn('send_text idempotency lookup failed', e);
      }
    }
    const textWallet = await debitWalletForSend(supabase, {
      tenantUserId: user.id,
      idempotencyKey: textIdem,
      provider: activeProvider,
      sendKind: employeeForWallet || orderRefForWallet
        ? 'oil_change_card'
        : 'campaign_or_text',
    });
    if (!textWallet.ok) return walletRejectResponse(textWallet);

    const textWalletGate = await gateProviderSendAfterWallet(supabase, {
      tenantUserId: user.id,
      idempotencyKey: textIdem,
      wallet: textWallet,
    });
    {
      const early = providerGateResponse(textWalletGate, {
        mode: 'text',
        sent_to: phone,
      });
      if (early) return early;
    }

    const textClaimGate = await claimSendLogRow(supabase, {
      tenantUserId: user.id,
      idempotencyKey: textIdem,
      toPhone: phone,
      provider: activeProvider,
      templateKey: employeeForWallet || orderRefForWallet
        ? 'oil_change_card'
        : null,
      orderRef: orderRefForWallet || null,
      employeeName: employeeForWallet || null,
      body: text,
    });
    {
      const early = providerGateResponse(textClaimGate, {
        mode: 'text',
        sent_to: phone,
      });
      if (early) return early;
    }

    /// بطاقة الغيار قد تُرسل نصاً حراً لا قالباً، فنسجّل الإسناد هنا أيضاً
    /// وإلا نُسب تقييم العميل لبطاقة أقدم.
    const logOutboundText = async (
      provider: string,
      providerMessageId: string | null,
      ok: boolean,
      failDetail?: string | null,
    ): Promise<void> => {
      const employeeName = (body.employee_name ?? '').toString().trim();
      const orderRef = (body.order_id ?? '').toString().trim();
      if (!employeeName && !orderRef) return;
      try {
        const db = writeClient(supabase);
        const errorJson = ok
          ? null
          : formatWaLogError({
            source: 'gateway',
            code: codeFromGatewayDetail(failDetail),
            title: '',
            message: failDetail ?? '',
          });
        // إن وُجد سجل بنفس المفتاح (فشل سابق): UPDATE لا INSERT — وإلا يكسر unique.
        const { data: existingLog } = await db
          .from('whatsapp_message_logs')
          .select('id')
          .eq('tenant_user_id', user.id)
          .eq('idempotency_key', textIdem)
          .maybeSingle();
        if (existingLog?.id) {
          const { error: updErr } = await db
            .from('whatsapp_message_logs')
            .update({
              status: ok ? 'sent' : 'failed',
              provider_message_id: providerMessageId,
              error: errorJson,
              to_phone: phone,
              body: text,
              employee_name: employeeName || null,
              order_ref: orderRef || null,
              provider,
            })
            .eq('id', existingLog.id)
            .eq('tenant_user_id', user.id);
          if (updErr) {
            console.warn('send_text log update failed', updErr.message);
          }
          return;
        }
        await db.from('whatsapp_message_logs').insert({
          tenant_user_id: user.id,
          channel: 'whatsapp',
          provider,
          template_key: 'oil_change_card',
          to_phone: phone,
          status: ok ? 'sent' : 'failed',
          provider_message_id: providerMessageId,
          error: errorJson,
          order_ref: orderRef || null,
          employee_name: employeeName || null,
          body: text,
          idempotency_key: textIdem,
        });
      } catch (e) {
        console.warn('send_text log upsert failed', e);
      }
    };

    // —— مسار Dualhook / YCloud Transport (نص حر؛ البطاقة عبر send_oil_change_card) ——
    if (activeProvider === 'ycloud' || activeProvider === 'dualhook') {
      const transport = getWhatsAppProvider(activeProvider);
      const { data: gate } = await supabase
        .from('tenant_whatsapp_gateways')
        .select(
          'ycloud_from_phone, whatsapp_phone, status, cloud_phone_number_id',
        )
        .eq('user_id', user.id)
        .maybeSingle();
      const from = String(
        gate?.ycloud_from_phone ?? gate?.whatsapp_phone ?? '',
      ).trim();
      const phoneNumberId = String(gate?.cloud_phone_number_id ?? '').trim();
      const readyEnough = activeProvider === 'dualhook'
        ? String(gate?.status) === 'connected' && !!phoneNumberId
        : String(gate?.status) === 'connected' && !!from;
      if (!transport || !readyEnough) {
        return Response.json({
          ok: false,
          reason: `${activeProvider}_not_ready`,
          detail: 'not_connected',
          mode: activeProvider,
          sent_to: phone,
          message_ar: 'واتساب الرسمي غير جاهز للإرسال.',
        }, { status: 409 });
      }
      const sent = await transport.sendText({
        tenantUserId: user.id,
        fromPhoneE164: from || undefined,
        toPhoneE164: phone,
        body: text,
        phoneNumberId: phoneNumberId || undefined,
      });
      await logOutboundText(
        activeProvider,
        sent.providerMessageId ?? null,
        sent.ok,
        sent.detail,
      );
      if (!sent.ok) {
        return Response.json({
          ok: false,
          reason: `${activeProvider}_send_failed`,
          detail: sent.detail ?? 'error',
          mode: activeProvider,
          sent_to: phone,
          message_ar: 'فشل الإرسال عبر واتساب الرسمي.',
        }, { status: 502 });
      }
      return Response.json({
        ok: true,
        mode: activeProvider,
        sent_to: phone,
        message_id: sent.providerMessageId ?? null,
      });
    }

    // —— مسار واتس360 ——
    if (activeProvider === 'whats360') {
      const { data: gate } = await supabase
        .from('tenant_whatsapp_gateways')
        .select(
          'whats360_instance_id, whats360_access_token, cloud_setup_status, status',
        )
        .eq('user_id', user.id)
        .maybeSingle();
      const token = String(gate?.whats360_access_token ?? '').trim();
      const w360Instance = String(gate?.whats360_instance_id ?? '').trim();
      const setup = String(gate?.cloud_setup_status ?? 'none');
      if (!token || !w360Instance || setup !== 'ready') {
        return Response.json({
          ok: false,
          reason: 'whats360_not_ready',
          detail: 'missing_credentials',
          mode: 'whats360',
          sent_to: phone,
          message_ar:
            'واتس360 غير جاهز. أدخل التوكن ومعرّف الجهاز من شاشة الربط.',
        }, { status: 409 });
      }
      const sent = await whats360SendText({
        token,
        instanceId: w360Instance,
        toDigits: phone,
        message: text,
      });
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'send_text',
        source: 'client_notify',
        detail: sent.ok ? 'whats360_ok' : (sent.detail ?? 'whats360_fail'),
        meta: { provider: 'whats360', message_id: sent.messageId ?? null },
      });
      if (!sent.ok) {
        return Response.json({
          ok: false,
          reason: 'whats360_send_failed',
          detail: sent.detail ?? 'error',
          mode: 'whats360',
          sent_to: phone,
          message_ar: 'فشل الإرسال عبر واتس360. تحقق من التوكن والجهاز والرقم.',
        }, { status: 502 });
      }
      return Response.json({
        ok: true,
        reason: 'ok',
        detail: 'whats360',
        mode: 'whats360',
        sent_to: phone,
        message_id: sent.messageId ?? null,
      });
    }

    // —— مسار واتساب الرسمي (Cloud API) ——
    if (activeProvider === 'cloud_api') {
      const { data: gate } = await supabase
        .from('tenant_whatsapp_gateways')
        .select('cloud_phone_number_id, cloud_setup_status')
        .eq('user_id', user.id)
        .maybeSingle();
      const phoneNumberId = String(gate?.cloud_phone_number_id ?? '').trim();
      const setup = String(gate?.cloud_setup_status ?? 'none');
      if (!phoneNumberId || setup !== 'ready') {
        return Response.json({
          ok: false,
          reason: 'cloud_not_ready',
          detail: setup === 'pending' ? 'pending_meta_setup' : 'missing_phone_number_id',
          mode: 'cloud_api',
          sent_to: phone,
          message_ar:
            'واتساب الرسمي غير جاهز بعد. أكمل إعداد Meta مع الدعم ثم أعد المحاولة.',
        }, { status: 409 });
      }
      const sent = await cloudSendText({
        userId: user.id,
        phoneNumberId,
        toE164Digits: phone,
        body: text,
      });
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'send_text',
        source: 'client_notify',
        detail: sent.ok ? 'cloud_ok' : (sent.detail ?? 'cloud_fail'),
        meta: { provider: 'cloud_api', message_id: sent.messageId ?? null },
      });
      await logOutboundText(
        'cloud_api',
        sent.messageId ?? null,
        sent.ok,
        sent.detail,
      );
      if (!sent.ok) {
        return Response.json({
          ok: false,
          reason: 'cloud_send_failed',
          detail: sent.detail ?? 'error',
          mode: 'cloud_api',
          sent_to: phone,
        }, { status: 502 });
      }
      return Response.json({
        ok: true,
        reason: 'ok',
        detail: 'cloud_api',
        mode: 'cloud_api',
        sent_to: phone,
        message_id: sent.messageId ?? null,
      });
    }

    // —— مسار Evolution (QR) إن اختاره المستخدم ——
    if (activeProvider === 'evolution') {
      let live = await Evo.readEvolutionLiveState(instanceName);
      if (!live.ok || !live.mapped.connected) {
        if (!(await readRepairNeeded(supabase, user.id))) {
          const soft = await Evo.softReconnectEvolutionSession(instanceName);
          if (soft.ok) {
            live = await Evo.readEvolutionLiveState(instanceName);
          }
        }
      }
      if (!live.ok || !live.mapped.connected) {
        return Response.json({
          ok: false,
          reason: 'whatsapp_disconnected',
          detail: live.mapped.rawState || 'not_open',
          mode: 'evolution',
          sent_to: phone,
          provider: 'evolution',
          message_ar: 'واتساب غير متصل. امسح QR من إعدادات الربط.',
        }, { status: 409 });
      }
      const sent = await Evo.evolutionSendText({
        instanceName,
        phoneDigits: phone,
        text,
      });
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'send_text',
        source: 'client_notify',
        detail: sent.ok ? 'ok' : (sent.detail ?? 'fail'),
        meta: { provider: 'evolution' },
      });
      return Response.json({
        ok: sent.ok,
        reason: sent.ok ? 'ok' : (sent.reason ?? 'send_failed'),
        detail: sent.detail ?? '',
        mode: 'evolution',
        sent_to: phone,
        provider: 'evolution',
      }, { status: sent.ok ? 200 : 502 });
    }

    let softReconnectMeta: Awaited<
      ReturnType<typeof softReconnectEvolutionSession>
    > | null = null;

    let live = await readEvolutionLiveState(instanceName);
    if (!live.ok || !live.mapped.connected) {
      if (live.notFound) {
        const correlationId = newCorrelationId();
        await writeDiagnostic({
          userId: user.id,
          instanceName,
          eventType: 'send_attempt',
          severity: 'error',
          correlationId,
          recipientPhone: phone,
          connectionState: 'removed',
          outcome: 'error',
          reasonCode: 'instance_removed',
          technicalDetail: 'instance_not_found',
        });
        return Response.json({
          ok: false,
          reason: 'whatsapp_disconnected',
          detail: 'removed',
          mode: 'text',
          sent_to: phone,
          instance_name: instanceName,
          correlation_id: correlationId,
          soft_reconnect: false,
        }, { status: 409 });
      }

      // انقطاع/close: لا soft-reconnect إن لزم إصلاح يدوي.
      if (await readRepairNeeded(supabase, user.id)) {
        const correlationId = newCorrelationId();
        await writeDiagnostic({
          userId: user.id,
          instanceName,
          eventType: 'send_attempt',
          severity: 'error',
          correlationId,
          recipientPhone: phone,
          connectionState: live.mapped.rawState || 'not_open',
          outcome: 'error',
          reasonCode: 'repair_needed',
          technicalDetail: 'repair_needed_skip_soft_reconnect',
        });
        return Response.json({
          ok: false,
          reason: 'whatsapp_disconnected',
          detail: 'repair_needed',
          mode: 'text',
          sent_to: phone,
          instance_name: instanceName,
          correlation_id: correlationId,
          soft_reconnect: false,
          repair_needed: true,
        }, { status: 409 });
      }

      // انقطاع/close: جرّب soft reconnect قبل رفض الإرسال.
      softReconnectMeta = await softReconnectEvolutionSession(instanceName);
      await auditSoftReconnect(supabase, {
        userId: user.id,
        instanceName,
        source: 'send_text',
        soft: softReconnectMeta,
      });
      if (!softReconnectMeta.ok) {
        const correlationId = newCorrelationId();
        await writeDiagnostic({
          userId: user.id,
          instanceName,
          eventType: 'send_attempt',
          severity: 'error',
          correlationId,
          recipientPhone: phone,
          connectionState: softReconnectMeta.finalState || live.mapped.rawState ||
            'not_open',
          outcome: 'error',
          reasonCode: 'whatsapp_disconnected',
          technicalDetail:
            `soft_reconnect_failed:${softReconnectMeta.finalState}`,
          meta: {
            soft_elapsed_ms: softReconnectMeta.elapsedMs,
            restart_ok: softReconnectMeta.restartOk,
          },
        });
        return Response.json({
          ok: false,
          reason: 'whatsapp_disconnected',
          detail: softReconnectMeta.finalState || live.mapped.rawState ||
            'not_open',
          mode: 'text',
          sent_to: phone,
          instance_name: instanceName,
          correlation_id: correlationId,
          soft_reconnect: false,
          soft_reconnect_elapsed_ms: softReconnectMeta.elapsedMs,
        }, { status: 409 });
      }
      live = await readEvolutionLiveState(instanceName);
      if (!live.ok || !live.mapped.connected) {
        const correlationId = newCorrelationId();
        return Response.json({
          ok: false,
          reason: 'whatsapp_disconnected',
          detail: live.mapped.rawState || 'not_open',
          mode: 'text',
          sent_to: phone,
          instance_name: instanceName,
          correlation_id: correlationId,
          soft_reconnect: false,
        }, { status: 409 });
      }
    }

    // connectionState لا يُرجع رقم الجلسة — نجلبه من fetchInstances (ownerJid)
    // وإلا تمرّ رسائل «إرسال للنفس» وتُسجَّل ناجحة بينما واتساب يرفض تسليمها.
    let shopDigits = normalizeIraqWhatsappDigits(live.mapped.phone ?? '');
    if (!shopDigits) {
      shopDigits = await fetchEvolutionOwnerDigits(instanceName);
    }
    if (shopDigits && shopDigits === phone) {
      const correlationId = newCorrelationId();
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'send_text',
        source: 'client_notify',
        detail: 'same_as_shop_phone',
        meta: { sent_to: phone, order_id: body.order_id ?? null },
      });
      await writeDiagnostic({
        userId: user.id,
        instanceName,
        eventType: 'send_attempt',
        severity: 'warn',
        correlationId,
        shopPhone: shopDigits,
        recipientPhone: phone,
        recipientJidType: 'phone',
        outcome: 'same_as_shop_phone',
        reasonCode: 'same_as_shop_phone',
        meta: { order_id: body.order_id ?? null },
      });
      return Response.json({
        ok: false,
        reason: 'same_as_shop_phone',
        detail: 'customer_equals_shop',
        mode: 'text',
        sent_to: phone,
        instance_name: instanceName,
        correlation_id: correlationId,
      }, { status: 400 });
    }

    const correlationId = newCorrelationId();
    let sent = await evolutionSendText({
      instanceName,
      phoneDigits: phone,
      text,
    });

    // فشل بسبب disconnect أثناء الإرسال: soft reconnect ثم إعادة محاولة واحدة.
    if (!sent.ok && sent.reason === 'whatsapp_disconnected') {
      const softRetry = await softReconnectEvolutionSession(instanceName);
      await auditSoftReconnect(supabase, {
        userId: user.id,
        instanceName,
        source: 'send_text_retry',
        soft: softRetry,
      });
      softReconnectMeta = softRetry;
      if (softRetry.ok) {
        sent = await evolutionSendText({
          instanceName,
          phoneDigits: phone,
          text,
        });
      }
    }

    const jidType = jidTypeFromRemote(sent.remoteJid);
    await writeAudit(supabase, {
      userId: user.id,
      instanceName,
      action: 'send_text',
      source: 'client_notify',
      detail: sent.ok ? 'ok' : sent.reason,
      meta: {
        sent_to: sent.sentTo,
        order_id: body.order_id ?? null,
        remote_jid: sent.remoteJid || null,
        shop_digits: shopDigits || null,
        provider_message_id: sent.providerMessageId || null,
        correlation_id: correlationId,
        detail: sent.detail.slice(0, 200),
        soft_reconnect: softReconnectMeta
          ? {
            ok: softReconnectMeta.ok,
            elapsed_ms: softReconnectMeta.elapsedMs,
            final_state: softReconnectMeta.finalState,
            skipped: softReconnectMeta.skipped ?? null,
          }
          : null,
      },
    });

    await writeDiagnostic({
      userId: user.id,
      instanceName,
      eventType: sent.ok ? 'send_accepted' : 'send_attempt',
      severity: sent.ok ? 'info' : 'error',
      providerMessageId: sent.providerMessageId || null,
      correlationId,
      shopPhone: shopDigits || null,
      recipientPhone: sent.sentTo || phone,
      recipientJidType: jidType,
      connectionState: softReconnectMeta?.finalState ?? live.mapped.rawState ??
        null,
      outcome: sent.ok ? 'accepted' : 'error',
      reasonCode: sent.ok ? null : sent.reason,
      technicalDetail: sent.detail,
      meta: {
        order_id: body.order_id ?? null,
        remote_jid: sent.remoteJid || null,
        soft_reconnect_ok: softReconnectMeta?.ok ?? null,
      },
    });

    const errBlob = `${sent.reason ?? ''} ${sent.detail ?? ''}`.toLowerCase();
    const code463 = errBlob.includes('463') || errBlob.includes('timelock');
    await writeOpsFact(supabase, {
      userId: user.id,
      sessionName: instanceName,
      factType: sent.ok ? 'send_accepted' : 'send_error',
      code: sent.ok ? null : code463 ? '463' : (sent.reason ?? 'error'),
      phone: sent.sentTo || phone,
      rawRef: `send:${correlationId}:${sent.ok ? 'ok' : 'err'}`,
      meta: {
        provider_message_id: sent.providerMessageId || null,
        number_lock: code463 || undefined,
      },
    });

    return Response.json({
      ok: sent.ok,
      reason: sent.reason,
      detail: sent.detail,
      mode: 'text',
      sent_to: sent.sentTo,
      instance_name: instanceName,
      order_id: body.order_id ?? null,
      correlation_id: correlationId,
      provider_message_id: sent.providerMessageId || null,
      soft_reconnect: softReconnectMeta?.ok === true,
      soft_reconnect_elapsed_ms: softReconnectMeta?.elapsedMs ?? null,
    }, { status: sent.ok ? 200 : 502 });
  }

  return Response.json({ ok: false, error: 'unknown_action' }, { status: 400 });
  })();

  return withCors(req, res);
});

async function acquireLock(
  supabase: SupabaseClient,
): Promise<{ ok: boolean; error?: string; retryAfterSeconds?: number }> {
  try {
    const { data, error } = await supabase.rpc('acquire_whatsapp_gateway_lock', {
      p_ttl_seconds: LOCK_TTL_SECONDS,
    });
    if (error) {
      console.warn('acquire lock rpc failed, continuing without hard lock', error);
      return { ok: true };
    }
    const row = (data ?? {}) as Record<string, unknown>;
    if (row.ok === true) return { ok: true };
    return {
      ok: false,
      error: 'locked',
      retryAfterSeconds: LOCK_TTL_SECONDS,
    };
  } catch (e) {
    console.warn('acquire lock exception, continuing', e);
    return { ok: true };
  }
}

async function releaseLock(supabase: SupabaseClient): Promise<void> {
  try {
    await supabase.rpc('release_whatsapp_gateway_lock');
  } catch (e) {
    console.warn('release lock failed', e);
  }
}

async function checkHardResetRateLimit(
  supabase: SupabaseClient,
  userId: string,
  cooldownMs: number,
): Promise<{ ok: boolean; retryAfterSeconds?: number }> {
  const { data, error } = await supabase
    .from('tenant_whatsapp_gateways')
    .select('last_hard_reset_at')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) {
    console.warn('rate limit read failed', error);
    return { ok: true };
  }
  const raw = data?.last_hard_reset_at as string | null | undefined;
  if (!raw) return { ok: true };
  const last = Date.parse(raw);
  if (Number.isNaN(last)) return { ok: true };
  const elapsed = Date.now() - last;
  if (elapsed >= cooldownMs) return { ok: true };
  return {
    ok: false,
    retryAfterSeconds: Math.ceil((cooldownMs - elapsed) / 1000),
  };
}

async function markHardReset(
  supabase: SupabaseClient,
  userId: string,
  source: ResetSource,
  _meta: Record<string, unknown>,
): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await supabase
    .from('tenant_whatsapp_gateways')
    .update({
      last_hard_reset_at: now,
      last_reset_reason: source,
      last_reset_source: source,
      updated_at: now,
    })
    .eq('user_id', userId);
  if (error) {
    console.warn('markHardReset failed', error);
  }
}

async function readRepairNeeded(
  supabase: SupabaseClient,
  userId: string,
): Promise<boolean> {
  const { data } = await supabase
    .from('tenant_whatsapp_gateways')
    .select('repair_needed')
    .eq('user_id', userId)
    .maybeSingle();
  return data?.repair_needed === true;
}

async function writeAudit(
  supabase: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    action: string;
    source: string;
    detail?: string;
    meta?: Record<string, unknown>;
  },
): Promise<void> {
  try {
    const { error } = await supabase.from('whatsapp_gateway_audit').insert({
      user_id: args.userId,
      instance_name: args.instanceName,
      action: args.action,
      source: args.source,
      detail: args.detail ?? null,
      meta: args.meta ?? null,
    });
    if (error) console.warn('audit insert failed', error);
  } catch (e) {
    console.warn('audit insert failed', e);
  }
}

async function auditSoftReconnect(
  supabase: SupabaseClient,
  args: {
    userId: string;
    instanceName: string;
    source: string;
    soft: Awaited<ReturnType<typeof softReconnectEvolutionSession>>;
  },
): Promise<void> {
  const detail = args.soft.skipped
    ? `skipped_${args.soft.skipped}`
    : (args.soft.ok ? 'ok' : 'failed');
  await writeAudit(supabase, {
    userId: args.userId,
    instanceName: args.instanceName,
    action: 'soft_reconnect',
    source: args.source,
    detail,
    meta: {
      ok: args.soft.ok,
      restart_ok: args.soft.restartOk,
      connect_called: args.soft.connectCalled,
      final_state: args.soft.finalState,
      elapsed_ms: args.soft.elapsedMs,
      skipped: args.soft.skipped ?? null,
    },
  });
  await writeDiagnostic({
    userId: args.userId,
    instanceName: args.instanceName,
    eventType: 'soft_reconnect',
    severity: args.soft.ok ? 'info' : 'warn',
    connectionState: args.soft.finalState,
    outcome: args.soft.ok ? 'reconnected' : 'failed',
    reasonCode: args.soft.skipped ?? (args.soft.ok ? null : 'soft_reconnect_failed'),
    technicalDetail:
      `restartOk=${args.soft.restartOk};connectCalled=${args.soft.connectCalled};elapsedMs=${args.soft.elapsedMs}`,
    meta: {
      source: args.source,
      skipped: args.soft.skipped ?? null,
    },
  });
}
