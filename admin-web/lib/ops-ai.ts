import {
  accountStatusLabelAr,
  formatSubscriptionColumn,
  getAccountStatus,
  pickLicenseForUser,
} from "@/lib/account-status";
import type { LicenseRow, UserRow } from "@/lib/dashboard-data";
import {
  listRecentMessagesForContact,
  type OpsContactRow,
} from "@/lib/ops-contacts";

const ENDPOINT = "https://api.deepseek.com/chat/completions";
const MODEL = "deepseek-chat";

const PRODUCT_BRAIN_AR = `
أنت مساعد منصة نابو (NABOO) — تتكلم كمن بنى التطبيق ويهتم بالتاجر.
نابو: نظام إدارة محلات (مخزون، فواتير، غيار زيت، غسيل، مطعم حسب التخصص) مع اشتراك سحابي وترخيص أجهزة.
عند السؤال عن الاشتراك: اشرح التجربة، التجديد، عدد الأجهزة، ولا تخترع أسعاراً غير مذكورة.
وجّه المستخدم بخطوات عربية واضحة وقصيرة. إن لم تعرف قل ذلك واقترح تواصل فريق نابو.
`.trim();

export function buildMerchantContextBlock(args: {
  contact: OpsContactRow;
  user?: UserRow | null;
  licenses?: LicenseRow[];
}): string {
  const { contact, user, licenses = [] } = args;
  const lines: string[] = [
    `هاتف: ${contact.phone_e164}`,
    `اسم العرض: ${contact.display_name ?? "—"}`,
    `دورة الحياة (CRM): ${contact.lifecycle}`,
  ];
  if (user) {
    const license = pickLicenseForUser(user.id, licenses);
    const status = getAccountStatus(user, license);
    lines.push(`بريد: ${user.email ?? "—"}`);
    lines.push(`حالة الحساب: ${accountStatusLabelAr(status)}`);
    lines.push(`الاشتراك: ${formatSubscriptionColumn(user, license)}`);
    lines.push(`أجهزة مسجّلة: ${user.linked_devices_count}`);
    lines.push(`آخر دخول: ${user.last_sign_in_at ?? "—"}`);
    if (license?.business_name) lines.push(`اسم المحل: ${license.business_name}`);
    if (license?.expires_at) lines.push(`انتهاء الترخيص: ${license.expires_at}`);
  } else {
    lines.push("لا يوجد حساب Auth مربوط بعد (مهتم / قبل التسجيل).");
  }
  return lines.join("\n");
}

async function suggestViaEdgeFunction(args: {
  context: string;
  historyText: string;
  latest: string;
}): Promise<{ text: string; confidence: number } | null> {
  const base = (
    process.env.NEXT_PUBLIC_SUPABASE_URL ??
    process.env.SUPABASE_URL ??
    ""
  ).replace(/\/$/, "");
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim() ?? "";
  if (!base || !serviceKey) return null;

  try {
    const res = await fetch(`${base}/functions/v1/ops-crm-ai`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${serviceKey}`,
        apikey: serviceKey,
        "Content-Type": "application/json",
        ...(process.env.NABOO_OPS_CONTEXT_SECRET?.trim()
          ? {
              "x-ops-context-secret":
                process.env.NABOO_OPS_CONTEXT_SECRET.trim(),
            }
          : {}),
      },
      body: JSON.stringify({
        context: args.context,
        history_text: args.historyText,
        latest_message: args.latest,
      }),
    });
    if (!res.ok) return null;
    const json = (await res.json()) as {
      text?: string;
      confidence?: number;
    };
    const text = (json.text ?? "").trim();
    if (!text) return null;
    return {
      text: text.slice(0, 2000),
      confidence:
        typeof json.confidence === "number" ? json.confidence : 0.65,
    };
  } catch {
    return null;
  }
}

async function suggestViaLocalDeepseek(args: {
  context: string;
  historyText: string;
  latest: string;
}): Promise<{ text: string; confidence: number } | null> {
  const apiKey = process.env.DEEPSEEK_API_KEY?.trim();
  if (!apiKey) return null;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      signal: controller.signal,
      body: JSON.stringify({
        model: MODEL,
        temperature: 0.4,
        max_tokens: 500,
        messages: [
          { role: "system", content: PRODUCT_BRAIN_AR },
          {
            role: "user",
            content: [
              "سياق التاجر/المهتم:",
              args.context,
              "",
              "سجل المحادثة الأخير:",
              args.historyText || "(فارغ)",
              "",
              "آخر رسالة من العميل:",
              args.latest,
              "",
              "اكتب ردّاً عربياً واحداً جاهزاً للإرسال (بدون عناوين داخلية).",
            ].join("\n"),
          },
        ],
      }),
    });
    if (!res.ok) return null;
    const json = (await res.json()) as {
      choices?: { message?: { content?: string } }[];
    };
    const text = (json.choices?.[0]?.message?.content ?? "").trim();
    if (!text) return null;
    return { text: text.slice(0, 2000), confidence: 0.7 };
  } finally {
    clearTimeout(timer);
  }
}

export async function suggestOpsAiReply(args: {
  contact: OpsContactRow;
  user?: UserRow | null;
  licenses?: LicenseRow[];
  latestCustomerMessage: string;
}): Promise<{ text: string; confidence: number }> {
  const history = await listRecentMessagesForContact(args.contact.id, 10);
  const historyText = history
    .slice()
    .reverse()
    .map((m) => `${m.sender}: ${m.body}`)
    .join("\n");

  const context = buildMerchantContextBlock({
    contact: args.contact,
    user: args.user,
    licenses: args.licenses,
  });

  const latest = args.latestCustomerMessage;

  // 1) Edge Function على Supabase (DEEPSEEK_API_KEY موجود هناك أصلاً)
  const viaEdge = await suggestViaEdgeFunction({
    context,
    historyText,
    latest,
  });
  if (viaEdge) return viaEdge;

  // 2) مفتاح محلي اختياري في admin-web
  const viaLocal = await suggestViaLocalDeepseek({
    context,
    historyText,
    latest,
  });
  if (viaLocal) return viaLocal;

  return {
    text: "مرحباً، فريق نابو هنا. أخبرنا بمشكلتك أو طلب الاشتراك وسنساعدك مباشرة.",
    confidence: 0.2,
  };
}
