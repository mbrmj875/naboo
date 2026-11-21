"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { FieldShell } from "@/components/field/field-shell";
import { FIELD_MESSAGES } from "@/lib/field-messages";
import {
  listVisitCache,
  putVisitCache,
  type CachedVisit,
} from "@/lib/field-offline";

const LABELS: Record<string, string> = {
  rejected: FIELD_MESSAGES.INTEREST_REJECTED,
  warm: FIELD_MESSAGES.INTEREST_WARM,
  interested: FIELD_MESSAGES.INTEREST_INTERESTED,
  purchased: FIELD_MESSAGES.INTEREST_PURCHASED,
};

const FILTERS = [
  { id: "all", label: "الكل" },
  { id: "rejected", label: LABELS.rejected },
  { id: "warm", label: LABELS.warm },
  { id: "interested", label: LABELS.interested },
  { id: "purchased", label: LABELS.purchased },
] as const;

export default function VisitsPage() {
  const [visits, setVisits] = useState<CachedVisit[]>([]);
  const [filter, setFilter] = useState<string>("all");

  useEffect(() => {
    (async () => {
      try {
        const res = await fetch("/api/field/visits");
        if (res.ok) {
          const data = await res.json();
          for (const v of data.visits ?? []) {
            await putVisitCache({
              id: v.id,
              local_key: v.id,
              shop_name: v.shop_name,
              owner_name: v.owner_name,
              phone: v.phone,
              lat: v.lat,
              lng: v.lng,
              interest: v.interest,
              notes: v.notes,
              visited_at: v.visited_at,
              sync_status: "synced",
              location_source: v.location_source,
            });
          }
        }
      } catch {
        /* cache */
      }
      setVisits(await listVisitCache());
    })();
  }, []);

  const filtered =
    filter === "all" ? visits : visits.filter((v) => v.interest === filter);

  return (
    <FieldShell title="زياراتي">
      <div className="field-panel">
        <div className="field-filter-bar">
          <Link href="/field" className="field-btn primary block">
            محل جديد
          </Link>
          <div className="field-filter-row" role="tablist" aria-label="فلتر الحالة">
            {FILTERS.map((f) => (
              <button
                key={f.id}
                type="button"
                role="tab"
                aria-selected={filter === f.id}
                className={`field-filter-chip ${filter === f.id ? `active ${f.id === "all" ? "" : f.id}` : ""}`}
                onClick={() => setFilter(f.id)}
              >
                {f.label}
              </button>
            ))}
          </div>
        </div>

        {filtered.length === 0 ? (
          <div className="field-empty">لا توجد زيارات بعد</div>
        ) : (
          <ul className="field-list">
            {filtered.map((v) => (
              <li key={v.local_key} className="field-list-item">
                <div style={{ display: "flex", gap: 10 }}>
                  <span className={`field-dot ${v.interest}`} />
                  <div>
                    <strong>{v.shop_name}</strong>
                    <div
                      style={{
                        color: "var(--field-muted)",
                        fontSize: "0.88rem",
                        marginTop: 2,
                      }}
                    >
                      {v.owner_name}
                      {v.phone ? ` · ${v.phone}` : ""}
                    </div>
                    <div
                      style={{
                        color: "var(--field-muted)",
                        fontSize: "0.8rem",
                        marginTop: 4,
                      }}
                    >
                      {new Date(v.visited_at).toLocaleString("ar-IQ")}
                    </div>
                  </div>
                </div>
                <div style={{ textAlign: "end", fontSize: "0.82rem" }}>
                  <div style={{ fontWeight: 700 }}>
                    {LABELS[v.interest] ?? v.interest}
                  </div>
                  <div style={{ color: "var(--field-muted)", marginTop: 4 }}>
                    {v.sync_status === "synced"
                      ? FIELD_MESSAGES.SYNC_SYNCED
                      : v.sync_status === "pending"
                        ? FIELD_MESSAGES.SYNC_PENDING
                        : FIELD_MESSAGES.SYNC_FAILED}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>
    </FieldShell>
  );
}
