import { NextResponse } from "next/server";
import {
  ensureOpsContact,
  insertOpsMessage,
  listRecentMessagesForContact,
} from "@/lib/ops-contacts";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { normalizePhoneE164 } from "@/lib/ops-phone";
import { suggestOpsAiReply } from "@/lib/ops-ai";
import { isOpsChannelEnabled } from "@/lib/ops-channels";
import { secretsMatch } from "@/lib/secrets-match";

/**
 * Webhook وارد لمنصة نابو (واتساب أولاً).
 * يُستثنى من جلسة الأدمن ويُحمى بـ NABOO_OPS_WEBHOOK_SECRET.
 *
 * جسم متوقع (مبسّط):
 * { secret, channel, from_phone, text, external_id?, display_name? }
 */
export async function POST(req: Request) {
  try {
    const expected = process.env.NABOO_OPS_WEBHOOK_SECRET?.trim() ?? "";
    const body = (await req.json()) as Record<string, unknown>;
    const secret = String(body.secret ?? req.headers.get("x-ops-webhook-secret") ?? "");
    if (!secretsMatch(secret, expected)) {
      return NextResponse.json({ error: "غير مصرّح" }, { status: 401 });
    }

    const channel = String(body.channel ?? "whatsapp").toLowerCase();
    if (!isOpsChannelEnabled(channel) && channel !== "whatsapp") {
      return NextResponse.json(
        {
          error: `القناة ${channel} غير مفعّلة بعد — واتساب فقط في هذه المرحلة`,
          channel,
        },
        { status: 400 },
      );
    }

    const fromPhone = normalizePhoneE164(String(body.from_phone ?? ""));
    const text = String(body.text ?? "").trim();
    if (!fromPhone || !text) {
      return NextResponse.json(
        { error: "from_phone و text مطلوبان" },
        { status: 400 },
      );
    }

    const contact = await ensureOpsContact({
      phone: fromPhone,
      displayName: body.display_name ? String(body.display_name) : null,
      channelIds:
        channel === "whatsapp"
          ? { whatsapp_id: String(body.whatsapp_id ?? fromPhone) }
          : undefined,
    });
    if (!contact) {
      return NextResponse.json({ error: "تعذر إنشاء جهة التواصل" }, { status: 400 });
    }

    const msg = await insertOpsMessage({
      contactId: contact.id,
      channel: channel === "whatsapp" ? "whatsapp" : "whatsapp",
      direction: "inbound",
      sender: "customer",
      body: text,
      externalId: body.external_id ? String(body.external_id) : null,
      raw: body,
    });

    // اقتراح AI تلقائي (لا يُرسل إلا بعد موافقة من Inbox)
    let suggestionId: string | null = null;
    try {
      const suggestion = await suggestOpsAiReply({
        contact,
        latestCustomerMessage: text,
      });
      const supabase = getSupabaseAdmin();
      const { data: sug } = await supabase
        .from("ops_ai_suggestions")
        .insert({
          contact_id: contact.id,
          message_id: msg?.id ?? null,
          response_text: suggestion.text,
          confidence: suggestion.confidence,
          status: "pending",
          created_by: "webhook",
        })
        .select("id")
        .single();
      suggestionId = sug?.id ?? null;
    } catch {
      /* AI اختياري */
    }

    const recent = await listRecentMessagesForContact(contact.id, 5);

    return NextResponse.json({
      ok: true,
      contact_id: contact.id,
      message_id: msg?.id ?? null,
      suggestion_id: suggestionId,
      recent_count: recent.length,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}

export async function GET() {
  return NextResponse.json({
    ok: true,
    service: "naboo-ops-whatsapp-webhook",
    channels_enabled: ["whatsapp"],
  });
}
