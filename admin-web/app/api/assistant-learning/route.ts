import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

/** تعلّم المساعد (ب6، م5-8): الدروس وحالاتها، تشغيلات اختبار الأمان، أكثر
 *  المواضيع فشلاً بحكم الحَكَم، وبريد تنبيه الدعم. الجداول للخادم وحده. */

const SUPPORT_EMAIL_KEY = "assistant_support_email";

type Body = { action?: string; id?: number; email?: string };

type Judged = {
  j_topic: string | null;
  j_answered: boolean | null;
  j_grounded: boolean | null;
  j_perm_ok: boolean | null;
  j_no_invention: boolean | null;
};

export async function GET(req: Request) {
  try {
    // مرشّح القناة (م6-15): المساعد داخل التطبيق ومجيب واتساب يُعرضان منفصلين.
    const channel = new URL(req.url).searchParams.get("channel") === "whatsapp" ? "whatsapp" : "app";
    const supabase = getSupabaseAdmin();
    const runsQuery = supabase
      .from("assistant_eval_runs")
      .select("id,target,lesson_id,model,passed,total,note,created_at")
      .order("id", { ascending: false })
      .limit(30);
    const since = new Date(Date.now() - 14 * 86_400_000).toISOString();
    const [lessons, runs, usage, judged, email] = await Promise.all([
      supabase
        .from("assistant_lessons")
        .select(
          "id,audience,tenant_id,kind,topic,trigger_text,body,status,version,eval_before,eval_after,origin,created_at,activated_at,retired_at,retired_reason,merged_from,eval_requested_at",
        )
        .eq("audience", channel)
        .order("created_at", { ascending: false })
        .limit(300),
      channel === "whatsapp"
        ? runsQuery.eq("target", "whatsapp-responder")
        : runsQuery.neq("target", "whatsapp-responder"),
      supabase.rpc("assistant_lesson_usage", { p_days: 30 }),
      supabase
        .from("assistant_turns")
        .select("j_topic,j_answered,j_grounded,j_perm_ok,j_no_invention")
        .eq("channel", channel)
        .not("judged_at", "is", null)
        .gte("created_at", since)
        .limit(5000),
      supabase.from("ops_edge_cron_config").select("value").eq("key", SUPPORT_EMAIL_KEY).maybeSingle(),
    ]);
    const err = lessons.error ?? runs.error ?? usage.error ?? judged.error ?? email.error;
    if (err) throw new Error(err.message);

    // أكثر المواضيع فشلاً: الإخفاق = أي حكم سلبي من الأربعة.
    const byTopic = new Map<string, { total: number; fails: number }>();
    for (const t of (judged.data ?? []) as Judged[]) {
      const k = t.j_topic ?? "other";
      const failed = t.j_answered === false || t.j_grounded === false || t.j_perm_ok === false ||
        t.j_no_invention === false;
      const v = byTopic.get(k) ?? { total: 0, fails: 0 };
      v.total++;
      if (failed) v.fails++;
      byTopic.set(k, v);
    }
    const topics = [...byTopic.entries()]
      .map(([topic, v]) => ({ topic, ...v }))
      .sort((a, b) => b.fails - a.fails || b.total - a.total)
      .slice(0, 15);

    return NextResponse.json({
      lessons: lessons.data,
      runs: runs.data,
      usage: usage.data,
      topics,
      judgedTotal: judged.data?.length ?? 0,
      supportEmail: email.data?.value ?? "",
    });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "خطأ" }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    const b = (await req.json()) as Body;
    const supabase = getSupabaseAdmin();
    const id = Number(b.id);
    const validId = Number.isInteger(id) && id > 0;

    switch (b.action) {
      case "rollback": {
        // تراجع يدوي: الدرس يخرج من المساعد خلال 10 دقائق (ذاكرة الدالة).
        if (!validId) return bad("معرّف غير صالح");
        const { error } = await supabase
          .from("assistant_lessons")
          .update({ status: "retired", retired_at: new Date().toISOString(), retired_reason: "تراجع يدوي" })
          .eq("id", id)
          .eq("status", "active");
        if (error) return bad(error.message);
        return NextResponse.json({ ok: true });
      }
      case "request_eval": {
        // «اختبره»: مهمة التقييم الدورية تلتقطه خلال 10 دقائق.
        if (!validId) return bad("معرّف غير صالح");
        const { error } = await supabase
          .from("assistant_lessons")
          .update({ eval_requested_at: new Date().toISOString() })
          .eq("id", id)
          .eq("status", "candidate");
        if (error) return bad(error.message);
        return NextResponse.json({ ok: true });
      }
      case "reject": {
        if (!validId) return bad("معرّف غير صالح");
        const { error } = await supabase
          .from("assistant_lessons")
          .update({ status: "rejected", retired_at: new Date().toISOString(), retired_reason: "رفض يدوي" })
          .eq("id", id)
          .eq("status", "candidate");
        if (error) return bad(error.message);
        return NextResponse.json({ ok: true });
      }
      case "support_email": {
        const email = (b.email ?? "").trim();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 200) return bad("بريد غير صالح");
        const { error } = await supabase
          .from("ops_edge_cron_config")
          .upsert({ key: SUPPORT_EMAIL_KEY, value: email, updated_at: new Date().toISOString() }, { onConflict: "key" });
        if (error) return bad(error.message);
        return NextResponse.json({ ok: true });
      }
    }
    return bad("إجراء غير معروف");
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "خطأ" }, { status: 500 });
  }
}

function bad(error: string) {
  return NextResponse.json({ error }, { status: 400 });
}
