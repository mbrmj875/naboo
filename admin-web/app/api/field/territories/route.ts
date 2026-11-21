import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { requireFieldSession } from "@/lib/field-request";
import {
  findSyncLog,
  insertSyncLog,
  listTerritoriesForRep,
} from "@/lib/field-db";
import { computeOperationHash } from "@/lib/field-hash";
import { FIELD_MESSAGES } from "@/lib/field-messages";
import {
  CreateTerritorySchema,
  UpdateTerritorySchema,
} from "@/lib/field-schemas";

export async function GET() {
  const auth = await requireFieldSession();
  if (!auth.ok) return auth.response;
  const territories = await listTerritoriesForRep(auth.session.repId, "active");
  return NextResponse.json({ territories });
}

export async function POST(req: Request) {
  try {
    const auth = await requireFieldSession();
    if (!auth.ok) return auth.response;

    const body = await req.json();
    const parsed = CreateTerritorySchema.safeParse(body);
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

    const payload = parsed.data;
    const expectedHash = computeOperationHash(
      "create_territory",
      {
        name: payload.name,
        geom_geojson: payload.geom_geojson,
        status: "active",
      },
      null,
    ).toLowerCase();
    if (payload.operation_hash.toLowerCase() !== expectedHash) {
      return NextResponse.json(
        { error: FIELD_MESSAGES.VALIDATION_ERROR, code: "HASH_MISMATCH" },
        { status: 400 },
      );
    }

    const existing = await findSyncLog(
      payload.client_op_id,
      payload.operation_hash.toLowerCase(),
    );
    if (existing) {
      return NextResponse.json({
        status: "already_processed",
        result: existing.result_json,
      });
    }

    const ring = payload.geom_geojson.coordinates[0];
    if (!ring || ring.length < 4) {
      return NextResponse.json(
        {
          error: "المضلع يحتاج 3 نقاط على الأقل ثم إغلاق",
          code: "VALIDATION_ERROR",
        },
        { status: 400 },
      );
    }

    const { data: territory, error } = await getSupabaseAdmin()
      .from("field_territories")
      .insert({
        rep_id: auth.session.repId,
        name: payload.name,
        geom_geojson: payload.geom_geojson,
        status: "active",
        client_op_id: payload.client_op_id,
        claimed_at: payload.client_updated_at,
        updated_at: new Date().toISOString(),
      })
      .select("id")
      .single();

    if (error || !territory) {
      return NextResponse.json(
        { error: error?.message ?? "فشل الحفظ" },
        { status: 500 },
      );
    }

    const result = { territory_id: territory.id as string };
    await insertSyncLog({
      client_op_id: payload.client_op_id,
      operation_hash: payload.operation_hash.toLowerCase(),
      rep_id: auth.session.repId,
      op: "create_territory",
      result_json: result,
    });

    return NextResponse.json({ status: "synced", result });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}

export async function PATCH(req: Request) {
  try {
    const auth = await requireFieldSession();
    if (!auth.ok) return auth.response;

    const body = await req.json();
    const parsed = UpdateTerritorySchema.safeParse(body);
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

    const payload = parsed.data;
    const expectedHash = computeOperationHash(
      "update_territory",
      {
        name: payload.name ?? null,
        status: payload.status ?? null,
      },
      payload.territory_id,
    ).toLowerCase();
    if (payload.operation_hash.toLowerCase() !== expectedHash) {
      return NextResponse.json(
        { error: FIELD_MESSAGES.VALIDATION_ERROR, code: "HASH_MISMATCH" },
        { status: 400 },
      );
    }

    const existing = await findSyncLog(
      payload.client_op_id,
      payload.operation_hash.toLowerCase(),
    );
    if (existing) {
      return NextResponse.json({
        status: "already_processed",
        result: existing.result_json,
      });
    }

    const patch: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };
    if (payload.name != null) patch.name = payload.name;
    if (payload.status != null) {
      patch.status = payload.status;
      if (payload.status === "released") {
        patch.released_at = new Date().toISOString();
      }
    }

    const { data, error } = await getSupabaseAdmin()
      .from("field_territories")
      .update(patch)
      .eq("id", payload.territory_id)
      .eq("rep_id", auth.session.repId)
      .select("id")
      .maybeSingle();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
    if (!data) {
      return NextResponse.json(
        { error: "المنطقة غير موجودة", code: "NOT_FOUND" },
        { status: 404 },
      );
    }

    const result = { territory_id: data.id as string };
    await insertSyncLog({
      client_op_id: payload.client_op_id,
      operation_hash: payload.operation_hash.toLowerCase(),
      rep_id: auth.session.repId,
      op: "update_territory",
      result_json: result,
    });

    return NextResponse.json({ status: "synced", result });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
