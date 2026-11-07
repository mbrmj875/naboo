/**
 * سياق محادثة الزبون: ما أرسله وما رددنا به، مرتباً زمنياً.
 * بدونه يعيد الرد التلقائي نفس الشكر على كل رسالة.
 * العزل دائماً: tenant_user_id + رقم الزبون فقط.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import type { ConversationTurn } from './ai_reply.ts';

const HISTORY_TURNS = 16;
const HISTORY_FETCH_CAP = 40;
const HISTORY_WINDOW_DAYS = 7;
/** سقف يومي لكل زبون — كان 15 فيُصمت الرد فجأة بعد محادثة قصيرة. */
const MAX_AUTO_REPLIES_PER_DAY = 80;
const AUTO_REPLY_TEMPLATE_KEY = 'rating_auto_reply';

export type ConversationBundle = {
  history: ConversationTurn[];
  /** ملخص سطرين للمحادثة الأقدم خارج نافذة التاريخ. */
  memorySummary: string | null;
};

export function phoneVariants(phone: string): string[] {
  const digits = String(phone ?? '').replace(/\D/g, '');
  if (!digits) return [String(phone ?? '')];
  return [digits, `+${digits}`];
}

/** أسئلة الزبون ليست رأياً بالخدمة — تُميَّز حين يتعذّر سؤال النموذج. */
export function looksLikeFeedback(text: string): boolean {
  const s = String(text ?? '').trim();
  if (!s) return false;
  if (s.includes('؟') || s.includes('?')) return false;
  // أسئلة شائعة (حتى بلا علامة استفهام) ليست رأياً بالخدمة.
  if (/ضمان|مكفول|مكفولة|كفالة|warranty/i.test(s)) return false;
  if (
    /(من\s*هو|منو|مين|ماهو|ما\s*هو|شنو|شني|شكد|شگد).{0,20}(فني|موظف|سعر|حساب|مبلغ|اجمالي|إجمالي)/i
      .test(s)
  ) {
    return false;
  }
  if (
    /(سعر|الحساب|الإجمالي|الاجمالي|المبلغ).{0,12}(صار|شكد|شگد|كم)/i.test(s) ||
    /(شكد|شگد|كم)\s*صار\s*(سعر|الحساب|المبلغ)?/i.test(s)
  ) {
    return false;
  }

  const asking =
    /(^|\s)(شنو|شني|شلون|شگد|شكد|وين|منو|مين|من\s*هو|ماهو|ما\s*هو|ليش|متى|هل|كم|اكو|اريد اعرف|أريد أعرف|ممكن تعرفوني)(\s|$)/;
  return !asking.test(s);
}

/** ملخص خفيف بلا استدعاء نموذج — مواضيع ظاهرة في الرسائل القديمة. */
export function summarizeOlderTurns(turns: ConversationTurn[]): string | null {
  if (turns.length === 0) return null;
  const topics: string[] = [];
  const blob = turns.map((t) => t.text).join(' ');
  if (/ضمان|كفالة|مكفول/i.test(blob)) topics.push('سأل عن الضمان سابقاً');
  if (/رقم|هاتف|تواصل|عنوان|موقع|لوكيشن/i.test(blob)) {
    topics.push('سأل عن التواصل أو العنوان سابقاً');
  }
  if (/شكر|تسلم|مشكور/i.test(blob)) topics.push('تم شكره سابقاً');
  if (/\b([1-9]|10)\b|تقييم|نجوم/i.test(blob)) {
    topics.push('أرسل تقييماً سابقاً');
  }
  if (topics.length === 0) {
    const snippet = turns
      .slice(-2)
      .map((t) => `${t.role === 'customer' ? 'زبون' : 'محل'}: ${t.text.slice(0, 60)}`)
      .join(' | ');
    return snippet || null;
  }
  return topics.slice(0, 3).join('؛ ');
}

