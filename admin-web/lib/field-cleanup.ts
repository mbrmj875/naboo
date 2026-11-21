"use client";

import { openFieldDb, listVisitCache } from "@/lib/field-offline";

const CACHE_DAYS = 60;
const SYNCED_QUEUE_KEEP_MS = 7 * 24 * 60 * 60 * 1000;

export async function cleanupOldRecords(): Promise<void> {
  const db = await openFieldDb();
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - CACHE_DAYS);
  const cutoffIso = cutoff.toISOString();

  const visits = await listVisitCache();
  const tx = db.transaction(
    ["visits_cache", "op_queue", "territories_cache"],
    "readwrite",
  );

  for (const v of visits) {
    if (v.visited_at < cutoffIso && v.sync_status === "synced") {
      await tx.objectStore("visits_cache").delete(v.local_key);
    }
  }

  const queue = await tx.objectStore("op_queue").getAll();
  const now = Date.now();
  for (const op of queue) {
    if (
      op.status === "synced" &&
      op.synced_at &&
      now - op.synced_at > SYNCED_QUEUE_KEEP_MS
    ) {
      if (op.id != null) await tx.objectStore("op_queue").delete(op.id);
    }
  }

  const territories = await tx.objectStore("territories_cache").getAll();
  for (const t of territories) {
    if (t.status !== "active" && t.sync_status === "synced") {
      await tx.objectStore("territories_cache").delete(t.local_key);
    }
  }

  await tx.done;
}

/** مرة يومياً */
export async function maybeDailyCleanup(): Promise<void> {
  const { getMeta, setMeta } = await import("@/lib/field-offline");
  const key = "last_cleanup_day";
  const today = new Date().toISOString().slice(0, 10);
  const last = await getMeta<string>(key);
  if (last === today) return;
  await cleanupOldRecords();
  await setMeta(key, today);
}
