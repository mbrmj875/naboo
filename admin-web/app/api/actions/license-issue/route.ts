import { randomUUID } from "node:crypto";
import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { maxDevicesForPlan, PLAN_KEYS, type PlanKey } from "@/lib/plan-presets";
import { importRsaPrivateKeyFromPem, signLicenseJwt } from "@/lib/license-jwt-sign";
import {
  expandLicensePrivateKeyPath,
  resolveLicenseJwtPrivateKeyPem,
} from "@/lib/resolve-license-private-pem";

type Body = {
  tenant_id?: string;
  plan?: string;
  max_devices?: number | null;
  starts_at?: string | null;
  ends_at?: string | null;
  is_trial?: boolean;
  business_name?: string | null;
  assigned_user_id?: string | null;
};

function isUuid(v: string): boolean {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/.test(
    v.trim(),
  );
}

/**
 * إصدار ترخيص v2: صف في `licenses` + JWT موقّع RS256 للعميل.
 * يتطلب LICENSE_JWT_KID ومفتاحاً خاصاً: يُفضّل PATH ثم PEM (راجع resolve-license-private-pem).
 */
export async function POST(req: Request) {
  let insertedId: number | null = null;
  try {
    const pathRaw = process.env.LICENSE_JWT_PRIVATE_KEY_PATH?.trim();
    const pem = resolveLicenseJwtPrivateKeyPem();
    const kid = process.env.LICENSE_JWT_KID?.trim();
    if (!pem) {
      const pathHint =
        pathRaw != null && pathRaw !== ""
          ? ` تعذر قراءة الملف: ${expandLicensePrivateKeyPath(pathRaw)} (تحقق من المسار والأذونات).`
          : "";
      return NextResponse.json(
        {
          error:
            "لم يُضبط مفتاح التوقيع: اضبط LICENSE_JWT_PRIVATE_KEY_PEM أو LICENSE_JWT_PRIVATE_KEY_PATH في .env.local داخل مجلد admin-web ثم أعد تشغيل الخادم." +
            pathHint,
        },
        { status: 503 },
      );
    }
    if (!kid) {
      return NextResponse.json(
        { error: "لم يُضبط LICENSE_JWT_KID — يجب أن يطابق المفتاح العام في التطبيق" },
        { status: 503 },
      );
    }

    const body = (await req.json()) as Body;
    const tenantId = (body.tenant_id ?? "").trim();
    if (!tenantId) {
      return NextResponse.json({ error: "tenant_id مطلوب" }, { status: 400 });
    }

    const rawPlan = (body.plan ?? "").trim().toLowerCase();
    if (!PLAN_KEYS.includes(rawPlan as PlanKey)) {
      return NextResponse.json(
        { error: `الخطة يجب أن تكون واحدة من: ${PLAN_KEYS.join(", ")}` },
        { status: 400 },
      );
    }
    const plan = rawPlan as PlanKey;

    let maxDevices: number;
    if (body.max_devices != null && Number.isFinite(Number(body.max_devices))) {
      const n = Number(body.max_devices);
      if (n < 0) {
        return NextResponse.json({ error: "max_devices غير صالح" }, { status: 400 });
      }
      maxDevices = Math.floor(n);
    } else {
      maxDevices = maxDevicesForPlan(plan);
    }

    const now = new Date();
    const startsAt = body.starts_at?.trim()
      ? new Date(body.starts_at.trim())
      : now;
    const endsAt = body.ends_at?.trim()
      ? new Date(body.ends_at.trim())
      : new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

    if (Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime())) {
      return NextResponse.json(
        { error: "starts_at أو ends_at ليست تواريخاً صالحة (ISO 8601)" },
        { status: 400 },
      );
    }
    if (endsAt.getTime() <= startsAt.getTime()) {
      return NextResponse.json(
        { error: "ends_at يجب أن يكون بعد starts_at" },
        { status: 400 },
      );
    }

    const isTrial = Boolean(body.is_trial);
    const businessName =
      typeof body.business_name === "string" ? body.business_name.trim() : "";
    const rawAssign = body.assigned_user_id;
    let assignedUserId: string | null = null;
    if (rawAssign != null && String(rawAssign).trim() !== "") {
      const aid = String(rawAssign).trim();
      if (!isUuid(aid)) {
        return NextResponse.json(
          { error: "assigned_user_id يجب أن يكون UUID لمستخدم صالح" },
          { status: 400 },
        );
      }
      assignedUserId = aid;
    }

    const licenseKeyPlaceholder = `V2-${randomUUID()}`;
    const status = isTrial ? "trial" : "active";
    const trialStartedAt = isTrial ? startsAt.toISOString() : null;
    const expiresAt = endsAt.toISOString();

    const supabase = getSupabaseAdmin();
    const row: Record<string, unknown> = {
      license_key: licenseKeyPlaceholder,
      status,
      plan,
      max_devices: maxDevices,
      registered_devices: {},
      business_name: businessName || null,
      expires_at: expiresAt,
    };
    if (trialStartedAt) row.trial_started_at = trialStartedAt;
    if (assignedUserId) row.assigned_user_id = assignedUserId;

    const { data: inserted, error: insErr } = await supabase
      .from("licenses")
      .insert(row)
      .select("id")
      .single();

    if (insErr || !inserted?.id) {
      return NextResponse.json(
        { error: insErr?.message ?? "فشل إدراج الترخيص" },
        { status: 400 },
      );
    }
    insertedId = inserted.id as number;

    const privateKey = await importRsaPrivateKeyFromPem(pem);
    const issuedAt = new Date();
    const jwt = await signLicenseJwt({
      privateKey,
      kid,
      claims: {
        tenantId,
        plan,
        maxDevices,
        startsAt,
        endsAt,
        licenseId: String(insertedId),
        isTrial,
        issuedAt,
      },
    });

    const { error: jwtSaveErr } = await supabase
      .from("licenses")
      .update({ license_jwt: jwt })
      .eq("id", insertedId);

    if (jwtSaveErr) {
      try {
        await supabase.from("licenses").delete().eq("id", insertedId);
      } catch {
        /* ignore */
      }
      const hint =
        jwtSaveErr.message?.includes("license_jwt") || jwtSaveErr.message?.includes("column")
          ? " نفّذ admin-web/supabase/licenses_license_jwt.sql في Supabase ثم أعد المحاولة."
          : "";
      return NextResponse.json(
        {
          error: (jwtSaveErr.message ?? "فشل حفظ JWT في قاعدة البيانات") + hint,
        },
        { status: 400 },
      );
    }

    return NextResponse.json({
      ok: true,
      jwt,
      license_id: insertedId,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    if (insertedId != null) {
      try {
        const supabase = getSupabaseAdmin();
        await supabase.from("licenses").delete().eq("id", insertedId);
      } catch {
        /* ignore */
      }
    }
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
