import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type Body = { licenseId?: number };

/**
 * إرجاع المفتاح الكامل لمشرف مسجّل دخول فقط — لا يُعرض في قائمة JSON العامة.
 */
export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const licenseId = Number(body.licenseId);
    if (!Number.isFinite(licenseId) || licenseId <= 0) {
      return NextResponse.json({ error: "معرّف غير صالح" }, { status: 400 });
    }
    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from("licenses")
      .select("license_key")
      .eq("id", licenseId)
      .maybeSingle();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    if (!data?.license_key) {
      return NextResponse.json({ error: "لم يُعثر على الترخيص" }, { status: 404 });
    }
    return NextResponse.json({ license_key: String(data.license_key) });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
