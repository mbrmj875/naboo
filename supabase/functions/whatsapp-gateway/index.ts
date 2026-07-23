import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  ensureEvolutionInstance,
  ensureEvolutionWebhook,
  evolutionInstanceNameForUser,
  evolutionSendText,
  extractQrPayload,
  fetchEvolutionConnectQr,
  fetchEvolutionOwnerDigits,
  hardResetEvolutionSession,
  normalizeIraqWhatsappDigits,
  readEvolutionLiveState,
} from './evolution.ts';
import {
  jidTypeFromRemote,
  newCorrelationId,
  writeDiagnostic,
} from './diagnostics.ts';

type GatewayAction =
  | 'provision'
  | 'qr'
  | 'status'
  | 'report_disconnected'
  | 'disconnect'
  | 'send_text';

type ResetSource =
  | 'user_disconnect'
  | 'user_force_reset'
  | 'server_qr_fallback';

type RequestBody = {
  action?: GatewayAction;
  /** عند true يصفّر الجلسة قبل جلب QR — يُتجاهل إذا الجلسة open/connecting. */
  force_reset?: boolean;
  /** إرسال نص عبر Evolution — رقم الزبون ونص الرسالة فقط. */
  customer_phone?: string;
  message_text?: string;
  order_id?: number | string | null;
};

const FORCE_RESET_COOLDOWN_MS = 10 * 60 * 1000;
const DISCONNECT_COOLDOWN_MS = 2 * 60 * 1000;
const LOCK_TTL_SECONDS = 45;

Deno.serve(async (req) => {
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

  if (action === 'provision') {
    await ensureEvolutionInstance(instanceName);
    const webhookOk = await ensureEvolutionWebhook(instanceName);
    const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
      {
        user_id: user.id,
        evolution_instance_name: instanceName,
        status: 'connecting',
        updated_at: now,
      },
      { onConflict: 'user_id' },
    );
    if (error) {
      console.error('provision upsert failed', error);
      return Response.json({ ok: false, error: error.message }, { status: 500 });
    }
    await writeDiagnostic({
      userId: user.id,
      instanceName,
      eventType: 'provision',
      severity: 'info',
      connectionState: 'connecting',
      outcome: 'accepted',
      meta: { webhook_ok: webhookOk },
    });
    return Response.json({ ok: true, instance_name: instanceName });
  }

  if (action === 'status') {
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
    if (mapped.connected) patch.last_connected_at = now;
    if (mapped.status === 'disconnected') patch.last_disconnected_at = now;

    const { error } = await supabase.from('tenant_whatsapp_gateways').upsert(
      patch,
      { onConflict: 'user_id' },
    );
    if (error) {
      return Response.json({ ok: false, error: error.message }, { status: 500 });
    }

    return Response.json({
      ok: true,
      status: mapped.status,
      connected: mapped.connected,
      phone: mapped.phone,
      raw_state: mapped.rawState,
      instance_name: instanceName,
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

      // غير open: صدّق الحالة الحية وحدّث السحابة (بانر بعد مزامنة status من الأجهزة).
      const cloudStatus =
        mapped.status === 'unknown' ? 'disconnected' : mapped.status;
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'report_disconnected_confirmed',
        source: 'client_status',
        detail: 'confirmed_not_open_from_live_status',
        meta: {
          raw_state: mapped.rawState,
          status: cloudStatus,
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

      let evolutionError: string | null = null;
      let logoutOk = false;
      let restartOk = false;
      try {
        const reset = await hardResetEvolutionSession(instanceName);
        logoutOk = reset.logoutOk;
        restartOk = reset.restartOk;
        if (!logoutOk && !restartOk) {
          evolutionError = 'evolution_reset_failed';
        }
      } catch (e) {
        evolutionError = e instanceof Error ? e.message : 'evolution_logout_failed';
        console.warn('disconnect reset failed', e);
      }

      await markHardReset(supabase, user.id, 'user_disconnect', {
        logoutOk,
        restartOk,
        evolutionError,
      });
      await writeAudit(supabase, {
        userId: user.id,
        instanceName,
        action: 'hard_reset',
        source: 'user_disconnect',
        detail: evolutionError ?? 'ok',
        meta: { logoutOk, restartOk },
      });
      await writeDiagnostic({
        userId: user.id,
        instanceName,
        eventType: 'hard_reset',
        severity: 'warn',
        connectionState: 'disconnected',
        outcome: 'disconnected',
        reasonCode: evolutionError ?? 'user_disconnect',
        technicalDetail: `logoutOk=${logoutOk};restartOk=${restartOk}`,
        meta: { source: 'user_disconnect' },
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
        ok: true,
        status: 'disconnected',
        evolution_ok: logoutOk || restartOk,
        evolution_logout_ok: logoutOk,
        evolution_restart_ok: restartOk,
        evolution_error: evolutionError,
      });
    } finally {
      await releaseLock(supabase);
    }
  }

  if (action === 'qr') {
    await ensureEvolutionInstance(instanceName);
    await ensureEvolutionWebhook(instanceName);

    const live = await readEvolutionLiveState(instanceName);
    if (!live.ok) {
      return Response.json({
        ok: false,
        error: 'evolution_state_unavailable',
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

    // أثناء connecting: لا hardReset — انتظر اكتمال المسح.
    if (live.mapped.status === 'connecting') {
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
      if (wantsReset) {
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
            message_ar:
              'تمت محاولة تصفير الجلسة مؤخراً. انتظر حتى 10 دقائق أو استخدم إلغاء الربط ثم QR.',
          }, { status: 429 });
        }
        await hardResetEvolutionSession(instanceName);
        await markHardReset(supabase, user.id, 'user_force_reset', {});
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'hard_reset',
          source: 'user_force_reset',
          detail: 'qr_force_reset_while_disconnected',
        });
      }

      let { ok, data } = await fetchEvolutionConnectQr(instanceName);
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

        await hardResetEvolutionSession(instanceName);
        await markHardReset(supabase, user.id, 'server_qr_fallback', {});
        await writeAudit(supabase, {
          userId: user.id,
          instanceName,
          action: 'hard_reset',
          source: 'server_qr_fallback',
          detail: 'no_base64_after_connect',
        });
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

    const live = await readEvolutionLiveState(instanceName);
    if (!live.ok || !live.mapped.connected) {
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
        reasonCode: live.notFound ? 'instance_removed' : 'whatsapp_disconnected',
        technicalDetail: live.mapped.rawState || 'not_open',
      });
      return Response.json({
        ok: false,
        reason: 'whatsapp_disconnected',
        detail: live.mapped.rawState || 'not_open',
        mode: 'text',
        sent_to: phone,
        instance_name: instanceName,
        correlation_id: correlationId,
      }, { status: 409 });
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
    const sent = await evolutionSendText({
      instanceName,
      phoneDigits: phone,
      text,
    });

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
      outcome: sent.ok ? 'accepted' : 'error',
      reasonCode: sent.ok ? null : sent.reason,
      technicalDetail: sent.detail,
      meta: {
        order_id: body.order_id ?? null,
        remote_jid: sent.remoteJid || null,
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
    }, { status: sent.ok ? 200 : 502 });
  }

  return Response.json({ ok: false, error: 'unknown_action' }, { status: 400 });
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
