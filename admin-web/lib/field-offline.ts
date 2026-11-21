"use client";

import { openDB, type DBSchema, type IDBPDatabase } from "idb";

export type SyncStatus = "pending" | "syncing" | "synced" | "failed";

export type FieldOpKind =
  | "create_visit"
  | "update_visit"
  | "create_territory"
  | "update_territory";

export type QueuedOp = {
  id?: number;
  client_op_id: string;
  op: FieldOpKind;
  visit_id?: string | null;
  territory_id?: string | null;
  payload: Record<string, unknown>;
  operation_hash: string;
  client_updated_at: string;
  attempts: number;
  next_retry_at: number;
  last_error: string | null;
  status: SyncStatus;
  created_at: number;
  synced_at?: number | null;
};

export type CachedVisit = {
  id: string;
  local_key: string;
  shop_name: string;
  owner_name: string;
  phone: string | null;
  lat: number;
  lng: number;
  interest: string;
  notes: string | null;
  visited_at: string;
  sync_status: SyncStatus;
  location_source: string;
  geo_warning?: string | null;
  rep_id?: string;
};

export type CachedTerritory = {
  id: string;
  local_key: string;
  name: string;
  geom_geojson: unknown;
  status: string;
  sync_status: SyncStatus;
  claimed_at: string;
};

export type VisitDraft = {
  key: "current";
  data: Record<string, unknown>;
  saved_at: number;
};

interface FieldDbSchema extends DBSchema {
  op_queue: {
    key: number;
    value: QueuedOp;
    indexes: {
      by_status: SyncStatus;
      by_client_op: string;
      by_next_retry: number;
    };
  };
  visits_cache: {
    key: string;
    value: CachedVisit;
    indexes: { by_visited_at: string };
  };
  territories_cache: {
    key: string;
    value: CachedTerritory;
  };
  visit_drafts: {
    key: string;
    value: VisitDraft;
  };
  polygon_draft: {
    key: string;
    value: { key: string; points: [number, number][]; saved_at: number };
  };
  meta: {
    key: string;
    value: { key: string; value: unknown };
  };
}

let dbPromise: Promise<IDBPDatabase<FieldDbSchema>> | null = null;

export function openFieldDb() {
  if (!dbPromise) {
    dbPromise = openDB<FieldDbSchema>("naboo_field_app", 1, {
      upgrade(db) {
        const q = db.createObjectStore("op_queue", {
          keyPath: "id",
          autoIncrement: true,
        });
        q.createIndex("by_status", "status");
        q.createIndex("by_client_op", "client_op_id", { unique: true });
        q.createIndex("by_next_retry", "next_retry_at");

        const v = db.createObjectStore("visits_cache", { keyPath: "local_key" });
        v.createIndex("by_visited_at", "visited_at");

        db.createObjectStore("territories_cache", { keyPath: "local_key" });
        db.createObjectStore("visit_drafts", { keyPath: "key" });
        db.createObjectStore("polygon_draft", { keyPath: "key" });
        db.createObjectStore("meta", { keyPath: "key" });
      },
    });
  }
  return dbPromise;
}

export async function enqueueOp(
  op: Omit<QueuedOp, "id" | "attempts" | "next_retry_at" | "last_error" | "status" | "created_at"> &
    Partial<Pick<QueuedOp, "attempts" | "status">>,
): Promise<number> {
  const db = await openFieldDb();
  const row: QueuedOp = {
    ...op,
    attempts: op.attempts ?? 0,
    next_retry_at: Date.now(),
    last_error: null,
    status: op.status ?? "pending",
    created_at: Date.now(),
  };
  return db.add("op_queue", row);
}

export async function listPendingOps(): Promise<QueuedOp[]> {
  const db = await openFieldDb();
  const all = await db.getAll("op_queue");
  return all
    .filter((o) => o.status === "pending" || o.status === "failed")
    .filter((o) => o.next_retry_at <= Date.now())
    .sort((a, b) => a.created_at - b.created_at);
}

export async function updateQueuedOp(
  id: number,
  patch: Partial<QueuedOp>,
): Promise<void> {
  const db = await openFieldDb();
  const row = await db.get("op_queue", id);
  if (!row) return;
  await db.put("op_queue", { ...row, ...patch });
}

export async function putVisitCache(visit: CachedVisit): Promise<void> {
  const db = await openFieldDb();
  await db.put("visits_cache", visit);
}

export async function listVisitCache(): Promise<CachedVisit[]> {
  const db = await openFieldDb();
  const all = await db.getAll("visits_cache");
  return all.sort((a, b) => (a.visited_at < b.visited_at ? 1 : -1));
}

export async function putTerritoryCache(t: CachedTerritory): Promise<void> {
  const db = await openFieldDb();
  await db.put("territories_cache", t);
}

export async function listTerritoryCache(): Promise<CachedTerritory[]> {
  const db = await openFieldDb();
  return db.getAll("territories_cache");
}

export async function saveVisitDraft(
  data: Record<string, unknown>,
): Promise<void> {
  const db = await openFieldDb();
  await db.put("visit_drafts", { key: "current", data, saved_at: Date.now() });
}

export async function loadVisitDraft(): Promise<VisitDraft | undefined> {
  const db = await openFieldDb();
  return db.get("visit_drafts", "current");
}

export async function clearVisitDraft(): Promise<void> {
  const db = await openFieldDb();
  await db.delete("visit_drafts", "current");
}

export async function savePolygonDraft(
  points: [number, number][],
): Promise<void> {
  const db = await openFieldDb();
  await db.put("polygon_draft", {
    key: "current",
    points,
    saved_at: Date.now(),
  });
}

export async function loadPolygonDraft(): Promise<[number, number][] | null> {
  const db = await openFieldDb();
  const row = await db.get("polygon_draft", "current");
  return row?.points ?? null;
}

export async function clearPolygonDraft(): Promise<void> {
  const db = await openFieldDb();
  await db.delete("polygon_draft", "current");
}

export async function getMeta<T>(key: string): Promise<T | undefined> {
  const db = await openFieldDb();
  const row = await db.get("meta", key);
  return row?.value as T | undefined;
}

export async function setMeta(key: string, value: unknown): Promise<void> {
  const db = await openFieldDb();
  await db.put("meta", { key, value });
}

export async function countPendingOps(): Promise<number> {
  const db = await openFieldDb();
  const all = await db.getAll("op_queue");
  return all.filter((o) => o.status === "pending" || o.status === "failed" || o.status === "syncing").length;
}