export async function loadConversationBundle(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    customerPhone: string;
    excludeInboundMessageId?: string | null;
  },
): Promise<ConversationBundle> {
  const since = new Date(
    Date.now() - HISTORY_WINDOW_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();
  const phones = phoneVariants(args.customerPhone);

  const [inbound, outbound] = await Promise.all([
    db
      .from('whatsapp_inbound_messages')
      .select('body, received_at, provider_message_id')
      .eq('tenant_user_id', args.tenantUserId)
      .in('from_phone', phones)
      .gte('received_at', since)
      .order('received_at', { ascending: false })
      .limit(HISTORY_FETCH_CAP),
    db
      .from('whatsapp_message_logs')
      .select('body, created_at')
      .eq('tenant_user_id', args.tenantUserId)
      .in('to_phone', phones)
      .eq('status', 'sent')
      .not('body', 'is', null)
      .gte('created_at', since)
      .order('created_at', { ascending: false })
      .limit(HISTORY_FETCH_CAP),
  ]);

  type Row = { role: 'customer' | 'shop'; text: string; at: string };
  const rows: Row[] = [];

  for (const r of inbound.data ?? []) {
    if (
      args.excludeInboundMessageId &&
      String(r.provider_message_id ?? '') === args.excludeInboundMessageId
    ) {
      continue;
    }
    const text = String(r.body ?? '').trim();
    if (text) rows.push({ role: 'customer', text, at: String(r.received_at) });
  }

  for (const r of outbound.data ?? []) {
    const text = String(r.body ?? '').trim();
    if (text) rows.push({ role: 'shop', text, at: String(r.created_at) });
  }

  rows.sort((a, b) => a.at.localeCompare(b.at));

  const mapped = rows.map((r) => ({
    role: r.role,
    text: r.text.slice(0, 300),
  }));

  if (mapped.length <= HISTORY_TURNS) {
    return { history: mapped, memorySummary: null };
  }

  const older = mapped.slice(0, mapped.length - HISTORY_TURNS);
  const history = mapped.slice(-HISTORY_TURNS);
  return {
    history,
    memorySummary: summarizeOlderTurns(older),
  };
}

/** توافق خلفي: آخر N رسائل فقط. */
export async function loadConversation(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    customerPhone: string;
    excludeInboundMessageId?: string | null;
  },
): Promise<ConversationTurn[]> {
  const bundle = await loadConversationBundle(db, args);
  return bundle.history;
}

/** سقف يومي يمنع محادثة لا تنتهي أو استنزاف رصيد النموذج. */
export async function autoReplyQuotaLeft(
  db: SupabaseClient,
  tenantUserId: string,
  customerPhone: string,
): Promise<boolean> {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count } = await db
    .from('whatsapp_message_logs')
    .select('id', { count: 'exact', head: true })
    .eq('tenant_user_id', tenantUserId)
    .eq('template_key', AUTO_REPLY_TEMPLATE_KEY)
    .eq('status', 'sent')
    .in('to_phone', phoneVariants(customerPhone))
    .gte('created_at', since);
  return (count ?? 0) < MAX_AUTO_REPLIES_PER_DAY;
}

export async function logAutoReply(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    customerPhone: string;
    body: string;
    providerMessageId: string | null;
    employeeName: string | null;
    orderRef: string | null;
    /** مفتاح منع التكرار لنفس رسالة الزبون الواردة. */
    idempotencyKey?: string | null;
  },
): Promise<void> {
  try {
    const key = (args.idempotencyKey ?? '').trim();
    if (key) {
      const { data: updated, error: updErr } = await db
        .from('whatsapp_message_logs')
        .update({
          status: 'sent',
          provider_message_id: args.providerMessageId,
          body: args.body,
          employee_name: args.employeeName,
          order_ref: args.orderRef,
        })
        .eq('tenant_user_id', args.tenantUserId)
        .eq('idempotency_key', key)
        .select('id')
        .maybeSingle();
      if (!updErr && updated?.id) return;
    }

    await db.from('whatsapp_message_logs').insert({
      tenant_user_id: args.tenantUserId,
      channel: 'whatsapp',
      provider: 'cloud_api',
      template_key: AUTO_REPLY_TEMPLATE_KEY,
      to_phone: args.customerPhone,
      status: 'sent',
      provider_message_id: args.providerMessageId,
      body: args.body,
      employee_name: args.employeeName,
      order_ref: args.orderRef,
      idempotency_key: key || null,
    });
  } catch (e) {
    console.warn('auto reply log failed', e);
  }
}

/**
 * يحجز رداً واحداً لكل wamid وارد — يمنع الرسالة المزدوجة عند تكرار webhook.
 * يرجع false إذا الحجز لطلب آخر سبق.
 */
export async function claimAutoReplySlot(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    customerPhone: string;
    inboundWamid: string | null | undefined;
  },
): Promise<boolean> {
  const wamid = String(args.inboundWamid ?? '').trim();
  if (!wamid) return true;
  const key = `auto_reply:${wamid}`;
  const { error } = await db.from('whatsapp_message_logs').insert({
    tenant_user_id: args.tenantUserId,
    channel: 'whatsapp',
    provider: 'cloud_api',
    template_key: AUTO_REPLY_TEMPLATE_KEY,
    to_phone: args.customerPhone,
    status: 'queued',
    body: null,
    idempotency_key: key,
  });
  if (!error) return true;
  if (error.code === '23505') return false;
  console.warn('auto reply claim failed', error.message);
  // إن فشل الحجز لسبب آخر نكمل بحذر بدل صمت كامل.
  return true;
}

export function autoReplyIdempotencyKey(
  inboundWamid: string | null | undefined,
): string | null {
  const wamid = String(inboundWamid ?? '').trim();
  return wamid ? `auto_reply:${wamid}` : null;
}
