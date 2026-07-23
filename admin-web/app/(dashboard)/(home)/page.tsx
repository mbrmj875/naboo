"use client";

import { OpsHomePanel } from "@/components/ops-home-panel";
import { useDashboardData } from "@/lib/use-dashboard-data";
import { formatDateTimeLatn } from "@/lib/format-ar";

async function logout() {
  await fetch("/api/logout", { method: "POST" });
  window.location.href = "/login";
}

export default function DashboardPage() {
  const { data, loadErr, loading, reload } = useDashboardData();

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>لوحة إدارة NABOO</h1>
          <div className="meta">
            مركز العمليات
            {data?.fetchedAt ? (
              <> · آخر تحديث: {formatDateTimeLatn(data.fetchedAt)}</>
            ) : null}
          </div>
        </div>
        <div style={{ display: "flex", gap: "0.5rem", alignItems: "center" }}>
          <button type="button" className="btn-ghost" onClick={() => void reload()}>
            تحديث
          </button>
          <button type="button" className="btn-ghost" onClick={() => void logout()}>
            خروج
          </button>
        </div>
      </header>

      {loading ? (
        <div className="dash-state" role="status">
          جاري التحميل…
        </div>
      ) : null}

      {!loading && loadErr ? (
        <div className="alert" role="alert">
          <div>{loadErr}</div>
          <button type="button" className="btn-ghost" onClick={() => void reload()}>
            إعادة المحاولة
          </button>
        </div>
      ) : null}

      {!loading && !loadErr && (data?.errors?.length ?? 0) > 0 ? (
        <div className="alert">
          {(data?.errors ?? []).map((e) => (
            <div key={e}>{e}</div>
          ))}
        </div>
      ) : null}

      {!loading && !loadErr ? (
        <OpsHomePanel
          users={data?.users ?? []}
          licenses={data?.licenses ?? []}
        />
      ) : null}
    </div>
  );
}
