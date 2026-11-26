import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

/** إشعارات نابو (خطة الإشعارات، المرحلة 3 والبند 5ج): عدّاد الجاهزية،
 *  معاينة عدد المستلمين، الإرسال أو الجدولة، والسجل. كل الدوال للخادم وحده. */

type Filter = {
  user_id?: string;
  email?: string;
  vertical?: string;
  subscription?: string;
  version_below?: string;
};

type Body = {
  action?: "preview" | "send";
  filter?: Filter;
  key?: string;
  category?: string;
  type?: string;
  title?: string;
  body?: string;
  route?: string;
  deliver_after?: string | null;
  also_announcement?: boolean;
};

const SUBSCRIPTIONS = new Set(["", "active_paid", "lifetime", "monthly", "expiring_7d", "no_license"]);
const ROUTES = new Set(["", "subscription", "notifications"]);

function cleanFilter(f: Filter | undefined): Record<string, string> {
  const s = (v: unknown) => (v == null ? "" : String(v).trim().slice(0, 120));
  const out: Record<string, string> = {};
  const userId = s(f?.user_id);
  if (/^[0-9a-f-]{36}$/i.test(userId)) out.user_id = userId;
  const email = s(f?.email);
  if (email) out.email = email;
  const vertical = s(f?.vertical);
  if (/^[a-z_]{1,40}$/.test(vertical)) out.vertical = vertical;
  const sub = s(f?.subscription);
  if (SUBSCRIPTIONS.has(sub) && sub) out.subscription = sub;
  const ver = s(f?.version_below);
  if (/^\d+(\.\d+){0,3}$/.test(ver)) out.version_below = ver;
  return out;
}

export async function GET() {
  try {
    const supabase = getSupabaseAdmin();
    const [readiness, history, config] = await Promise.all([
      supabase.rpc("admin_notification_readiness"),
      supabase
        .from("notification_broadcasts")
        .select("id,broadcast_key,category,type,title_ar,body_ar,route,filter,recipients,deliver_after,created_by,created_at")
        .order("id", { ascending: false })
        .limit(50),
      supabase.from("app_remote_config").select("config").eq("id", 1).maybeSingle(),
    ]);
    if (readiness.error) {
      return NextResponse.json(
        { error: `لم تُطبَّق ترحيلة الإشعارات على الخادم بعد: ${readiness.error.message}` },
        { status: 400 },
      );
    }
    const cfg = (config.data?.config ?? {}) as Record<string, unknown>;
    return NextResponse.json({
      readiness: readiness.data,
      history: history.data ?? [],
      latestVersion: String(cfg.latest_version ?? ""),
      forceUpdate: cfg.force_update === true,
      updateMessage: String(cfg.update_message_ar ?? ""),
    });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "خطأ" }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    const b = (await req.json()) as Body;
    const supabase = getSupabaseAdmin();
    const filter = cleanFilter(b.filter);

    if (b.action === "preview") {
      const { data, error } = await supabase.rpc("admin_broadcast_preview", { p_filter: filter });
      if (error) return NextResponse.json({ error: error.message }, { status: 400 });
      return NextResponse.json({ preview: data });
    }

    if (b.action === "send") {
      const key = String(b.key ?? "").trim();
      const category = b.category === "naboo_account" ? "naboo_account" : "naboo_ads";
      const type = String(b.type ?? "").trim() || (category === "naboo_account" ? "naboo_notice" : "naboo_offer");
      const title = String(b.title ?? "").trim();
      const body = String(b.body ?? "").trim();
      const route = String(b.route ?? "").trim();
      if (!/^[0-9a-f-]{36}$/i.test(key)) {
        return NextResponse.json({ error: "مفتاح الإرسال غير صالح. أعد تحميل الصفحة." }, { status: 400 });
      }
      if (!title || title.length > 80) {
        return NextResponse.json({ error: "العنوان مطلوب، وحتى 80 حرفا." }, { status: 400 });
      }
      if (body.length > 300) {
        return NextResponse.json({ error: "النص حتى 300 حرف." }, { status: 400 });
      }
      if (!ROUTES.has(route) || !/^[a-z_]{1,40}$/.test(type)) {
        return NextResponse.json({ error: "وجهة أو نوع غير معروف." }, { status: 400 });
      }
      let deliverAfter: string | null = null;
      if (b.deliver_after) {
        const d = new Date(b.deliver_after);
        if (Number.isNaN(d.getTime())) {
          return NextResponse.json({ error: "وقت الجدولة غير صالح." }, { status: 400 });
        }
        deliverAfter = d.toISOString();
      }
      const { data, error } = await supabase.rpc("admin_broadcast_send", {
        p_broadcast_key: key,
        p_category: category,
        p_type: type,
        p_title: title,
        p_body: body,
        p_route: route || null,
        p_filter: filter,
        p_deliver_after: deliverAfter,
        p_created_by: "admin-web",
      });
      if (error) return NextResponse.json({ error: error.message }, { status: 400 });

      // اختياري: يظهر أيضا كإعلان داخل التطبيق (لمن لا يستلم الإشعارات).
      if (b.also_announcement) {
        const { data: existing } = await supabase
          .from("app_remote_config")
          .select("config")
          .eq("id", 1)
          .maybeSingle();
        const config = {
          ...((existing?.config ?? {}) as Record<string, unknown>),
          announcement_title_ar: title,
          announcement_body_ar: body,
        };
        const { error: cfgErr } = await supabase
          .from("app_remote_config")
          .upsert({ id: 1, config, updated_at: new Date().toISOString() });
        if (cfgErr) {
          return NextResponse.json(
            { error: `أُرسل الإشعار، لكن تعذر حفظ الإعلان: ${cfgErr.message}`, recipients: data },
            { status: 400 },
          );
        }
      }
      return NextResponse.json({ recipients: data });
    }

    return NextResponse.json({ error: "إجراء غير معروف" }, { status: 400 });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "خطأ" }, { status: 500 });
  }
}
