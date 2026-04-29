import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

const ALLOWED_STATUS = new Set(["active", "suspended", "expired", "trial", "none"]);
const ALLOWED_PLAN = new Set(["basic", "pro", "unlimited"]);

type Body = {
  licenseId: number;
  patch: {
    status?: string;
    expires_at?: string | null;
    business_name?: string | null;
    max_devices?: number | null;
    plan?: string;
    assigned_user_id?: string | null;
    /** لمسح تسجيل الأجهزة فقط — يُقبل `{}` لتفريغ JSON */
    registered_devices?: Record<string, never> | null;
  };
};

function isUuid(v: string): boolean {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/.test(
    v.trim(),
  );
}

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
    if (patch.plan !== undefined) {
      if (!ALLOWED_PLAN.has(patch.plan)) {
        return NextResponse.json(
          { error: `خطة غير مسموحة: ${patch.plan}` },
          { status: 400 },
        );
      }
      row.plan = patch.plan;
    }
    if (patch.assigned_user_id !== undefined) {
      const v = patch.assigned_user_id;
      if (v === null || v === "") {
        row.assigned_user_id = null;
      } else if (typeof v === "string" && isUuid(v)) {
        row.assigned_user_id = v.trim();
      } else {
        return NextResponse.json(
          { error: "assigned_user_id يجب أن يكون UUID أو فارغاً لإزالة الربط" },
          { status: 400 },
        );
      }
    }
    if (patch.registered_devices !== undefined) {
      const r = patch.registered_devices;
      if (
        r !== null &&
        (typeof r !== "object" || Object.keys(r as object).length > 0)
      ) {
        return NextResponse.json(
          { error: "مسح الأجهزة: أرسل فقط كائناً فارغاً {} أو null" },
          { status: 400 },
        );
      }
      row.registered_devices = r ?? {};
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
