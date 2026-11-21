import { getSupabaseAdmin } from "@/lib/supabase-admin";
import type { FieldSyncOp } from "@/lib/field-hash";

export type FieldRepRow = {
  id: string;
  username: string;
  password_hash: string;
  display_name: string;
  is_active: boolean;
  disabled_at: string | null;
  disabled_reason: string | null;
  password_version: number;
  created_at: string;
};

export type FieldVisitRow = {
  id: string;
  rep_id: string;
  territory_id: string | null;
  shop_name: string;
  owner_name: string;
  phone: string | null;
  lat: number;
  lng: number;
  gps_accuracy: number | null;
  location_source: "gps" | "manual";
  geo_warning: string | null;
  interest: string;
  notes: string | null;
  visited_at: string;
  client_op_id: string | null;
  created_at: string;
  updated_at: string;
};

export type FieldTerritoryRow = {
  id: string;
  rep_id: string;
  name: string;
  geom_geojson: unknown;
  status: "active" | "released";
  client_op_id: string | null;
  claimed_at: string;
  released_at: string | null;
  created_at: string;
  updated_at: string;
};

export type FieldVisitEventRow = {
  id: number;
  visit_id: string;
  actor_rep_id: string | null;
  actor_kind: "rep" | "admin";
  field_name: string;
  old_value: string | null;
  new_value: string | null;
  created_at: string;
};

export async function findRepByUsername(
  username: string,
): Promise<FieldRepRow | null> {
  const { data, error } = await getSupabaseAdmin()
    .from("field_reps")
    .select("*")
    .eq("username", username.trim().toLowerCase())
    .maybeSingle();
  if (error) throw error;
  return (data as FieldRepRow | null) ?? null;
}

export async function findRepById(id: string): Promise<FieldRepRow | null> {
  const { data, error } = await getSupabaseAdmin()
    .from("field_reps")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return (data as FieldRepRow | null) ?? null;
}

