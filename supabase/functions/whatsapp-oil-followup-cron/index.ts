/**
 * cron: إرسال تذكيرات غيار الزيت المستحقة.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { debitWalletForSend } from '../whatsapp-gateway/wallet.ts';
import {
  classifyFailure,
  nextRetryDelayMs,
} from '../whatsapp-gateway/failure_policy.ts';
import { notifyOilChangeFollowup } from '../whatsapp-gateway/notifications/notifiers/oil_change_followup_notifier.ts';
import {
  getWhatsAppProvider,
  isOfficialTemplateTransport,
  parseTransportId,
} from '../whatsapp-gateway/providers/registry.ts';
import { computeReadyState } from '../whatsapp-gateway/lifecycle/ready_state.ts';
import { checkRecipientConsent } from '../whatsapp-gateway/recipient_consent.ts';
import { FOLLOWUP_TEMPLATE_KEY } from '../whatsapp-gateway/lifecycle/followup_template.ts';

type JobRow = {
  id: string;
  tenant_user_id: string;
  order_ref: string;
  customer_phone: string;
  due_at: string;
  status: string;
  payload: Record<string, unknown> | null;
  idempotency_key: string;
  attempts?: number | null;
};

function cronAuthorized(req: Request): boolean {
  const secret = Deno.env.get('CRON_SECRET')?.trim() ||
    Deno.env.get('WHATSAPP_OPS_ANALYST_SECRET')?.trim() ||
    '';
  if (!secret) return false;
  const auth = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '') ??
    req.headers.get('x-cron-secret') ??
    '';
  return auth === secret;
}

function renderBody(
  template: string,
  payload: Record<string, unknown>,
): string {
  const p = payload;
  return template
    .replaceAll('{الاسم}', String(p.customer_name ?? 'عميلنا الكريم'))
    .replaceAll('{المحل}', String(p.shop ?? 'المحل'))
    .replaceAll('{السيارة}', String(p.car ?? 'سيارتكم'))
    .replaceAll('{آخر_قراءة}', String(p.odometer_current ?? '—'))
    .replaceAll('{القراءة_اللاحقة}', String(p.odometer_next ?? '—'))
    .replaceAll('{تاريخ_الغيار}', String(p.visit_date ?? '—'));
}

function baghdadHour(at = new Date()): number {
  const hour = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Baghdad',
    hour: 'numeric',
    hourCycle: 'h23',
  }).format(at);
  const n = Number(hour);
  return Number.isFinite(n) ? n : 12;
}

function inQuietHours(at = new Date()): boolean {
  const hour = baghdadHour(at);
  return hour >= 22 || hour < 8;
}

function variablesFromPayload(
  payload: Record<string, unknown>,
): Record<string, string> {
  return {
    customer: String(payload.customer_name ?? 'عميلنا الكريم'),
    shop: String(payload.shop ?? 'المحل'),
    car: String(payload.car ?? 'سيارتكم'),
    odo_current: String(payload.odometer_current ?? '—'),
    odo_next: String(payload.odometer_next ?? '—'),
    visit_date: String(payload.visit_date ?? '—'),
  };
}

const STALE_SENDING_MS = 15 * 60_000;
const BLOCKED_RECHECK_MS = 30 * 60_000;
/** انقطاع الربط أو نفاد الرصيد يؤخر التذكير ولا يسقطه، حتى يتجاوز التأخير المهلة. */
const HOLD_RECHECK_MS = 60 * 60_000;
const CONSENT_RECHECK_MS = 5 * 60_000;

