"use client";

import {
  listPendingOps,
  updateQueuedOp,
  putVisitCache,
  putTerritoryCache,
  type QueuedOp,
} from "@/lib/field-offline";
import { fieldNetwork, fetchWithTimeout } from "@/lib/field-network";

let syncing = false;
let started = false;

function backoffMs(attempts: number): number {
  return Math.min(5 * 60_000, 2000 * 2 ** Math.min(attempts, 8));
}

async function pushOne(op: QueuedOp): Promise<"ok" | "auth" | "retry" | "conflict"> {
  if (op.id == null) return "retry";
  await updateQueuedOp(op.id, { status: "syncing" });

  const url =
    op.op === "create_visit" || op.op === "update_visit"
      ? "/api/field/visits"
      : "/api/field/territories";
  const method = op.op.startsWith("create") ? "POST" : "PATCH";

  const body = {
    ...op.payload,
    client_op_id: op.client_op_id,
    operation_hash: op.operation_hash,
    op: op.op,
    client_updated_at: op.client_updated_at,
  };

  try {
    const res = await fetchWithTimeout(
      url,
      {
        method,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      },
      3000,
    );

    if (res.status === 401) {
      const data = (await res.json().catch(() => ({}))) as {
        code?: string;
      };
      if (data.code === "SESSION_INVALIDATED") {
        await updateQueuedOp(op.id, {
          status: "pending",
          last_error: "SESSION_INVALIDATED",
        });
        return "auth";
      }
      await updateQueuedOp(op.id, {
        status: "failed",
        attempts: op.attempts + 1,
        next_retry_at: Date.now() + backoffMs(op.attempts + 1),
        last_error: "UNAUTHORIZED",
      });
      return "retry";
    }

    if (res.status === 409) {
      await updateQueuedOp(op.id, {
        status: "failed",
        attempts: op.attempts + 1,
        next_retry_at: Date.now() + backoffMs(op.attempts + 1),
        last_error: "VERSION_CONFLICT",
      });
      return "conflict";
    }

    if (!res.ok) {
      const data = (await res.json().catch(() => ({}))) as {
        error?: string;
        code?: string;
      };
      await updateQueuedOp(op.id, {
        status: "failed",
        attempts: op.attempts + 1,
        next_retry_at: Date.now() + backoffMs(op.attempts + 1),
        last_error: data.code ?? data.error ?? `HTTP_${res.status}`,
      });
      return "retry";
    }

    const data = (await res.json()) as {
      status: string;
      result?: { visit_id?: string; territory_id?: string };
    };

    const serverId =
      data.result?.visit_id ?? data.result?.territory_id ?? op.visit_id ?? null;

    await updateQueuedOp(op.id, {
      status: "synced",
      synced_at: Date.now(),
      last_error: null,
      visit_id: data.result?.visit_id ?? op.visit_id,
      territory_id: data.result?.territory_id ?? op.territory_id,
    });

    if (op.op.includes("visit") && serverId) {
      await putVisitCache({
        id: serverId,
        local_key: serverId,
        shop_name: String(op.payload.shop_name ?? ""),
        owner_name: String(op.payload.owner_name ?? ""),
        phone: (op.payload.phone as string | null) ?? null,
        lat: Number(op.payload.lat),
        lng: Number(op.payload.lng),
        interest: String(op.payload.interest ?? "warm"),
        notes: (op.payload.notes as string | null) ?? null,
        visited_at: op.client_updated_at,
        sync_status: "synced",
        location_source: String(op.payload.location_source ?? "gps"),
      });
    }

    if (op.op.includes("territory") && serverId) {
      await putTerritoryCache({
        id: serverId,
        local_key: serverId,
        name: String(op.payload.name ?? ""),
        geom_geojson: op.payload.geom_geojson,
        status: String(op.payload.status ?? "active"),
        sync_status: "synced",
        claimed_at: op.client_updated_at,
      });
    }

    return "ok";
  } catch {
    await updateQueuedOp(op.id, {
      status: "failed",
      attempts: op.attempts + 1,
      next_retry_at: Date.now() + backoffMs(op.attempts + 1),
      last_error: "NETWORK",
    });
    return "retry";
  }
}

export async function syncQueue(): Promise<{
  synced: number;
  authInvalidated: boolean;
  conflict: boolean;
}> {
  if (syncing) return { synced: 0, authInvalidated: false, conflict: false };
  syncing = true;
  let synced = 0;
  let authInvalidated = false;
  let conflict = false;
  try {
    const reachable = await fieldNetwork.checkConnectivity();
    if (!reachable) return { synced: 0, authInvalidated: false, conflict: false };

    const ops = await listPendingOps();
    for (const op of ops) {
      const r = await pushOne(op);
      if (r === "ok") synced += 1;
      if (r === "auth") {
        authInvalidated = true;
        break;
      }
      if (r === "conflict") conflict = true;
    }
  } finally {
    syncing = false;
  }
  return { synced, authInvalidated, conflict };
}

export function startFieldSyncEngine(opts?: {
  onAuthInvalidated?: () => void;
  onConflict?: () => void;
}): () => void {
  if (started || typeof window === "undefined") return () => {};
  started = true;
  fieldNetwork.start();

  const run = async () => {
    const r = await syncQueue();
    if (r.authInvalidated) opts?.onAuthInvalidated?.();
    if (r.conflict) opts?.onConflict?.();
  };

  const unsub = fieldNetwork.onChange((online) => {
    if (online) void run();
  });

  const interval = setInterval(() => void run(), 12_000);
  void run();

  return () => {
    started = false;
    unsub();
    clearInterval(interval);
    fieldNetwork.stop();
  };
}