export async function findSyncLog(
  clientOpId: string,
  operationHash: string,
): Promise<{ result_json: unknown } | null> {
  const { data, error } = await getSupabaseAdmin()
    .from("field_sync_log")
    .select("result_json")
    .eq("client_op_id", clientOpId)
    .eq("operation_hash", operationHash)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function insertSyncLog(input: {
  client_op_id: string;
  operation_hash: string;
  rep_id: string;
  op: FieldSyncOp;
  result_json: Record<string, unknown>;
}): Promise<void> {
  const { error } = await getSupabaseAdmin().from("field_sync_log").insert(input);
  if (error) throw error;
}

export async function insertVisitEvent(input: {
  visit_id: string;
  actor_rep_id: string | null;
  actor_kind: "rep" | "admin";
  field_name: string;
  old_value: string | null;
  new_value: string | null;
}): Promise<void> {
  const { error } = await getSupabaseAdmin()
    .from("field_visit_events")
    .insert(input);
  if (error) throw error;
}

export async function getVisitById(
  visitId: string,
): Promise<FieldVisitRow | null> {
  const { data, error } = await getSupabaseAdmin()
    .from("field_visits")
    .select("*")
    .eq("id", visitId)
    .maybeSingle();
  if (error) throw error;
  return (data as FieldVisitRow | null) ?? null;
}

export async function listVisitsForRep(
  repId: string,
  opts?: { days?: number; limit?: number },
): Promise<FieldVisitRow[]> {
  const days = opts?.days ?? 60;
  const limit = opts?.limit ?? 500;
  const since = new Date();
  since.setDate(since.getDate() - days);

  const { data, error } = await getSupabaseAdmin()
    .from("field_visits")
    .select("*")
    .eq("rep_id", repId)
    .gte("visited_at", since.toISOString())
    .order("visited_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data as FieldVisitRow[]) ?? [];
}

export async function listTerritoriesForRep(
  repId: string,
  status: "active" | "released" | "all" = "active",
): Promise<FieldTerritoryRow[]> {
  let q = getSupabaseAdmin()
    .from("field_territories")
    .select("*")
    .eq("rep_id", repId)
    .order("claimed_at", { ascending: false });
  if (status !== "all") q = q.eq("status", status);
  const { data, error } = await q;
  if (error) throw error;
  return (data as FieldTerritoryRow[]) ?? [];
}

export async function listAllReps(includeDisabled = true): Promise<
  Omit<FieldRepRow, "password_hash">[]
> {
  let q = getSupabaseAdmin()
    .from("field_reps")
    .select(
      "id, username, display_name, is_active, disabled_at, disabled_reason, password_version, created_at",
    )
    .order("created_at", { ascending: false });
  if (!includeDisabled) q = q.eq("is_active", true);
  const { data, error } = await q;
  if (error) throw error;
  return (data as Omit<FieldRepRow, "password_hash">[]) ?? [];
}

export async function adminListRecentVisits(opts?: {
  limit?: number;
  repId?: string;
  interest?: string;
}): Promise<FieldVisitRow[]> {
  const limit = opts?.limit ?? 50;
  let q = getSupabaseAdmin()
    .from("field_visits")
    .select("*")
    .order("visited_at", { ascending: false })
    .limit(limit);
  if (opts?.repId) q = q.eq("rep_id", opts.repId);
  if (opts?.interest) q = q.eq("interest", opts.interest);
  const { data, error } = await q;
  if (error) throw error;
  return (data as FieldVisitRow[]) ?? [];
}

export async function adminVisitStats(): Promise<{
  today: number;
  byInterest: Record<string, number>;
  activeTerritories: number;
  activeReps: number;
}> {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const sb = getSupabaseAdmin();

  const [todayRes, interestRes, terrRes, repsRes] = await Promise.all([
    sb
      .from("field_visits")
      .select("id", { count: "exact", head: true })
      .gte("visited_at", start.toISOString()),
    sb.from("field_visits").select("interest"),
    sb
      .from("field_territories")
      .select("id", { count: "exact", head: true })
      .eq("status", "active"),
    sb
      .from("field_reps")
      .select("id", { count: "exact", head: true })
      .eq("is_active", true),
  ]);

  const byInterest: Record<string, number> = {
    rejected: 0,
    warm: 0,
    interested: 0,
    purchased: 0,
  };
  for (const row of (interestRes.data as { interest: string }[] | null) ?? []) {
    byInterest[row.interest] = (byInterest[row.interest] ?? 0) + 1;
  }

  return {
    today: todayRes.count ?? 0,
    byInterest,
    activeTerritories: terrRes.count ?? 0,
    activeReps: repsRes.count ?? 0,
  };
}

export async function listVisitEventsSince(
  sinceId: number,
  limit = 100,
): Promise<FieldVisitEventRow[]> {
  const { data, error } = await getSupabaseAdmin()
    .from("field_visit_events")
    .select("*")
    .gt("id", sinceId)
    .order("id", { ascending: true })
    .limit(limit);
  if (error) throw error;
  return (data as FieldVisitEventRow[]) ?? [];
}

export async function listVisitEventsForVisit(
  visitId: string,
): Promise<FieldVisitEventRow[]> {
  const { data, error } = await getSupabaseAdmin()
    .from("field_visit_events")
    .select("*")
    .eq("visit_id", visitId)
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) throw error;
  return (data as FieldVisitEventRow[]) ?? [];
}

const AUDIT_FIELDS = [
  "shop_name",
  "owner_name",
  "phone",
  "lat",
  "lng",
  "interest",
  "notes",
  "location_source",
] as const;

export async function writeVisitFieldAudits(opts: {
  visitId: string;
  actorRepId: string | null;
  actorKind: "rep" | "admin";
  before: Record<string, unknown>;
  after: Record<string, unknown>;
}): Promise<void> {
  for (const field of AUDIT_FIELDS) {
    const oldV = opts.before[field];
    const newV = opts.after[field];
    if (oldV === newV) continue;
    if (String(oldV ?? "") === String(newV ?? "")) continue;
    await insertVisitEvent({
      visit_id: opts.visitId,
      actor_rep_id: opts.actorRepId,
      actor_kind: opts.actorKind,
      field_name: field,
      old_value: oldV == null ? null : String(oldV),
      new_value: newV == null ? null : String(newV),
    });
  }
}