Deno.serve(async (req) => {
  if (req.method !== 'POST' && req.method !== 'GET') {
    return new Response('method not allowed', { status: 405 });
  }
  if (!cronAuthorized(req)) {
    return Response.json({ ok: false, error: 'unauthorized' }, { status: 401 });
  }

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !key) {
    return Response.json({ ok: false, error: 'missing_env' }, { status: 500 });
  }

  const db = createClient(url, key, { auth: { persistSession: false } });
  const now = new Date().toISOString();
  const staleDays = 7;

  // ما علق على sending بعد انقطاع يعود للطابور. مفتاح الخصم ثابت فلا يتكرر الخصم.
  const staleBefore = new Date(Date.now() - STALE_SENDING_MS).toISOString();
  await db.from('wa_oil_followup_jobs').update({
    status: 'queued',
    updated_at: now,
  }).eq('status', 'sending').lt('updated_at', staleBefore);

  const { data: jobs, error } = await db
    .from('wa_oil_followup_jobs')
    .select('*')
    .eq('status', 'queued')
    .lte('due_at', now)
    .or(`next_attempt_at.is.null,next_attempt_at.lte.${now}`)
    .order('due_at', { ascending: true })
    .limit(40);

  if (error) {
    console.error('followup cron list failed', error);
    return Response.json({ ok: false, error: error.message }, { status: 500 });
  }

  let sent = 0;
  let skipped = 0;

  for (const raw of jobs ?? []) {
    const job = raw as JobRow;
    const tenant = job.tenant_user_id;
    const payload = (job.payload ?? {}) as Record<string, unknown>;

    const { data: quietRule } = await db
      .from('wa_oil_followup_rules')
      .select('quiet_hours')
      .eq('tenant_user_id', tenant)
      .maybeSingle();
    if (quietRule?.quiet_hours !== false && inQuietHours()) {
      // لا يبقى في أول الدفعة فيؤخر تذكيرات متجر آخر بلا ساعات هدوء.
      await db.from('wa_oil_followup_jobs').update({
        next_attempt_at: new Date(Date.now() + BLOCKED_RECHECK_MS).toISOString(),
      }).eq('id', job.id).eq('status', 'queued');
      skipped++;
      continue;
    }

    const consent = await checkRecipientConsent(db, tenant, job.customer_phone);
    if (consent === 'opted_out') {
      await db.from('wa_oil_followup_jobs').update({
        status: 'cancelled',
        last_error: 'opted_out',
        updated_at: now,
      }).eq('id', job.id).eq('status', 'queued');
      skipped++;
      continue;
    }
    if (consent === 'unknown') {
      await db.from('wa_oil_followup_jobs').update({
        next_attempt_at: new Date(Date.now() + CONSENT_RECHECK_MS).toISOString(),
        updated_at: now,
      }).eq('id', job.id).eq('status', 'queued');
      skipped++;
      continue;
    }

    const isLate = Date.now() - new Date(job.due_at).getTime() >
      staleDays * 86400000;

    const { data: locked } = await db
      .from('wa_oil_followup_jobs')
      .update({ status: 'sending', updated_at: now })
      .eq('id', job.id)
      .eq('status', 'queued')
      .select('id')
      .maybeSingle();
    if (!locked) continue;

    const ready = await computeReadyState(db, tenant);
    if (ready.readyState !== 'ready' || !ready.connected) {
      await db.from('wa_oil_followup_jobs').update({
        status: isLate ? 'failed' : 'queued',
        last_error: 'gateway_disconnected',
        next_attempt_at: isLate
          ? null
          : new Date(Date.now() + HOLD_RECHECK_MS).toISOString(),
        updated_at: now,
      }).eq('id', job.id);
      skipped++;
      continue;
    }

    const { data: gate } = await db
      .from('tenant_whatsapp_gateways')
      .select('whatsapp_provider, whatsapp_phone, ycloud_from_phone, cloud_phone_number_id')
      .eq('user_id', tenant)
      .maybeSingle();

    const providerId = parseTransportId(gate?.whatsapp_provider);
    const official = isOfficialTemplateTransport(providerId);

    if (official) {
      const { data: tpl } = await db
        .from('tenant_whatsapp_templates')
        .select('status')
        .eq('tenant_user_id', tenant)
        .eq('template_key', FOLLOWUP_TEMPLATE_KEY)
        .eq('provider', providerId)
        .maybeSingle();

      const st = String(tpl?.status ?? '');
      if (st !== 'approved') {
        const due = new Date(job.due_at).getTime();
        const late = Date.now() - due > staleDays * 86400000;
        await db.from('wa_oil_followup_jobs').update({
          status: late ? 'skipped_no_template' : 'queued',
          last_error: 'template_not_approved',
          next_attempt_at: late
            ? null
            : new Date(Date.now() + BLOCKED_RECHECK_MS).toISOString(),
          updated_at: now,
        }).eq('id', job.id);
        skipped++;
        continue;
      }
    }

    const wallet = await debitWalletForSend(db, {
      tenantUserId: tenant,
      idempotencyKey: job.idempotency_key,
      provider: providerId,
      sendKind: 'oil_change_followup',
    });

    if (!wallet.ok && String(wallet.error ?? '').startsWith('send_blocked:')) {
      // الطابور موقوف بخطأ حساب: تبقى الوظيفة بلا خصم وتُفحص لاحقًا.
      await db.from('wa_oil_followup_jobs').update({
        status: 'queued',
        last_error_code: String(wallet.error).slice('send_blocked:'.length),
        next_attempt_at: new Date(Date.now() + BLOCKED_RECHECK_MS).toISOString(),
        updated_at: now,
      }).eq('id', job.id);
      skipped++;
      continue;
    }

    if (!wallet.ok) {
      await db.from('wa_oil_followup_jobs').update({
        status: isLate ? 'skipped_no_wallet' : 'queued',
        last_error: wallet.error ?? 'insufficient_balance',
        next_attempt_at: isLate
          ? null
          : new Date(Date.now() + HOLD_RECHECK_MS).toISOString(),
        updated_at: now,
      }).eq('id', job.id);
      skipped++;
      continue;
    }

    let dispatchOk = false;
    let detail = '';
    let errorCode: number | undefined;
    let httpStatus: number | undefined;

    if (official) {
      const result = await notifyOilChangeFollowup(db, {
        tenantUserId: tenant,
        customerPhone: job.customer_phone,
        variables: variablesFromPayload(payload),
        orderRef: job.order_ref,
        idempotencyKey: job.idempotency_key,
      });
      dispatchOk = result.ok;
      detail = result.detail ?? '';
      errorCode = result.errorCode;
      httpStatus = result.httpStatus;
    } else {
      const { data: rule } = await db
        .from('wa_oil_followup_rules')
        .select('body_template')
        .eq('tenant_user_id', tenant)
        .maybeSingle();
      const bodyTemplate = String(rule?.body_template ?? '').trim();
      const text = bodyTemplate
        ? renderBody(bodyTemplate, payload)
        : renderBody(
          'مرحباً {الاسم}، تذكير من {المحل} بخصوص {السيارة}.',
          payload,
        );

      const provider = getWhatsAppProvider(providerId);
      const to = job.customer_phone.trim();
      const from = String(
        gate?.ycloud_from_phone ?? gate?.whatsapp_phone ?? '',
      ).trim();
      if (provider?.sendText) {
        const sentText = await provider.sendText({
          tenantUserId: tenant,
          fromPhoneE164: from,
          toPhoneE164: to,
          body: text,
        });
        dispatchOk = sentText.ok;
        detail = sentText.detail ?? '';
        errorCode = sentText.errorCode;
        httpStatus = sentText.httpStatus;
      } else {
        dispatchOk = false;
        detail = 'qr_text_unsupported';
      }
    }

    if (dispatchOk) {
      await db.from('wa_oil_followup_jobs').update({
        status: 'sent',
        last_error: null,
        updated_at: now,
      }).eq('id', job.id);
      sent++;
    } else {
      const decision = classifyFailure({
        errorCode,
        detail,
        httpStatus,
        isSharedSender: providerId === 'dualhook',
      });
      const attempts = Number(job.attempts ?? 0);
      // خلل مؤقت أو إيقاف على الحساب أو القالب يؤخر التذكير ولا يسقطه قبل المهلة.
      const delay = decision.autoRetry ? nextRetryDelayMs(attempts) : null;
      const canWait = !isLate && (decision.autoRetry || decision.block !== 'none');
      const retryIn = delay ?? (canWait ? HOLD_RECHECK_MS : null);
      await db.from('wa_oil_followup_jobs').update({
        status: retryIn === null ? 'failed' : 'queued',
        attempts: attempts + 1,
        next_attempt_at: retryIn === null
          ? null
          : new Date(Date.now() + retryIn).toISOString(),
        last_error: detail || 'send_failed',
        last_error_code: decision.reasonCode,
        updated_at: now,
      }).eq('id', job.id);
      skipped++;
    }
  }

  return Response.json({
    ok: true,
    processed: (jobs ?? []).length,
    sent,
    skipped,
  });
});
