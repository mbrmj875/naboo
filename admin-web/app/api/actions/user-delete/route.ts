import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

/**
 * حذف حساب من Auth وما يرتبط به في السحابة (جدول محلي).
 * يتطابق البريد المُدخل مع بريد المستخدم لتقليل الخطأ.
 */
export async function POST(req: Request) {
  try {
    const body = (await req.json()) as { userId?: string; emailConfirm?: string };
    const userId = (body.userId ?? "").trim();
    const emailConfirm = (body.emailConfirm ?? "").trim().toLowerCase();
    if (!userId) {
      return NextResponse.json({ error: "معرّف المستخدم ناقص" }, { status: 400 });
    }
    if (!emailConfirm) {
      return NextResponse.json(
        { error: "يجب تأكيد البريد الإلكتروني للحساب" },
        { status: 400 },
      );
    }

    const supabase = getSupabaseAdmin();
    const { data: au, error: getErr } = await supabase.auth.admin.getUserById(userId);
    if (getErr || !au?.user) {
      return NextResponse.json(
        { error: getErr?.message ?? "لم يُعثر على المستخدم" },
        { status: 400 },
      );
    }
    const email = (au.user.email ?? "").trim().toLowerCase();
    if (!email || email !== emailConfirm) {
      return NextResponse.json(
        { error: "البريد المعروض لا يطابق حساب هذا المستخدم" },
        { status: 400 },
      );
    }

    const { error: l1 } = await supabase
      .from("licenses")
      .update({ assigned_user_id: null })
      .eq("assigned_user_id", userId);
    if (l1) {
      return NextResponse.json({ error: `تراخيص: ${l1.message}` }, { status: 400 });
    }

    const { error: d1 } = await supabase.from("account_devices").delete().eq("user_id", userId);
    if (d1) {
      return NextResponse.json({ error: `أجهزة: ${d1.message}` }, { status: 400 });
    }

    const { error: cErr } = await supabase.from("app_snapshot_chunks").delete().eq("user_id", userId);
    if (cErr) {
      return NextResponse.json({ error: `chunks: ${cErr.message}` }, { status: 400 });
    }
    const { error: sErr } = await supabase.from("app_snapshots").delete().eq("user_id", userId);
    if (sErr) {
      return NextResponse.json({ error: `snapshots: ${sErr.message}` }, { status: 400 });
    }

    const { error: pErr } = await supabase.from("profiles").delete().eq("id", userId);
    if (pErr) {
      return NextResponse.json({ error: `profiles: ${pErr.message}` }, { status: 400 });
    }

    const { error: authErr } = await supabase.auth.admin.deleteUser(userId);
    if (authErr) {
      return NextResponse.json({ error: authErr.message }, { status: 400 });
    }

    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
