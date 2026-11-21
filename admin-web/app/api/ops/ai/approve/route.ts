import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { insertOpsMessage } from "@/lib/ops-contacts";
import { sendOpsWhatsApp } from "@/lib/ops-wa-send";

type Body = {
  suggestion_id: string;
  action: "approve" | "reject" | "edit_send";
  manual_edit?: string;
  send_channel?: "whatsapp" | "none";
};

/**
 * موافقة بشرية على اقتراح AI.
 * الإرسال عبر NABOO_OPS_WA_SEND_URL أو Evolution إن وُجد.
 */
export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const id = (body.suggestion_id ?? "").trim();
    if (!id) {
      return NextResponse.json({ error: "معرّف الاقتراح ناقص" }, { status: 400 });
    }

    const supabase = getSupabaseAdmin();
    const { data: suggestion, error: fetchErr } = await supabase
      .from("ops_ai_suggestions")
      .select("*")
      .eq("id", id)
      .maybeSingle();

    if (fetchErr || !suggestion) {
      return NextResponse.json(
        { error: fetchErr?.message ?? "الاقتراح غير موجود" },
        { status: 404 },
      );
    }

    if (body.action === "reject") {
      const { error } = await supabase
        .from("ops_ai_suggestions")
        .update({
          status: "rejected",
          decided_at: new Date().toISOString(),
        })
        .eq("id", id)
        .eq("status", "pending");
      if (error) {
        return NextResponse.json({ error: error.message }, { status: 400 });
      }
      return NextResponse.json({ ok: true, status: "rejected" });
    }

    if (suggestion.status !== "pending") {
      return NextResponse.json(
        { error: "لا يمكن إرسال اقتراح غير معلّق" },
        { status: 409 },
      );
    }

    const text =
      body.action === "edit_send" && body.manual_edit?.trim()
        ? body.manual_edit.trim()
        : String(suggestion.response_text ?? "");

    if (text.length < 1) {
      return NextResponse.json({ error: "نص الرد فارغ" }, { status: 400 });
    }

    let outboundId: string | null = null;
    let providerSent = false;
    let sendWarning: string | undefined;
    const channel = body.send_channel ?? "whatsapp";
    if (channel === "whatsapp") {
      const { data: contact } = await supabase
        .from("ops_contacts")
        .select("phone_e164,whatsapp_id")
        .eq("id", suggestion.contact_id)
        .maybeSingle();

      if (contact?.phone_e164) {
        const sent = await sendOpsWhatsApp({
          toPhone: contact.phone_e164,
          text,
        });
        if (sent.ok) providerSent = true;
        else sendWarning = sent.error;
      }

      const msg = await insertOpsMessage({
        contactId: suggestion.contact_id,
        channel: "whatsapp",
        direction: "outbound",
        sender: body.action === "edit_send" ? "human" : "ai",
        body: text,
      });
      outboundId = msg?.id ?? null;
    }

    const { data: updated, error: updErr } = await supabase
      .from("ops_ai_suggestions")
      .update({
        status: body.action === "edit_send" ? "edited" : "sent",
        manual_edit: body.action === "edit_send" ? text : null,
        decided_at: new Date().toISOString(),
        message_id: outboundId,
      })
      .eq("id", id)
      .eq("status", "pending")
      .select("id")
      .maybeSingle();

    if (updErr) {
      return NextResponse.json({ error: updErr.message }, { status: 400 });
    }
    if (!updated) {
      return NextResponse.json(
        { error: "لا يمكن إرسال اقتراح غير معلّق" },
        { status: 409 },
      );
    }

    return NextResponse.json({
      ok: true,
      status: body.action === "edit_send" ? "edited" : "sent",
      text,
      outbound_message_id: outboundId,
      sent_via_provider: providerSent,
      send_warning: sendWarning,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
