/**
 * عزل مستأجر الرقم المشترك — موضوع حسّاس أمنياً.
 *
 * قاعدة ذهبية:
 * الرد باسم محل + بياناته فقط إذا وُجدت مراسلة صادرة سابقة
 * من ذلك المحل إلى نفس رقم الزبون (خلال نافذة العلاقة).
 * غير ذلك = تواصل بارد → رد نظام نابو فقط، بلا سياق أي محل.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  cloudMarkReadAndTyping,
  cloudSendText,
  humanTypingDelayMs,
  sleepMs,
} from '../whatsapp-gateway/cloud_api.ts';

/** بعد هذه المدة بلا مراسلة من المحل، لا نربط الزبون بأي مستأجر. */
export const RELATIONSHIP_WINDOW_DAYS = 30;

export type InboundTenantResolution =
  | {
    status: 'bound';
    tenantUserId: string;
    reason: 'last_outbound';
  }
  | {
    status: 'cold';
    reason: 'no_prior_outbound';
  }
  | {
    status: 'unknown';
    reason: 'no_gateway' | 'missing_phone_number_id';
  };

export function phoneVariants(phone: string): string[] {
  const digits = String(phone ?? '').replace(/\D/g, '');
  if (!digits) return [String(phone ?? '')];
  return [digits, `+${digits}`];
}

/**
 * رد نظام نابو — بلا اسم محل وبلا بطاقة وبلا DeepSeek.
 * لا يكشف بيانات أي مستأجر.
 */
export const NABOO_COLD_CONTACT_REPLY =
  'هلا بيك 👋\n' +
  'هذا رقم إشعارات خدمة تلقائية لزبائن المحلات المشتركة بمنصة نابو.\n' +
  'إذا زرتَ محلاً واستلمت منه بطاقة خدمة على واتساب، رد على نفس المحادثة وراح يساعدك استقبال المحل.\n' +
  'إذا ما وصلك شي من المحل، تواصل مباشرة وية المحل اللي تعرفه — ما نكدر ننسب رسالتك لمحل بدون رابط خدمة سابق.';

/**
 * يربط الوارد بمحل فقط عبر آخر إرسال مؤكّد لهذا الرقم.
 * لا تخمين عند وجود عدة بوابات ولا ربط بـ «محل وحيد على الرقم».
 */
export async function resolveTenantForInbound(
  db: SupabaseClient,
  phoneNumberId: string,
  fromPhone: string,
): Promise<InboundTenantResolution> {
  if (!phoneNumberId.trim()) {
    return { status: 'unknown', reason: 'missing_phone_number_id' };
  }

  const { data } = await db
    .from('tenant_whatsapp_gateways')
    .select('user_id')
    .eq('cloud_phone_number_id', phoneNumberId)
    .limit(100);

  const tenantIds = (data ?? [])
    .map((row) => String(row.user_id ?? '').trim())
    .filter((id) => id.length > 0);

  if (tenantIds.length === 0) {
    return { status: 'unknown', reason: 'no_gateway' };
  }

  const since = new Date(
    Date.now() - RELATIONSHIP_WINDOW_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();

  const { data: last } = await db
    .from('whatsapp_message_logs')
    .select('tenant_user_id')
    .in('tenant_user_id', tenantIds)
    .in('to_phone', phoneVariants(fromPhone))
    .in('status', ['sent', 'delivered'])
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (last?.tenant_user_id) {
    return {
      status: 'bound',
      tenantUserId: String(last.tenant_user_id),
      reason: 'last_outbound',
    };
  }

  return { status: 'cold', reason: 'no_prior_outbound' };
}

/** يمنع تكرار رد النظام البارد لنفس wamid. */
export async function claimColdReplySlot(
  db: SupabaseClient,
  providerMessageId: string,
  fromPhone: string,
  phoneNumberId: string,
): Promise<boolean> {
  const wamid = providerMessageId.trim();
  if (!wamid) return false;

  const { error } = await db.from('whatsapp_cold_replies').insert({
    provider_message_id: wamid,
    from_phone: fromPhone,
    phone_number_id: phoneNumberId || null,
    body: NABOO_COLD_CONTACT_REPLY,
  });

  if (!error) return true;
  if (error.code === '23505') return false;
  console.warn('cold reply claim failed', error.message);
  return false;
}

/**
 * يخزّن الوارد البارد بلا tenant (إن سمحت القاعدة) ثم يرد برد النظام فقط.
 */
export async function handleColdOrUnknownInbound(
  db: SupabaseClient,
  args: {
    phoneNumberId: string;
    fromPhone: string;
    messageId: string;
    body: string | null;
    messageType: string;
    resolution: 'cold_unmatched' | 'unknown_number';
  },
): Promise<{ stored: boolean; sent: boolean; detail: string }> {
  try {
    await db.from('whatsapp_inbound_messages').insert({
      tenant_user_id: null,
      provider: 'cloud_api',
      provider_message_id: args.messageId,
      from_phone: args.fromPhone,
      body: args.body,
      message_type: args.messageType,
      context_message_id: null,
      resolution: args.resolution,
      raw: {
        isolation: args.resolution,
        note: 'no_tenant_binding_without_prior_outbound',
      },
    });
  } catch (e) {
    const msg = String(e);
    if (!msg.includes('23505') && !msg.includes('duplicate')) {
      console.warn('cold inbound store failed', msg.slice(0, 160));
    }
  }

  if (!args.messageId || !args.fromPhone || !args.phoneNumberId) {
    return { stored: true, sent: false, detail: 'incomplete' };
  }

  const claimed = await claimColdReplySlot(
    db,
    args.messageId,
    args.fromPhone,
    args.phoneNumberId,
  );
  if (!claimed) {
    return { stored: true, sent: false, detail: 'cold_already_replied' };
  }

  await cloudMarkReadAndTyping({
    userId: 'system',
    phoneNumberId: args.phoneNumberId,
    inboundMessageId: args.messageId,
  });

  await sleepMs(humanTypingDelayMs(NABOO_COLD_CONTACT_REPLY, { fast: true }));

  const sent = await cloudSendText({
    userId: 'system',
    phoneNumberId: args.phoneNumberId,
    toE164Digits: args.fromPhone,
    body: NABOO_COLD_CONTACT_REPLY,
  });

  if (!sent.ok) {
    console.warn('cold system reply failed', sent.detail);
    return { stored: true, sent: false, detail: sent.detail ?? 'send_failed' };
  }

  return { stored: true, sent: true, detail: 'cold_system_reply' };
}
