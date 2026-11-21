import { createHash } from "crypto";

export type FieldSyncOp =
  | "create_visit"
  | "update_visit"
  | "create_territory"
  | "update_territory";

export type VisitHashPayload = {
  shop_name?: string | null;
  owner_name?: string | null;
  phone?: string | null;
  lat?: number | null;
  lng?: number | null;
  interest?: string | null;
  notes?: string | null;
  location_source?: string | null;
  name?: string | null;
  geom_geojson?: unknown;
  status?: string | null;
};

/**
 * Canonical hash — must match client Web Crypto implementation field-hash-client.ts
 * Keys sorted; nulls explicit; visitId optional for updates.
 */
export function buildCanonicalObject(
  op: FieldSyncOp,
  payload: VisitHashPayload,
  visitId?: string | null,
): Record<string, unknown> {
  if (op === "create_territory" || op === "update_territory") {
    return {
      geom_geojson: payload.geom_geojson ?? null,
      interest: null,
      lat: null,
      lng: null,
      location_source: null,
      name: payload.name ?? null,
      notes: null,
      op,
      owner_name: null,
      phone: null,
      shop_name: null,
      status: payload.status ?? null,
      visitId: visitId ?? null,
    };
  }

  return {
    geom_geojson: null,
    interest: payload.interest ?? null,
    lat: payload.lat ?? null,
    lng: payload.lng ?? null,
    location_source: payload.location_source ?? null,
    name: null,
    notes: payload.notes ?? null,
    op,
    owner_name: payload.owner_name ?? null,
    phone: payload.phone ?? null,
    shop_name: payload.shop_name ?? null,
    status: null,
    visitId: visitId ?? null,
  };
}

export function computeOperationHash(
  op: FieldSyncOp,
  payload: VisitHashPayload,
  visitId?: string | null,
): string {
  const canonical = buildCanonicalObject(op, payload, visitId);
  const keys = Object.keys(canonical).sort();
  const ordered: Record<string, unknown> = {};
  for (const k of keys) ordered[k] = canonical[k];
  const json = JSON.stringify(ordered);
  return createHash("sha256").update(json).digest("hex");
}
