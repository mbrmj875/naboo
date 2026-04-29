import { randomInt } from "crypto";
import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { maxDevicesForPlan, PLAN_KEYS, type PlanKey } from "@/lib/plan-presets";

function generateLicenseKey(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const segment = () =>
    Array.from({ length: 4 }, () => alphabet[randomInt(alphabet.length)]).join("");
  return `NABOO-${segment()}-${segment()}-${segment()}`;
}

type Body = {
  plan?: string;
  business_name?: string | null;
  /** عدد الشهور لـ expires_at؛ يُهمِّل لو status=trial وليس نشطاً بتاريخ */
  months_valid?: number | null;
  status?: string;
  /** ربط إداري بمستخدم Supabase (اختياري) */
  assigned_user_id?: string | null;
};

function isUuid(v: string): boolean {
  return /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/.test(
    v.trim(),
  );
}

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const rawPlan = body.plan ?? "";
    if (!PLAN_KEYS.includes(rawPlan as PlanKey)) {
      return NextResponse.json(
        { error: `الخطة يجب أن تكون واحدة من: ${PLAN_KEYS.join(", ")}` },
        { status: 400 },
      );
    }
    const plan = rawPlan as PlanKey;

    let status = (body.status ?? "active").toLowerCase();
    if (!["active", "trial"].includes(status)) status = "active";

    let expires_at: string | null = null;
    const months =
      body.months_valid != null ? Number(body.months_valid) : null;
    if (
      status === "active" &&
      months != null &&
      Number.isFinite(months) &&
      months > 0 &&
      months <= 120
    ) {
      const d = new Date();
      d.setUTCMonth(d.getUTCMonth() + Math.floor(months));
      expires_at = d.toISOString();
    }

    const trial_started_at =
      status === "trial" ? new Date().toISOString() : null;

    const supabase = getSupabaseAdmin();
    const business_name =
      typeof body.business_name === "string" ? body.business_name.trim() : "";
    const row: Record<string, unknown> = {
      license_key: "",
      status,
      plan,
      max_devices: maxDevicesForPlan(plan),
      registered_devices: {},
      business_name: business_name || null,
      expires_at,
    };
    if (trial_started_at) row.trial_started_at = trial_started_at;

    const rawAssign = body.assigned_user_id;
    if (rawAssign != null && String(rawAssign).trim() !== "") {
      const aid = String(rawAssign).trim();
      if (!isUuid(aid)) {
        return NextResponse.json(
          { error: "assigned_user_id يجب أن يكون UUID لمستخدم صالح" },
          { status: 400 },
        );
      }
      row.assigned_user_id = aid;
    }

    for (let attempt = 0; attempt < 10; attempt++) {
      const license_key = generateLicenseKey();
      row.license_key = license_key;
      const { data, error } = await supabase
        .from("licenses")
        .insert(row)
        .select("id,license_key")
        .single();

      if (!error && data) {
        return NextResponse.json({
          ok: true,
          id: data.id as number,
          license_key: data.license_key as string,
        });
      }
      const msg = error?.message ?? "";
      if (!msg.toLowerCase().includes("duplicate") && !msg.includes("unique")) {
        return NextResponse.json({ error: msg }, { status: 400 });
      }
    }

    return NextResponse.json(
      { error: "تعذر إنشاء مفتاح فريد بعد عدة محاولات" },
      { status: 500 },
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
