import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

/** معرفة المساعد (ب4): مكتبة نابو (م1-30)، طلبات الدعم من المساعد (م1-18)،
 *  ومراجعة دليل السيارات (م1-13). الجداول للخادم وحده، فتُقرأ بمفتاح الخدمة هنا. */

const MAX_BODY = 800;

type Body = {
  action?: string;
  id?: number;
  kind?: string;
  title?: string;
  body?: string;
  keywords?: string;
  published?: boolean;
};

export async function GET() {
  try {
    const supabase = getSupabaseAdmin();
    const [articles, support, cars] = await Promise.all([
      supabase
        .from("assistant_knowledge")
        .select("id,kind,title,body,keywords,published,updated_at")
        .order("updated_at", { ascending: false })
        .limit(300),
      supabase
        .from("assistant_support_requests")
        .select("id,tenant_id,role_key,route_id,summary,status,created_at,resolved_at,notified_at")
        .order("created_at", { ascending: false })
        .limit(100),
      supabase
        .from("assistant_car_specs")
        .select(
          "id,make,model,year_from,year_to,engine,fuel,oil_capacity_l,viscosity_primary,oil_spec,sources,confidence,locked,hits,updated_at",
        )
        .order("hits", { ascending: false })
        .limit(300),
    ]);
    const err = articles.error ?? support.error ?? cars.error;
    if (err) throw new Error(err.message);
    return NextResponse.json({ articles: articles.data, support: support.data, cars: cars.data });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "خطأ" }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    const b = (await req.json()) as Body;
    const supabase = getSupabaseAdmin();
    const id = Number(b.id);
    const needId = () => (Number.isInteger(id) && id > 0 ? null : "معرّف غير صالح");

    switch (b.action) {
      case "save_article": {
        const kind = b.kind === "naboo" ? "naboo" : "library";
        const title = (b.title ?? "").trim();
        const body = (b.body ?? "").trim();
        const keywords = (b.keywords ?? "").trim();
        if (!title || title.length > 120) return bad("العنوان مطلوب، 120 حرفاً كحد أقصى");
        if (!body || body.length > MAX_BODY) return bad(`النص مطلوب، ${MAX_BODY} حرف كحد أقصى`);
        if (keywords.length > 400) return bad("كلمات الاستدعاء طويلة");
        const row = { kind, title, body, keywords, published: b.published === true, updated_at: new Date().toISOString() };
        const q = Number.isInteger(id) && id > 0
          ? supabase.from("assistant_knowledge").update(row).eq("id", id)
          : supabase.from("assistant_knowledge").insert(row);
        const { error } = await q;
        if (error) return bad(error.message);
        return NextResponse.json({ ok: true });
      }
      case "delete_article": {
        const e = needId();
        if (e) return bad(e);
        const { error } = await supabase.from("assistant_knowledge").delete().eq("id", id);
        if (error) return bad(error.message);
        return NextResponse.json({ ok: true });
      }
      case "support_done": {
        const e = needId();
        if (e) return bad(e);
        const { error } = await supabase
          .from("assistant_support_requests")
          .update({ status: "done", resolved_at: new Date().toISOString() })
          .eq("id", id);
        if (error) return bad(error.message);
        return NextResponse.json({ ok: true });
      }
      case "car_lock": {
        // «أقفل» = راجعتُه بنفسي: يصبح موثقاً ولا يُعاد البحث عنه.
        const e = needId();
        if (e) return bad(e);
        const { error } = await supabase
          .from("assistant_car_specs")
          .update({ locked: true, confidence: "verified", updated_at: new Date().toISOString() })
          .eq("id", id);
        if (error) return bad(error.message);
        return NextResponse.json({ ok: true });
      }
      case "car_delete": {
        const e = needId();
        if (e) return bad(e);
        const { error } = await supabase.from("assistant_car_specs").delete().eq("id", id);
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
