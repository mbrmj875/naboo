import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { requireFieldSession } from "@/lib/field-request";
import {
  findSyncLog,
  getVisitById,
  insertSyncLog,
  insertVisitEvent,
  listVisitsForRep,
  writeVisitFieldAudits,
} from "@/lib/field-db";
import { computeOperationHash } from "@/lib/field-hash";
import { checkVisitGeo } from "@/lib/field-geo";
import { FIELD_MESSAGES } from "@/lib/field-messages";
import { CreateVisitSchema, UpdateVisitSchema } from "@/lib/field-schemas";

export async function GET(req: Request) {
  const auth = await requireFieldSession();
  if (!auth.ok) return auth.response;

  const url = new URL(req.url);
  const days = Number(url.searchParams.get("days") ?? "60");
  const visits = await listVisitsForRep(auth.session.repId, {
    days: Number.isFinite(days) ? days : 60,
  });
  return NextResponse.json({ visits });
}

export async function POST(req: Request) {
  try {
    const auth = await requireFieldSession();
    if (!auth.ok) return auth.response;

    const body = await req.json();
    const parsed = CreateVisitSchema.safeParse(body);
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
      "create_visit",
      payload,
      null,
    ).toLowerCase();
    if (payload.operation_hash.toLowerCase() !== expectedHash) {
      return NextResponse.json(
        {
          error: FIELD_MESSAGES.VALIDATION_ERROR,
          code: "HASH_MISMATCH",
        },
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

    const geo = checkVisitGeo({
      lat: payload.lat,
      lng: payload.lng,
      gpsAccuracy: payload.gps_accuracy,
      geoConfirmed: payload.geo_confirmed,
    });
    if (!geo.ok) {
      return NextResponse.json(
        {
          code: geo.code,
          error:
            geo.code === "GEO_CONFIRM_REQUIRED"
              ? FIELD_MESSAGES.GEO_CONFIRM_REQUIRED
              : FIELD_MESSAGES.OUT_OF_GOVERNORATE,
          distance_km: geo.distanceKm,
        },
        { status: 400 },
      );
    }

    const { data: visit, error } = await getSupabaseAdmin()
      .from("field_visits")
      .insert({
        rep_id: auth.session.repId,
        territory_id: payload.territory_id ?? null,
        shop_name: payload.shop_name,
        owner_name: payload.owner_name,
        phone: payload.phone ?? null,
        lat: payload.lat,
        lng: payload.lng,
        interest: payload.interest,
        notes: payload.notes ?? null,
        location_source: payload.location_source,
        gps_accuracy: payload.gps_accuracy ?? null,
        geo_warning: geo.geoWarning,
        client_op_id: payload.client_op_id,
        visited_at: payload.client_updated_at,
        updated_at: new Date().toISOString(),
      })
      .select("*")
      .single();

    if (error || !visit) {
      return NextResponse.json(
        { error: error?.message ?? "فشل الحفظ" },
        { status: 500 },
      );
    }

    const result = { visit_id: visit.id as string };
    await insertSyncLog({
      client_op_id: payload.client_op_id,
      operation_hash: payload.operation_hash.toLowerCase(),
      rep_id: auth.session.repId,
      op: "create_visit",
      result_json: result,
    });

    await insertVisitEvent({
      visit_id: visit.id as string,
      actor_rep_id: auth.session.repId,
      actor_kind: "rep",
      field_name: "created",
      old_value: null,
      new_value: JSON.stringify({
        shop_name: payload.shop_name,
        interest: payload.interest,
      }),
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
    const parsed = UpdateVisitSchema.safeParse(body);
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
      "update_visit",
      payload,
      payload.visit_id,
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

    const visit = await getVisitById(payload.visit_id);
    if (!visit || visit.rep_id !== auth.session.repId) {
      return NextResponse.json(
        { error: FIELD_MESSAGES.UNAUTHORIZED, code: "UNAUTHORIZED" },
        { status: 404 },
      );
    }

    const clientUpdated = new Date(payload.client_updated_at).getTime();
    const serverUpdated = new Date(visit.updated_at).getTime();
    // Allow 5s clock skew; otherwise LWW — client must be >= server
    if (clientUpdated + 5000 < serverUpdated) {
      return NextResponse.json(
        {
          status: "version_conflict",
          code: "VERSION_CONFLICT",
          error: FIELD_MESSAGES.VERSION_CONFLICT,
          visit,
        },
        { status: 409 },
      );
    }

    const nextLat = payload.lat ?? visit.lat;
    const nextLng = payload.lng ?? visit.lng;
    let geoWarning = visit.geo_warning;
    if (payload.lat != null || payload.lng != null) {
      const geo = checkVisitGeo({
        lat: nextLat,
        lng: nextLng,
        gpsAccuracy: payload.gps_accuracy,
        geoConfirmed: payload.geo_confirmed,
      });
      if (!geo.ok) {
        return NextResponse.json(
          {
            code: geo.code,
            error:
              geo.code === "GEO_CONFIRM_REQUIRED"
                ? FIELD_MESSAGES.GEO_CONFIRM_REQUIRED
                : FIELD_MESSAGES.OUT_OF_GOVERNORATE,
            distance_km: geo.distanceKm,
          },
          { status: 400 },
        );
      }
      geoWarning = geo.geoWarning;
    }

    const patch: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };
    if (payload.shop_name != null) patch.shop_name = payload.shop_name;
    if (payload.owner_name != null) patch.owner_name = payload.owner_name;
    if (payload.phone !== undefined) patch.phone = payload.phone;
    if (payload.lat != null) patch.lat = payload.lat;
    if (payload.lng != null) patch.lng = payload.lng;
    if (payload.interest != null) patch.interest = payload.interest;
    if (payload.notes !== undefined) patch.notes = payload.notes;
    if (payload.location_source != null) {
      patch.location_source = payload.location_source;
    }
    if (payload.gps_accuracy !== undefined) {
      patch.gps_accuracy = payload.gps_accuracy;
    }
    if (payload.lat != null || payload.lng != null) {
      patch.geo_warning = geoWarning;
    }

    const { data: updated, error } = await getSupabaseAdmin()
      .from("field_visits")
      .update(patch)
      .eq("id", visit.id)
      .eq("rep_id", auth.session.repId)
      .select("*")
      .single();

    if (error || !updated) {
      return NextResponse.json(
        { error: error?.message ?? "فشل التحديث" },
        { status: 500 },
      );
    }

    await writeVisitFieldAudits({
      visitId: visit.id,
      actorRepId: auth.session.repId,
      actorKind: "rep",
      before: visit as unknown as Record<string, unknown>,
      after: updated as unknown as Record<string, unknown>,
    });

    const result = { visit_id: visit.id };
    await insertSyncLog({
      client_op_id: payload.client_op_id,
      operation_hash: payload.operation_hash.toLowerCase(),
      rep_id: auth.session.repId,
      op: "update_visit",
      result_json: result,
    });

    return NextResponse.json({ status: "synced", result, visit: updated });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
