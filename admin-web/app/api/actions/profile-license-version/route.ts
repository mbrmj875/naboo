import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type Body = {
  userId: string;
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const userId = (body.userId ?? "").trim();
    if (!userId) {
      return NextResponse.json({ error: "معرّف المستخدم ناقص" }, { status: 400 });
    }

    const nowIso = new Date().toISOString();
    const supabase = getSupabaseAdmin();
    const { error } = await supabase
      .from("profiles")
      .update({
        // v2 هو النظام الوحيد المعتمد؛ لا نقبل إرجاع الحساب إلى v1.
        license_system_version: "v2",
        updated_at: nowIso,
      })
      .eq("id", userId);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
