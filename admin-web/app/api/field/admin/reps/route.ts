import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { hashPassword } from "@/lib/field-auth";
import {
  adminListRecentVisits,
  adminVisitStats,
  listAllReps,
  listVisitEventsForVisit,
} from "@/lib/field-db";
import { FIELD_MESSAGES } from "@/lib/field-messages";
import {
  invalidatePwdVersionCache,
  setPwdVersionCache,
} from "@/lib/field-pwdver-cache";
import { requireAdminSession } from "@/lib/field-request";
import {
  AdminCreateRepSchema,
  AdminUpdateRepSchema,
} from "@/lib/field-schemas";

export async function GET(req: Request) {
  const auth = await requireAdminSession();
  if (!auth.ok) return auth.response;

  const url = new URL(req.url);
  const visitId = url.searchParams.get("visit_id");
  if (visitId) {
    const events = await listVisitEventsForVisit(visitId);
    return NextResponse.json({ events });
  }

  const includeDisabled = url.searchParams.get("all") !== "0";
  const repId = url.searchParams.get("rep_id") ?? undefined;
  const interest = url.searchParams.get("interest") ?? undefined;

  const [reps, visits, stats] = await Promise.all([
    listAllReps(includeDisabled),
    adminListRecentVisits({ limit: 50, repId, interest }),
    adminVisitStats(),
  ]);

  return NextResponse.json({ reps, visits, stats });
}

export async function POST(req: Request) {
  try {
    const auth = await requireAdminSession();
    if (!auth.ok) return auth.response;

    const body = await req.json();
    const parsed = AdminCreateRepSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        {
          error: FIELD_MESSAGES.VALIDATION_ERROR,
          code: "VALIDATION_ERROR",
          errors: parsed.error.flatten().fieldErrors,
        },
        { status: 400 },
      );
    }

    const username = parsed.data.username.trim().toLowerCase();
    const password_hash = await hashPassword(parsed.data.password);

    const { data, error } = await getSupabaseAdmin()
      .from("field_reps")
      .insert({
        username,
        password_hash,
        display_name: parsed.data.display_name.trim(),
        is_active: true,
        password_version: 1,
      })
      .select(
        "id, username, display_name, is_active, disabled_at, disabled_reason, password_version, created_at",
      )
      .single();

    if (error) {
      const msg =
        error.code === "23505"
          ? "اسم المستخدم مستخدم مسبقاً"
          : error.message;
      return NextResponse.json({ error: msg }, { status: 400 });
    }

    return NextResponse.json({ ok: true, rep: data });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}

export async function PATCH(req: Request) {
  try {
    const auth = await requireAdminSession();
    if (!auth.ok) return auth.response;

    const body = await req.json();
    const parsed = AdminUpdateRepSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        {
          error: FIELD_MESSAGES.VALIDATION_ERROR,
          code: "VALIDATION_ERROR",
          errors: parsed.error.flatten().fieldErrors,
        },
        { status: 400 },
      );
    }

    const { rep_id, action } = parsed.data;

    if (action === "disable") {
      const { data, error } = await getSupabaseAdmin()
        .from("field_reps")
        .update({
          is_active: false,
          disabled_at: new Date().toISOString(),
          disabled_reason: parsed.data.disabled_reason ?? "تعطيل إداري",
        })
        .eq("id", rep_id)
        .select(
          "id, username, display_name, is_active, disabled_at, disabled_reason, password_version, created_at",
        )
        .single();
      if (error) {
        return NextResponse.json({ error: error.message }, { status: 500 });
      }
      return NextResponse.json({ ok: true, rep: data });
    }

    if (action === "enable") {
      const { data, error } = await getSupabaseAdmin()
        .from("field_reps")
        .update({
          is_active: true,
          disabled_at: null,
          disabled_reason: null,
        })
        .eq("id", rep_id)
        .select(
          "id, username, display_name, is_active, disabled_at, disabled_reason, password_version, created_at",
        )
        .single();
      if (error) {
        return NextResponse.json({ error: error.message }, { status: 500 });
      }
      return NextResponse.json({ ok: true, rep: data });
    }

    // reset_password
    if (!parsed.data.password) {
      return NextResponse.json(
        { error: "كلمة المرور الجديدة مطلوبة", code: "VALIDATION_ERROR" },
        { status: 400 },
      );
    }
    const password_hash = await hashPassword(parsed.data.password);
    const current = await getSupabaseAdmin()
      .from("field_reps")
      .select("password_version")
      .eq("id", rep_id)
      .single();
    if (current.error || !current.data) {
      return NextResponse.json({ error: "المندوب غير موجود" }, { status: 404 });
    }
    const nextVer = (current.data.password_version as number) + 1;
    const { data, error } = await getSupabaseAdmin()
      .from("field_reps")
      .update({
        password_hash,
        password_version: nextVer,
      })
      .eq("id", rep_id)
      .select(
        "id, username, display_name, is_active, disabled_at, disabled_reason, password_version, created_at",
      )
      .single();
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
    invalidatePwdVersionCache(rep_id);
    setPwdVersionCache(rep_id, nextVer);
    return NextResponse.json({ ok: true, rep: data });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
