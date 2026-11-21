import { getSupabaseAdmin } from "./supabase-admin";
import { normalizePhoneE164 } from "./ops-phone";
import type { OpsChannel } from "./ops-channels";

export type OpsContactRow = {
  id: string;
  phone_e164: string;
  display_name: string | null;
  auth_user_id: string | null;
  lifecycle: string;
  whatsapp_id: string | null;
  facebook_psid: string | null;
  instagram_id: string | null;
  telegram_id: string | null;
  tiktok_id: string | null;
  email: string | null;
  created_at: string;
  updated_at: string;
};

export type OpsMessageRow = {
  id: string;
  contact_id: string;
  channel: string;
  direction: string;
  sender: string;
  body: string;
  external_id: string | null;
  created_at: string;
};

/** Strip auth secrets before persisting webhook payloads. */
export function redactOpsMessageRaw(raw: unknown): unknown {
  if (raw == null) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) return raw;
  const copy = { ...(raw as Record<string, unknown>) };
  delete copy.secret;
  delete copy.authorization;
  delete copy.Authorization;
  return copy;
}

/** إيجاد أو إنشاء جهة اتصال بالهاتف. */
export async function ensureOpsContact(args: {
  phone: string;
  displayName?: string | null;
  authUserId?: string | null;
  channelIds?: Partial<
    Pick<
      OpsContactRow,
      | "whatsapp_id"
      | "facebook_psid"
      | "instagram_id"
      | "telegram_id"
      | "tiktok_id"
      | "email"
    >
  >;
}): Promise<OpsContactRow | null> {
  const phone = normalizePhoneE164(args.phone);
  if (!phone) return null;

  const supabase = getSupabaseAdmin();
  const { data: existing } = await supabase
    .from("ops_contacts")
    .select("*")
    .eq("phone_e164", phone)
    .maybeSingle();

  if (existing) {
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (args.displayName && !existing.display_name) {
      patch.display_name = args.displayName;
    }
    if (args.authUserId && !existing.auth_user_id) {
      patch.auth_user_id = args.authUserId;
    }
    if (args.channelIds) {
      for (const [k, v] of Object.entries(args.channelIds)) {
        if (v && !(existing as Record<string, unknown>)[k]) patch[k] = v;
      }
    }
    if (Object.keys(patch).length > 1) {
      const { data: updated } = await supabase
        .from("ops_contacts")
        .update(patch)
        .eq("id", existing.id)
        .select("*")
        .single();
      return (updated as OpsContactRow) ?? (existing as OpsContactRow);
    }
    return existing as OpsContactRow;
  }

  const insert = {
    phone_e164: phone,
    display_name: args.displayName ?? null,
    auth_user_id: args.authUserId ?? null,
    lifecycle: "lead",
    whatsapp_id: args.channelIds?.whatsapp_id ?? null,
    facebook_psid: args.channelIds?.facebook_psid ?? null,
    instagram_id: args.channelIds?.instagram_id ?? null,
    telegram_id: args.channelIds?.telegram_id ?? null,
    tiktok_id: args.channelIds?.tiktok_id ?? null,
    email: args.channelIds?.email ?? null,
  };

  const { data: created, error } = await supabase
    .from("ops_contacts")
    .insert(insert)
    .select("*")
    .single();
  if (error) throw new Error(error.message);
  return created as OpsContactRow;
}

export async function linkContactToAuthUser(
  contactId: string,
  authUserId: string,
): Promise<void> {
  const supabase = getSupabaseAdmin();
  await supabase
    .from("ops_contacts")
    .update({
      auth_user_id: authUserId,
      updated_at: new Date().toISOString(),
    })
    .eq("id", contactId);
}

export async function findContactByAuthUserId(
  authUserId: string,
): Promise<OpsContactRow | null> {
  const supabase = getSupabaseAdmin();
  const { data } = await supabase
    .from("ops_contacts")
    .select("*")
    .eq("auth_user_id", authUserId)
    .maybeSingle();
  return (data as OpsContactRow) ?? null;
}

export async function findContactByPhone(
  phone: string,
): Promise<OpsContactRow | null> {
  const e164 = normalizePhoneE164(phone);
  if (!e164) return null;
  const supabase = getSupabaseAdmin();
  const { data } = await supabase
    .from("ops_contacts")
    .select("*")
    .eq("phone_e164", e164)
    .maybeSingle();
  return (data as OpsContactRow) ?? null;
}

export async function insertOpsMessage(args: {
  contactId: string;
  channel: OpsChannel;
  direction: "inbound" | "outbound";
  sender: "customer" | "human" | "ai" | "system";
  body: string;
  externalId?: string | null;
  raw?: unknown;
}): Promise<OpsMessageRow | null> {
  const supabase = getSupabaseAdmin();
  const row = {
    contact_id: args.contactId,
    channel: args.channel,
    direction: args.direction,
    sender: args.sender,
    body: args.body.slice(0, 8000),
    external_id: args.externalId ?? null,
    raw: redactOpsMessageRaw(args.raw),
  };
  const { data, error } = await supabase
    .from("ops_messages")
    .insert(row)
    .select("*")
    .single();
  if (error) {
    // تجاهل تكرار external_id
    if (error.code === "23505") return null;
    throw new Error(error.message);
  }
  return data as OpsMessageRow;
}

export async function listRecentMessagesForContact(
  contactId: string,
  limit = 40,
): Promise<OpsMessageRow[]> {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from("ops_messages")
    .select(
      "id,contact_id,channel,direction,sender,body,external_id,created_at",
    )
    .eq("contact_id", contactId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw new Error(error.message);
  return (data as OpsMessageRow[]) ?? [];
}

/** ملخص محادثات للمنصة يُحقن في مساعد التطبيق. */
export async function buildOpsConversationSummaryForUser(
  authUserId: string,
  phone?: string | null,
): Promise<string | null> {
  let contact = await findContactByAuthUserId(authUserId);
  if (!contact && phone) {
    contact = await findContactByPhone(phone);
    if (contact && !contact.auth_user_id) {
      await linkContactToAuthUser(contact.id, authUserId);
    }
  }
  if (!contact) return null;

  const messages = await listRecentMessagesForContact(contact.id, 12);
  if (messages.length === 0) {
    return `جهة تواصل منصة نابو معروفة (هاتف ${contact.phone_e164}) بدون رسائل بعد.`;
  }

  const lines = messages
    .slice()
    .reverse()
    .map((m) => {
      const who =
        m.sender === "customer"
          ? "العميل"
          : m.sender === "ai"
            ? "AI"
            : m.sender === "human"
              ? "الفريق"
              : "النظام";
      return `- [${m.channel}] ${who}: ${m.body.slice(0, 180)}`;
    });

  return [
    `سجل تواصل منصة نابو (آخر ${messages.length} رسائل):`,
    ...lines,
  ].join("\n");
}
