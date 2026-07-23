import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import {
  LIFETIME_JWT_ENDS_AT,
  isLifetimePlan,
} from "@/lib/plan-presets";
import { importRsaPrivateKeyFromPem, signLicenseJwt } from "@/lib/license-jwt-sign";
import {
  expandLicensePrivateKeyPath,
  resolveLicenseJwtPrivateKeyPem,
} from "@/lib/resolve-license-private-pem";

type Body = {
  licenseId?: number;
  /** إجمالي الأجهزة (هاتف + حواسيب) — يُدمَج في JWT */
  max_devices?: number;
};

function isUuid(v: string): boolean {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/.test(
    v.trim(),
  );
}

/**
 * تحديث max_devices لترخيص v2 موجود + إعادة توقيع JWT.
 * يجب لصق المفتاح الجديد في التطبيق لأن حد الأجهزة داخل الـ JWT.
 */
export async function POST(req: Request) {
  try {
    const pathRaw = process.env.LICENSE_JWT_PRIVATE_KEY_PATH?.trim();
    const pem = resolveLicenseJwtPrivateKeyPem();
    const kid = process.env.LICENSE_JWT_KID?.trim();
    if (!pem) {
      const pathHint =
        pathRaw != null && pathRaw !== ""
          ? ` تعذر قراءة الملف: ${expandLicensePrivateKeyPath(pathRaw)}`
          : "";
      return NextResponse.json(
        {
          error:
            "لم يُضبط مفتاح التوقيع (LICENSE_JWT_PRIVATE_KEY_PEM أو PATH)." +
            pathHint,
        },
        { status: 503 },
      );
    }
    if (!kid) {
      return NextResponse.json(
        { error: "لم يُضبط LICENSE_JWT_KID" },
        { status: 503 },
      );
    }

    const body = (await req.json()) as Body;
    const licenseId = Number(body.licenseId);
    if (!Number.isFinite(licenseId) || licenseId <= 0) {
      return NextResponse.json({ error: "معرّف الترخيص غير صالح" }, { status: 400 });
    }
    const maxDevices = Number(body.max_devices);
    if (!Number.isFinite(maxDevices) || maxDevices < 1 || maxDevices > 64) {
      return NextResponse.json(
        { error: "max_devices يجب أن يكون بين 1 و 64" },
        { status: 400 },
      );
    }
    const maxDevicesInt = Math.floor(maxDevices);

    const supabase = getSupabaseAdmin();
    const { data: row, error: loadErr } = await supabase
      .from("licenses")
      .select(
        "id, plan, status, assigned_user_id, expires_at, trial_started_at, business_name",
      )
      .eq("id", licenseId)
      .maybeSingle();

    if (loadErr) {
      return NextResponse.json({ error: loadErr.message }, { status: 400 });
    }
    if (!row?.id) {
      return NextResponse.json({ error: "لم يُعثر على الترخيص" }, { status: 404 });
    }

    const tenantId = (row.assigned_user_id ?? "").toString().trim();
    if (!tenantId || !isUuid(tenantId)) {
      return NextResponse.json(
        {
          error:
            "الترخيص غير مربوط بحساب (assigned_user_id). اربطه بحساب أولاً ثم أعد المحاولة.",
        },
        { status: 400 },
      );
    }

    const plan = (row.plan ?? "monthly").toString().trim().toLowerCase() || "monthly";
    const isTrial = (row.status ?? "").toString().toLowerCase() === "trial";
    const lifetime = isLifetimePlan(plan);

    const now = new Date();
    let startsAt = now;
    if (row.trial_started_at) {
      const t = new Date(String(row.trial_started_at));
      if (!Number.isNaN(t.getTime())) startsAt = t;
    }

    let endsAt = LIFETIME_JWT_ENDS_AT;
    if (!lifetime) {
      if (row.expires_at) {
        const e = new Date(String(row.expires_at));
        if (!Number.isNaN(e.getTime())) endsAt = e;
        else endsAt = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
      } else {
        endsAt = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
      }
    }

    const { error: updErr } = await supabase
      .from("licenses")
      .update({ max_devices: maxDevicesInt })
      .eq("id", licenseId);

    if (updErr) {
      return NextResponse.json({ error: updErr.message }, { status: 400 });
    }

    const privateKey = await importRsaPrivateKeyFromPem(pem);
    const jwt = await signLicenseJwt({
      privateKey,
      kid,
      claims: {
        tenantId,
        plan,
        maxDevices: maxDevicesInt,
        startsAt,
        endsAt,
        licenseId: String(licenseId),
        isTrial,
        issuedAt: now,
      },
    });

    const { error: jwtErr } = await supabase
      .from("licenses")
      .update({ license_jwt: jwt })
      .eq("id", licenseId);

    if (jwtErr) {
      return NextResponse.json(
        { error: jwtErr.message ?? "فشل حفظ JWT" },
        { status: 400 },
      );
    }

    return NextResponse.json({
      ok: true,
      jwt,
      license_id: licenseId,
      max_devices: maxDevicesInt,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
