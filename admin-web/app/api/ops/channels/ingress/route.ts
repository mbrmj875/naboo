import { NextResponse } from "next/server";
import {
  ensureOpsContact,
  insertOpsMessage,
} from "@/lib/ops-contacts";
import { normalizePhoneE164 } from "@/lib/ops-phone";
import { isOpsChannelEnabled, type OpsChannel } from "@/lib/ops-channels";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { secretsMatch } from "@/lib/secrets-match";

/**
 * مدخل موحّد لقنوات المرحلة F (فيسبوك/إنستغرام/تيليجرام/إيميل/تيك توك).
 * حالياً يستقبل ويسجّل فقط للقنوات المفعّلة في ops-channels؛
 * غير المفعّلة تُرفض برسالة واضحة حتى تُوصَل الموصلات.
 */
export async function POST(req: Request) {
  try {
    const expected = process.env.NABOO_OPS_WEBHOOK_SECRET?.trim() ?? "";
    const body = (await req.json()) as Record<string, unknown>;
    const secret = String(
      body.secret ?? req.headers.get("x-ops-webhook-secret") ?? "",
    );
    if (!secretsMatch(secret, expected)) {
      return NextResponse.json({ error: "غير مصرّح" }, { status: 401 });
    }

    const channel = String(body.channel ?? "").toLowerCase() as OpsChannel;
    const allowed: OpsChannel[] = [
      "facebook",
      "instagram",
      "telegram",
      "email",
      "tiktok",
      "whatsapp",
    ];
    if (!allowed.includes(channel)) {
      return NextResponse.json({ error: "قناة غير معروفة" }, { status: 400 });
    }

    if (!isOpsChannelEnabled(channel)) {
      return NextResponse.json(
        {
          ok: false,
          deferred: true,
          message: `القناة ${channel} جاهزة في النموذج لكنها غير موصولة بعد. فعّلها في ops-channels بعد ربط المزوّد.`,
          channel,
        },
        { status: 202 },
      );
    }

    const phone = normalizePhoneE164(String(body.from_phone ?? body.email ?? ""));
    const text = String(body.text ?? "").trim();
    if (!text) {
      return NextResponse.json({ error: "text مطلوب" }, { status: 400 });
    }

    // للإيميل قد لا يوجد هاتف — نخزّن مفتاحاً اصطناعياً من البريد
    const identityPhone =
      phone ??
      (channel === "email" && body.email
        ? `+000${String(body.email).replace(/[^a-zA-Z0-9]/g, "").slice(0, 12)}`
        : null);
    if (!identityPhone) {
      return NextResponse.json(
        { error: "from_phone أو email مطلوب لربط الهوية" },
        { status: 400 },
      );
    }

    const contact = await ensureOpsContact({
      phone: identityPhone.startsWith("+000") ? identityPhone : identityPhone,
      displayName: body.display_name ? String(body.display_name) : null,
      channelIds: {
        facebook_psid: body.facebook_psid ? String(body.facebook_psid) : null,
        instagram_id: body.instagram_id ? String(body.instagram_id) : null,
        telegram_id: body.telegram_id ? String(body.telegram_id) : null,
        tiktok_id: body.tiktok_id ? String(body.tiktok_id) : null,
        email: body.email ? String(body.email) : null,
        whatsapp_id: body.whatsapp_id ? String(body.whatsapp_id) : null,
      },
    });
    if (!contact) {
      return NextResponse.json({ error: "تعذر إنشاء الهوية" }, { status: 400 });
    }

    // تصحيح: ensureOpsContact يرفض +000 — للإيميل نحدّث البريد مباشرة إن فشل الهاتف
    const msg = await insertOpsMessage({
      contactId: contact.id,
      channel,
      direction: "inbound",
      sender: "customer",
      body: text,
      externalId: body.external_id ? String(body.external_id) : null,
      raw: body,
    });

    await getSupabaseAdmin()
      .from("ops_contacts")
      .update({ updated_at: new Date().toISOString() })
      .eq("id", contact.id);

    return NextResponse.json({
      ok: true,
      contact_id: contact.id,
      message_id: msg?.id ?? null,
      channel,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}

export async function GET() {
  return NextResponse.json({
    ok: true,
    service: "naboo-ops-channel-ingress",
    note: "قنوات غير واتساب تُرفض بـ 202 حتى تُفعَّل في ops-channels",
  });
}
