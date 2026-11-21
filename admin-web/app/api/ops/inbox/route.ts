import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import {
  ensureOpsContact,
  insertOpsMessage,
  listRecentMessagesForContact,
} from "@/lib/ops-contacts";
import { normalizePhoneE164 } from "@/lib/ops-phone";
import { sendOpsWhatsApp } from "@/lib/ops-wa-send";

/** قائمة محادثات Inbox + خيط لجهة تواصل. */
export async function GET(req: Request) {
  try {
    const url = new URL(req.url);
    const contactId = url.searchParams.get("contact_id")?.trim() ?? "";
    const supabase = getSupabaseAdmin();

    if (contactId) {
      const { data: contact, error } = await supabase
        .from("ops_contacts")
        .select("*")
        .eq("id", contactId)
        .maybeSingle();
      if (error || !contact) {
        return NextResponse.json(
          { error: error?.message ?? "جهة التواصل غير موجودة" },
          { status: 404 },
        );
      }
      const messages = await listRecentMessagesForContact(contactId, 80);
      const { data: suggestions } = await supabase
        .from("ops_ai_suggestions")
        .select("*")
        .eq("contact_id", contactId)
        .eq("status", "pending")
        .order("created_at", { ascending: false })
        .limit(5);
      return NextResponse.json({
        contact,
        messages: messages.slice().reverse(),
        pending_suggestions: suggestions ?? [],
      });
    }

    const { data: contacts, error } = await supabase
      .from("ops_contacts")
      .select("*")
      .order("updated_at", { ascending: false })
      .limit(100);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    const enriched = [];
    for (const c of contacts ?? []) {
      const msgs = await listRecentMessagesForContact(c.id, 1);
      enriched.push({
        ...c,
        last_message: msgs[0] ?? null,
      });
    }

    return NextResponse.json({ conversations: enriched });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}

type SendBody = {
  contact_id?: string;
  phone?: string;
  text: string;
  as_ai?: boolean;
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as SendBody;
    const text = (body.text ?? "").trim();
    if (text.length < 1) {
      return NextResponse.json({ error: "نص الرسالة فارغ" }, { status: 400 });
    }

    let contactId = (body.contact_id ?? "").trim();
    if (!contactId && body.phone) {
      const c = await ensureOpsContact({ phone: body.phone });
      contactId = c?.id ?? "";
    }
    if (!contactId) {
      return NextResponse.json({ error: "جهة التواصل ناقصة" }, { status: 400 });
    }

    const supabase = getSupabaseAdmin();
    const { data: contact } = await supabase
      .from("ops_contacts")
      .select("phone_e164")
      .eq("id", contactId)
      .maybeSingle();

    const phone = normalizePhoneE164(contact?.phone_e164 ?? body.phone ?? "");
    let providerSent = false;
    let sendWarning: string | undefined;
    if (phone) {
      const sent = await sendOpsWhatsApp({ toPhone: phone, text });
      if (sent.ok) providerSent = true;
      else sendWarning = sent.error;
    }

    const msg = await insertOpsMessage({
      contactId,
      channel: "whatsapp",
      direction: "outbound",
      sender: body.as_ai ? "ai" : "human",
      body: text,
    });

    await supabase
      .from("ops_contacts")
      .update({ updated_at: new Date().toISOString() })
      .eq("id", contactId);

    return NextResponse.json({
      ok: true,
      message: msg,
      provider_sent: providerSent,
      send_warning: sendWarning,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
