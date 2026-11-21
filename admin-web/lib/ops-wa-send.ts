import { normalizePhoneE164 } from "@/lib/ops-phone";

/**
 * إرسال واتساب صادر لـ Ops CRM.
 * الأولوية: NABOO_OPS_WA_SEND_URL ثم Evolution API إن وُجد.
 */
export async function sendOpsWhatsApp(args: {
  toPhone: string;
  text: string;
}): Promise<{ ok: true; via: string } | { ok: false; error: string }> {
  const phone = normalizePhoneE164(args.toPhone);
  if (!phone) return { ok: false, error: "رقم الهاتف غير صالح" };
  const text = args.text.trim();
  if (!text) return { ok: false, error: "نص الرسالة فارغ" };

  const sendUrl = process.env.NABOO_OPS_WA_SEND_URL?.trim();
  const sendToken = process.env.NABOO_OPS_WA_SEND_TOKEN?.trim();
  if (sendUrl) {
    try {
      const res = await fetch(sendUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(sendToken ? { Authorization: `Bearer ${sendToken}` } : {}),
        },
        body: JSON.stringify({ to: phone, text }),
      });
      if (!res.ok) {
        const errText = await res.text();
        return {
          ok: false,
          error: `فشل الإرسال عبر الموصل: ${errText.slice(0, 200)}`,
        };
      }
      return { ok: true, via: "naboo_ops_wa_send_url" };
    } catch (e) {
      return {
        ok: false,
        error: e instanceof Error ? e.message : "خطأ إرسال",
      };
    }
  }

  const evoBase = (process.env.EVOLUTION_BASE_URL ?? "").replace(/\/$/, "");
  const evoKey = process.env.EVOLUTION_API_KEY?.trim() ?? "";
  const evoInstance =
    process.env.NABOO_OPS_EVOLUTION_INSTANCE?.trim() ||
    process.env.EVOLUTION_INSTANCE?.trim() ||
    "naboo";

  if (evoBase && evoKey) {
    const digits = phone.replace(/\D/g, "");
    try {
      const res = await fetch(
        `${evoBase}/message/sendText/${encodeURIComponent(evoInstance)}`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: evoKey,
          },
          body: JSON.stringify({
            number: digits,
            text,
          }),
        },
      );
      if (!res.ok) {
        const errText = await res.text();
        return {
          ok: false,
          error: `فشل Evolution: ${errText.slice(0, 200)}`,
        };
      }
      return { ok: true, via: "evolution" };
    } catch (e) {
      return {
        ok: false,
        error: e instanceof Error ? e.message : "خطأ Evolution",
      };
    }
  }

  return {
    ok: false,
    error:
      "لا موصل إرسال مضبوط (NABOO_OPS_WA_SEND_URL أو EVOLUTION_BASE_URL)",
  };
}
