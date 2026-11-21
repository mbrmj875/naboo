/**
 * تذكير الدين التلقائي (المرحلة 7 — الشريحة 4).
 *
 * التطبيق هو من يقرر أن الدين تأخر (المبلغ والتسديد على جهاز المحل)، ثم
 * يطلب إرسال رسالة واحدة بمفتاح ثابت. هنا: رفع القالب، حالته، والإرسال
 * بعد فحص الإيقاف والقالب والرصيد. المفتاح نفسه لا يُخصم ولا يُرسل مرتين.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { writeClient } from '../admin_client.ts';
import {
  isOfficialTemplateTransport,
  parseTransportId,
} from '../providers/registry.ts';
import { debtReminderTemplate } from './default_template_registry.ts';
import { ensureDefaultTemplatesForTenant } from './template_lifecycle_service.ts';
import { syncTemplateStatusesForTenant } from './template_lifecycle_service.ts';
import { computeReadyState } from './ready_state.ts';
import { checkRecipientConsent } from '../recipient_consent.ts';
import { debitWalletForSend } from '../wallet.ts';
import { dispatchNotification } from '../notifications/notification_dispatcher.ts';
import { TemplateKey } from '../notifications/notification_request.ts';
import { resolveShopNameForCard } from '../notifications/resolve_shop_name.ts';

export type DebtTemplateStatus =
  | 'approved'
  | 'pending'
  | 'rejected'
  | 'none'
  | 'not_official';

export type DebtReminderSendStatus =
  | 'sent'
  | 'already_sent'
  | 'opted_out'
  | 'template_not_approved'
  | 'not_connected'
  | 'insufficient_balance'
  | 'send_blocked'
  | 'invalid'
  | 'failed';

/** المفتاح من التطبيق: «عميل|يوم الاستحقاق». يُقيَّد بالمحل هنا. */
export function debtReminderIdempotencyKey(
  tenantUserId: string,
  reminderKey: string,
): string {
  return `debt_reminder:${tenantUserId}:${reminderKey.trim()}`;
}

/** هل يُعاد المحاولة لاحقاً من التطبيق؟ */
export function debtReminderRetryLater(status: DebtReminderSendStatus): boolean {
  return status === 'template_not_approved' ||
    status === 'not_connected' ||
    status === 'insufficient_balance' ||
    status === 'send_blocked' ||
    status === 'failed';
}

export function normalizeDebtTemplateStatus(raw: unknown): DebtTemplateStatus {
  const s = String(raw ?? '').trim();
  if (s === 'approved' || s === 'pending' || s === 'rejected') return s;
  if (s === 'disabled' || s === 'paused') return 'rejected';
  return 'none';
}

async function readTemplateStatus(
  db: SupabaseClient,
  tenantUserId: string,
  provider: string,
): Promise<DebtTemplateStatus> {
  const { data } = await db
    .from('tenant_whatsapp_templates')
    .select('status')
    .eq('tenant_user_id', tenantUserId)
    .eq('provider', provider)
    .eq('template_name', debtReminderTemplate.name)
    .maybeSingle();
  return normalizeDebtTemplateStatus(data?.status);
}

async function readProviderId(
  db: SupabaseClient,
  tenantUserId: string,
): Promise<string> {
  const { data: gate } = await db
    .from('tenant_whatsapp_gateways')
    .select('whatsapp_provider')
    .eq('user_id', tenantUserId)
    .maybeSingle();
  return parseTransportId(gate?.whatsapp_provider);
}

