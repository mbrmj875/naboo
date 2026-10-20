"use client";

import { useCallback, useEffect, useState } from "react";
import type {
  AppRemoteConfigPayload,
  ChunkRow,
  DeviceRow,
  LicenseRow,
  LicenseSummaryRow,
  SnapshotRow,
  UserRow,
} from "./dashboard-data";

/** شكل استجابة GET /api/data — مطابق لما يستهلكه العميل حالياً. */
export type DashboardPayload = {
  users: UserRow[];
  devices: DeviceRow[];
  licenses: LicenseRow[];
  licenseSummary: LicenseSummaryRow;
  snapshots: SnapshotRow[];
  snapshotChunks: ChunkRow[];
  remoteConfig: AppRemoteConfigPayload;
  remoteConfigUpdatedAt: string | null;
  errors: string[];
  fetchedAt: string;
  error?: string;
};

export type UseDashboardDataResult = {
  data: DashboardPayload | null;
  loadErr: string;
  loading: boolean;
  reload: () => Promise<void>;
};

/**
 * جلب مشترك لبيانات لوحة الإدارة.
 * لا يغيّر شكل الاستجابة؛ يعيد نفس الحمولة من /api/data.
 */
export function useDashboardData(): UseDashboardDataResult {
  const [data, setData] = useState<DashboardPayload | null>(null);
  const [loadErr, setLoadErr] = useState("");
  const [loading, setLoading] = useState(true);

  const load = useCallback(async (mode: "initial" | "refresh" = "initial") => {
    setLoadErr("");
    if (mode === "initial") setLoading(true);
    try {
      const res = await fetch("/api/data", { cache: "no-store" });
      const json = (await res.json()) as DashboardPayload;
      if (!res.ok) {
        setLoadErr(json.error ?? "فشل التحميل");
        if (mode === "initial") setData(null);
        return;
      }
      setData(json);
    } catch {
      setLoadErr("تعذر الاتصال بالخادم");
      if (mode === "initial") setData(null);
    } finally {
      if (mode === "initial") setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load("initial");
  }, [load]);

  const reload = useCallback(async () => {
    await load("refresh");
  }, [load]);

  return { data, loadErr, loading, reload };
}
