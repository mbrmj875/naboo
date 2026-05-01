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
      .select("license_key, license_jwt")
      .eq("id", licenseId)
      .maybeSingle();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    if (!data?.license_key && !data?.license_jwt) {
      return NextResponse.json({ error: "لم يُعثر على الترخيص" }, { status: 404 });
    }

    const jwt =
      data.license_jwt != null && String(data.license_jwt).trim() !== ""
        ? String(data.license_jwt).trim()
        : "";
    if (jwt.split(".").length === 3) {
      return NextResponse.json({ license_key: jwt });
    }

    const legacy = String(data.license_key ?? "");
    if (legacy.startsWith("V2-")) {
      return NextResponse.json(
        {
          error:
            "لا يوجد JWT محفوظ لهذا السجل (صدر قبل تفعيل العمود license_jwt أو فشل الحفظ). نفّذ licenses_license_jwt.sql ثم أصدر ترخيصاً جديداً أو انسخ JWT من وقت الإصدار.",
        },
        { status: 409 },
      );
    }

    return NextResponse.json({ license_key: legacy });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