/** يُرفع القالب عند اختيار «تلقائي». المعتمد أو قيد المراجعة لا يُعاد رفعه. */
export async function submitDebtReminderTemplate(
  supabase: SupabaseClient,
  tenantUserId: string,
): Promise<{ ok: boolean; status: DebtTemplateStatus; detail?: string }> {
  const db = writeClient(supabase);
  const provider = await readProviderId(db, tenantUserId);
  if (!isOfficialTemplateTransport(provider)) {
    return { ok: true, status: 'not_official' };
  }
  const current = await readTemplateStatus(db, tenantUserId, provider);
  if (current === 'approved' || current === 'pending') {
    return { ok: true, status: current };
  }
  const res = await ensureDefaultTemplatesForTenant(supabase, tenantUserId, [
    debtReminderTemplate,
  ]);
  return {
    ok: res.ok,
    status: await readTemplateStatus(db, tenantUserId, provider),
    detail: res.detail,
  };
}

export async function debtReminderTemplateStatus(
  supabase: SupabaseClient,
  tenantUserId: string,
): Promise<DebtTemplateStatus> {
  const db = writeClient(supabase);
  const provider = await readProviderId(db, tenantUserId);
  if (!isOfficialTemplateTransport(provider)) return 'not_official';
  try {
    await syncTemplateStatusesForTenant(supabase, tenantUserId);
  } catch (e) {
    console.warn('debt template sync failed', String(e).slice(0, 120));
  }
  return await readTemplateStatus(db, tenantUserId, provider);
}

export async function sendDebtReminder(
  supabase: SupabaseClient,
  args: {
    tenantUserId: string;
    customerPhone: string;
    reminderKey: string;
    customerName: string;
    amountText: string;
    sinceText: string;
    shopName: string;
  },
): Promise<{ status: DebtReminderSendStatus; detail?: string }> {
  const db = writeClient(supabase);
  const phone = args.customerPhone.trim();
  const key = args.reminderKey.trim();
  if (!phone || !key || !args.amountText.trim()) return { status: 'invalid' };

  const idempotencyKey = debtReminderIdempotencyKey(args.tenantUserId, key);
  const { data: done } = await db
    .from('whatsapp_message_logs')
    .select('status')
    .eq('tenant_user_id', args.tenantUserId)
    .eq('idempotency_key', idempotencyKey)
    .eq('status', 'sent')
    .maybeSingle();
  if (done) return { status: 'already_sent' };

  const consent = await checkRecipientConsent(db, args.tenantUserId, phone);
  if (consent === 'opted_out') return { status: 'opted_out' };
  if (consent === 'unknown') return { status: 'failed', detail: 'consent_unknown' };

  const ready = await computeReadyState(db, args.tenantUserId, [
    TemplateKey.debtReminder,
  ]);
  if (!ready.connected || ready.readyState !== 'ready') {
    return { status: 'not_connected' };
  }
  const provider = await readProviderId(db, args.tenantUserId);
  if (!isOfficialTemplateTransport(provider)) {
    return { status: 'template_not_approved', detail: 'not_official' };
  }
  if (await readTemplateStatus(db, args.tenantUserId, provider) !== 'approved') {
    return { status: 'template_not_approved' };
  }

  const wallet = await debitWalletForSend(db, {
    tenantUserId: args.tenantUserId,
    idempotencyKey,
    provider,
    sendKind: 'debt_reminder',
  });
  if (!wallet.ok) {
    const err = String(wallet.error ?? '');
    return {
      status: err.startsWith('send_blocked') ? 'send_blocked' : 'insufficient_balance',
      detail: err,
    };
  }

  const shop = await resolveShopNameForCard(db, {
    tenantUserId: args.tenantUserId,
    shopName: args.shopName,
  });
  const name = args.customerName.trim();
  const result = await dispatchNotification(db, {
    tenantUserId: args.tenantUserId,
    channel: 'whatsapp',
    templateKey: TemplateKey.debtReminder,
    recipient: { phone },
    variables: {
      customer: name || 'عميلنا الكريم',
      shop,
      amount: args.amountText.trim(),
      since: args.sinceText.trim() || '—',
    },
    idempotencyKey,
  });
  if (result.ok) {
    return { status: result.detail === 'idempotent_hit' ? 'already_sent' : 'sent' };
  }
  return { status: 'failed', detail: result.detail };
}
