/**
 * cron: إرسال تذكيرات غيار الزيت المستحقة.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { debitWalletForSend } from '../whatsapp-gateway/wallet.ts';
import { notifyOilChangeFollowup } from '../whatsapp-gateway/notifications/notifiers/oil_change_followup_notifier.ts';
import {
  getWhatsAppProvider,
  isOfficialTemplateTransport,
  parseTransportId,
} from '../whatsapp-gateway/providers/registry.ts';
import { computeReadyState } from '../whatsapp-gateway/lifecycle/ready_state.ts';
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

  const { data: jobs, error } = await db
    .from('wa_oil_followup_jobs')
    .select('*')
    .eq('status', 'queued')
    .lte('due_at', now)
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
      skipped++;
      continue;
    }

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
        status: 'failed',
        last_error: 'gateway_disconnected',
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
          last_error: late ? 'template_not_approved' : null,
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

    if (!wallet.ok) {
      await db.from('wa_oil_followup_jobs').update({
        status: 'skipped_no_wallet',
        last_error: wallet.error ?? 'insufficient_balance',
        updated_at: now,
      }).eq('id', job.id);
      skipped++;
      continue;
    }

    let dispatchOk = false;
    let detail = '';

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
      await db.from('wa_oil_followup_jobs').update({
        status: 'failed',
        last_error: detail || 'send_failed',
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
