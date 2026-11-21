"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { FieldShell } from "@/components/field/field-shell";
import { countPendingOps } from "@/lib/field-offline";
import { syncQueue } from "@/lib/field-sync";

export default function AccountPage() {
  const router = useRouter();
  const [name, setName] = useState("…");
  const [pending, setPending] = useState(0);
  const [syncing, setSyncing] = useState(false);

  useEffect(() => {
    void fetch("/api/field/me")
      .then((r) => r.json())
      .then((data) => {
        setName(data.rep?.display_name ?? data.rep?.username ?? "مندوب");
      })
      .catch(() => setName("مندوب"));
    void countPendingOps().then(setPending);
  }, []);

  const logout = async () => {
    await fetch("/api/field/logout", { method: "POST" });
    router.replace("/field/login");
  };

  return (
    <FieldShell title="حسابي">
      <div className="field-panel">
        <div className="field-card">
          <div className="field-label">المندوب</div>
          <strong style={{ fontSize: "1.2rem" }}>{name}</strong>
        </div>
        <div className="field-card">
          <div style={{ marginBottom: 12 }}>
            عمليات بانتظار المزامنة: <strong>{pending}</strong>
          </div>
          <button
            type="button"
            className="field-btn primary block"
            disabled={syncing}
            onClick={() => {
              setSyncing(true);
              void syncQueue()
                .then(() => countPendingOps().then(setPending))
                .finally(() => setSyncing(false));
            }}
          >
            {syncing ? "جاري المزامنة…" : "مزامنة الآن"}
          </button>
        </div>
        <button
          type="button"
          className="field-btn danger block"
          onClick={() => void logout()}
        >
          تسجيل الخروج
        </button>
      </div>
    </FieldShell>
  );
}
