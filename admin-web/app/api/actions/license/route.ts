import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

const ALLOWED_STATUS = new Set(["active", "suspended", "expired", "trial", "none"]);

type Body = {
  licenseId: number;
  patch: {
    status?: string;
    expires_at?: string | null;
    business_name?: string | null;
    max_devices?: number | null;
  };
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const licenseId = Number(body.licenseId);
    if (!Number.isFinite(licenseId) || licenseId <= 0) {
      return NextResponse.json({ error: "معرّف الترخيص غير صالح" }, { status: 400 });
    }
    const patch = body.patch ?? {};
    const row: Record<string, unknown> = {};
    if (patch.status !== undefined) {
      if (!ALLOWED_STATUS.has(patch.status)) {
        return NextResponse.json(
          { error: `حالة غير مسموحة: ${patch.status}` },
          { status: 400 },
        );
      }
      row.status = patch.status;
    }
    if (patch.expires_at !== undefined) {
      row.expires_at = patch.expires_at;
    }
    if (patch.business_name !== undefined) {
      row.business_name = patch.business_name;
    }
    if (patch.max_devices !== undefined) {
      row.max_devices = patch.max_devices;
    }
    if (Object.keys(row).length === 0) {
      return NextResponse.json({ error: "لا يوجد حقل للتحديث" }, { status: 400 });
    }
    const supabase = getSupabaseAdmin();
    const { error } = await supabase.from("licenses").update(row).eq("id", licenseId);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
