/**
 * حفظ الردود الواردة وإسناد التقييم للفني الذي نفّذ البطاقة.
 * ربط المستأجر معزول في tenant_isolation.ts — لا تخمين محل للتواصل البارد.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import type { MetaInboundMessage } from './meta_payload.ts';
import { parseRatingReply } from './rating_parse.ts';
import { phoneVariants } from './tenant_isolation.ts';

export {
  resolveTenantForInbound,
  type InboundTenantResolution,
} from './tenant_isolation.ts';

const RECENT_CARD_WINDOW_HOURS = 72;
const UNIQUE_VIOLATION = '23505';
const DELIVERABLE_STATUSES = ['sent', 'delivered'];

export type InboundHandleResult = {
  stored: boolean;
  ratingSaved: boolean;
  detail: string;
  score?: number | null;
  hasNote?: boolean;
  note?: string | null;
  employeeName?: string | null;
  orderRef?: string | null;
  cardPayload?: Record<string, string> | null;
  inboundMessageId?: string | null;
  source?: RatingSource;
};

export type RatingSource = 'reply_context' | 'recent_card';

export async function handleInboundMessage(
  db: SupabaseClient,
  tenantUserId: string,
  msg: MetaInboundMessage,
): Promise<InboundHandleResult> {
  if (!msg.messageId || !msg.fromPhone) {
    return { stored: false, ratingSaved: false, detail: 'incomplete_message' };
  }

  const { data: inserted, error: insertError } = await db
    .from('whatsapp_inbound_messages')
    .insert({
      tenant_user_id: tenantUserId,
      provider: 'cloud_api',
      provider_message_id: msg.messageId,
      from_phone: msg.fromPhone,
      body: msg.body,
      message_type: msg.messageType,
      context_message_id: msg.contextMessageId,
      resolution: 'bound',
      raw: msg as unknown as Record<string, unknown>,
    })
    .select('id')
    .maybeSingle();

  if (insertError) {
    if (insertError.code === UNIQUE_VIOLATION) {
      return await duplicateInboundForReply(db, tenantUserId, msg);
    }
    console.warn('inbound insert failed', insertError.message);
    return { stored: false, ratingSaved: false, detail: 'inbound_insert_failed' };
  }

  const parsed = parseRatingReply(msg.body ?? '');
  if (parsed.score == null && !parsed.note) {
    return { stored: true, ratingSaved: false, detail: 'no_rating_content' };
  }

  const attribution = await findCardAttribution(db, tenantUserId, msg);
  const inboundMessageId = inserted?.id ? String(inserted.id) : null;

  const saved = parsed.score != null &&
    await insertRating(db, {
      tenantUserId,
      orderRef: attribution.orderRef,
      employeeName: attribution.employeeName,
      customerPhone: msg.fromPhone,
      score: parsed.score,
      note: parsed.note,
      source: attribution.source,
      inboundMessageId,
    });

  return {
    stored: true,
    ratingSaved: saved,
    detail: parsed.score == null
      ? 'note_pending_classification'
      : saved
      ? `rating_${attribution.source}`
      : 'rating_not_saved',
    score: parsed.score,
    hasNote: parsed.note != null,
    note: parsed.note,
    employeeName: attribution.employeeName,
    orderRef: attribution.orderRef,
    cardPayload: attribution.cardPayload,
    inboundMessageId,
    source: attribution.source,
  };
}

export async function saveInboundNote(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    orderRef: string | null;
    employeeName: string | null;
    customerPhone: string;
    note: string;
    source: RatingSource;
    inboundMessageId: string | null;
  },
): Promise<boolean> {
  return await insertRating(db, {
    ...args,
    score: null,
    note: args.note,
  });
}

type Attribution = {
  orderRef: string | null;
  employeeName: string | null;
  cardPayload: Record<string, string> | null;
  source: RatingSource;
};

async function findCardAttribution(
  db: SupabaseClient,
  tenantUserId: string,
  msg: MetaInboundMessage,
): Promise<Attribution> {
  if (msg.contextMessageId) {
    const { data } = await db
      .from('whatsapp_message_logs')
      .select('order_ref, employee_name, card_payload')
      .eq('tenant_user_id', tenantUserId)
      .eq('provider_message_id', msg.contextMessageId)
      .maybeSingle();
    if (data) {
      return {
        orderRef: data.order_ref ? String(data.order_ref) : null,
        employeeName: data.employee_name ? String(data.employee_name) : null,
        cardPayload: asCardPayload(data.card_payload),
        source: 'reply_context',
      };
    }
  }

  const since = new Date(
    Date.now() - RECENT_CARD_WINDOW_HOURS * 60 * 60 * 1000,
  ).toISOString();

  const { data: recent } = await db
    .from('whatsapp_message_logs')
    .select('order_ref, employee_name, card_payload, template_key')
    .eq('tenant_user_id', tenantUserId)
    .in('to_phone', phoneVariants(msg.fromPhone))
    .in('status', DELIVERABLE_STATUSES)
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(8);

  const prefer = (recent ?? []).find((row) => {
    const key = String(row.template_key ?? '');
    if (key === 'oil_change_card') return true;
    return asCardPayload(row.card_payload) != null;
  }) ?? null;

  return {
    orderRef: prefer?.order_ref ? String(prefer.order_ref) : null,
    employeeName: prefer?.employee_name ? String(prefer.employee_name) : null,
    cardPayload: asCardPayload(prefer?.card_payload),
    source: 'recent_card',
  };
}

async function duplicateInboundForReply(
  db: SupabaseClient,
  tenantUserId: string,
  msg: MetaInboundMessage,
): Promise<InboundHandleResult> {
  const parsed = parseRatingReply(msg.body ?? '');
  if (parsed.score == null && !parsed.note) {
    return { stored: false, ratingSaved: false, detail: 'duplicate_message' };
  }

  const { data: inbound } = await db
    .from('whatsapp_inbound_messages')
    .select('id, received_at')
    .eq('tenant_user_id', tenantUserId)
    .eq('provider_message_id', msg.messageId)
    .maybeSingle();

  const receivedAtMs = inbound?.received_at
    ? new Date(String(inbound.received_at)).getTime()
    : 0;
  const ageMs = receivedAtMs > 0 ? Date.now() - receivedAtMs : 0;

  if (ageMs > 0 && ageMs < 90_000) {
    return { stored: false, ratingSaved: false, detail: 'duplicate_in_flight' };
  }

  if (inbound?.received_at) {
    const { count } = await db
      .from('whatsapp_message_logs')
      .select('id', { count: 'exact', head: true })
      .eq('tenant_user_id', tenantUserId)
      .eq('template_key', 'rating_auto_reply')
      .in('to_phone', phoneVariants(msg.fromPhone))
      .gte('created_at', String(inbound.received_at));
    if ((count ?? 0) > 0) {
      return { stored: false, ratingSaved: false, detail: 'duplicate_already_replied' };
    }
  }

  if (msg.messageId) {
    const { count: claims } = await db
      .from('whatsapp_message_logs')
      .select('id', { count: 'exact', head: true })
      .eq('tenant_user_id', tenantUserId)
      .eq('idempotency_key', `auto_reply:${msg.messageId}`);
    if ((claims ?? 0) > 0) {
      return { stored: false, ratingSaved: false, detail: 'duplicate_claimed' };
    }
  }

  const attribution = await findCardAttribution(db, tenantUserId, msg);
  return {
    stored: false,
    ratingSaved: false,
    detail: 'duplicate_retry_reply',
    score: parsed.score,
    hasNote: parsed.note != null,
    note: parsed.note,
    employeeName: attribution.employeeName,
    orderRef: attribution.orderRef,
    cardPayload: attribution.cardPayload,
    inboundMessageId: inbound?.id ? String(inbound.id) : null,
    source: attribution.source,
  };
}

function asCardPayload(raw: unknown): Record<string, string> | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    const text = String(value ?? '').trim();
    if (text) out[key] = text;
  }
  return Object.keys(out).length > 0 ? out : null;
}

async function insertRating(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    orderRef: string | null;
    employeeName: string | null;
    customerPhone: string;
    score: number | null;
    note: string | null;
    source: 'reply_context' | 'recent_card';
    inboundMessageId: string | null;
  },
): Promise<boolean> {
  const row = {
    tenant_user_id: args.tenantUserId,
    order_ref: args.orderRef,
    employee_name: args.employeeName,
    customer_phone: args.customerPhone,
    score: args.score,
    note: args.note,
    source: args.source,
    inbound_message_id: args.inboundMessageId,
  };

  const { error } = await db.from('oil_change_service_ratings').insert(row);
  if (!error) return true;

  console.warn('rating insert failed', error.message);
  return false;
}
