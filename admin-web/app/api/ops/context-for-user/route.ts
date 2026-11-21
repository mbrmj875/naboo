import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { buildOpsConversationSummaryForUser } from "@/lib/ops-contacts";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { cookieName, verifySessionToken } from "@/lib/session";
import { secretsMatch } from "@/lib/secrets-match";

/**
 * ملخص سياق المنصة لمساعد التطبيق (يُستدعى من Edge Function بسر مشترك
 * أو من الأدمن للمعاينة بجلسة). يتطلب جلسة أدمن صالحة أو NABOO_OPS_CONTEXT_SECRET.
 */
export async function POST(req: Request) {
  try {
    const body = (await req.json()) as {
      auth_user_id?: string;
      phone?: string;
      secret?: string;
    };

    const serviceSecret = process.env.NABOO_OPS_CONTEXT_SECRET?.trim() ?? "";
    const provided = (
      body.secret ??
      req.headers.get("x-ops-context-secret") ??
      ""
    ).trim();
    const jar = await cookies();
    const adminOk = await verifySessionToken(jar.get(cookieName())?.value);
    const secretOk = secretsMatch(provided, serviceSecret);
    if (!adminOk && !secretOk) {
      return NextResponse.json({ error: "غير مصرّح" }, { status: 401 });
    }

    const authUserId = (body.auth_user_id ?? "").trim();
    if (!authUserId) {
      return NextResponse.json({ error: "auth_user_id ناقص" }, { status: 400 });
    }

    let phone = body.phone ?? null;
    if (!phone) {
      const supabase = getSupabaseAdmin();
      const { data } = await supabase.auth.admin.getUserById(authUserId);
      phone = data.user?.phone ?? null;
    }

    const summary = await buildOpsConversationSummaryForUser(authUserId, phone);
    return NextResponse.json({
      ok: true,
      summary,
      has_history: Boolean(summary && summary.includes("رسائل")),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
