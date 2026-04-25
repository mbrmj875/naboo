import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

/**
 * يحذف لقطة المزامنة وأجزاءها من السحابة فقط.
 * لا يمس SQLite على أجهزة العميل — الأجهزة قد تعيد الرفع عند المزامنة.
 */
export async function POST(req: Request) {
  try {
    const body = (await req.json()) as { userId?: string };
    const userId = (body.userId ?? "").trim();
    if (!userId) {
      return NextResponse.json({ error: "معرّف المستخدم ناقص" }, { status: 400 });
    }

    const supabase = getSupabaseAdmin();

    const { error: cErr } = await supabase
      .from("app_snapshot_chunks")
      .delete()
      .eq("user_id", userId);
    if (cErr) {
      return NextResponse.json({ error: `chunks: ${cErr.message}` }, { status: 400 });
    }

    const { error: sErr } = await supabase
      .from("app_snapshots")
      .delete()
      .eq("user_id", userId);
    if (sErr) {
      return NextResponse.json({ error: `snapshots: ${sErr.message}` }, { status: 400 });
    }

    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
