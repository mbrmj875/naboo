import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

/** حذف صف ترخيص نهائياً من جدول licenses (service role). */
export async function POST(req: Request) {
  try {
    const body = (await req.json()) as { licenseId?: number };
    const licenseId = Number(body.licenseId);
    if (!Number.isFinite(licenseId) || licenseId <= 0) {
      return NextResponse.json({ error: "معرّف الترخيص غير صالح" }, { status: 400 });
    }
    const supabase = getSupabaseAdmin();
    const { error } = await supabase.from("licenses").delete().eq("id", licenseId);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
