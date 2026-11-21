"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { FieldShell } from "@/components/field/field-shell";
import { BasraMap, type MapVisitPin, type MapTerritory } from "@/components/field/basra-map";
import { newClientOpId } from "@/lib/field-client-id";
import { computeOperationHashClient } from "@/lib/field-hash-client";
import {
  enqueueOp,
  listVisitCache,
  listTerritoryCache,
  putVisitCache,
  putTerritoryCache,
  savePolygonDraft,
  loadPolygonDraft,
  clearPolygonDraft,
  type CachedVisit,
} from "@/lib/field-offline";
import { syncQueue } from "@/lib/field-sync";
import { FIELD_MESSAGES } from "@/lib/field-messages";

export function FieldMapPage() {
  const router = useRouter();
  const [visits, setVisits] = useState<MapVisitPin[]>([]);
  const [territories, setTerritories] = useState<MapTerritory[]>([]);
  const [drawMode, setDrawMode] = useState(false);
  const [points, setPoints] = useState<[number, number][]>([]);
  const [name, setName] = useState("");
  const [msg, setMsg] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const refresh = async () => {
    const [vc, tc] = await Promise.all([listVisitCache(), listTerritoryCache()]);
    setVisits(
      vc.map((v) => ({
        id: v.id,
        lat: v.lat,
        lng: v.lng,
        interest: v.interest,
        shop_name: v.shop_name,
      })),
    );
    setTerritories(
      tc
        .filter((t) => t.status === "active")
        .map((t) => ({
          id: t.id,
          name: t.name,
          geom_geojson: t.geom_geojson as MapTerritory["geom_geojson"],
        })),
    );
  };

  useEffect(() => {
    (async () => {
      try {
        const [vRes, tRes] = await Promise.all([
          fetch("/api/field/visits").then((r) => r.json()),
          fetch("/api/field/territories").then((r) => r.json()),
        ]);
        for (const v of (vRes.visits ?? []) as CachedVisit[]) {
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
            geo_warning: v.geo_warning,
          });
        }
        for (const t of tRes.territories ?? []) {
          await putTerritoryCache({
            id: t.id,
            local_key: t.id,
            name: t.name,
            geom_geojson: t.geom_geojson,
            status: t.status,
            sync_status: "synced",
            claimed_at: t.claimed_at,
          });
        }
      } catch {
        /* offline — use cache */
      }
      const draft = await loadPolygonDraft();
      if (draft?.length) {
        setPoints(draft);
        setDrawMode(true);
      }
      await refresh();
    })();
  }, []);

  const onDrawClick = (lat: number, lng: number) => {
    setPoints((prev) => {
      const next: [number, number][] = [...prev, [lat, lng]];
      void savePolygonDraft(next);
      return next;
    });
  };

  const undoPoint = () => {
    setPoints((prev) => {
      const next = prev.slice(0, -1);
      void savePolygonDraft(next);
      return next;
    });
  };

  const saveTerritory = async () => {
    if (points.length < 3 || !name.trim()) {
      setMsg("أدخل اسماً وارسم 3 نقاط على الأقل");
      return;
    }
    setSaving(true);
    setMsg(null);
    try {
      const ring: [number, number][] = points.map(([lat, lng]) => [lng, lat]);
      const first = ring[0];
      const last = ring[ring.length - 1];
      if (first && last && (first[0] !== last[0] || first[1] !== last[1])) {
        ring.push([first[0], first[1]]);
      }
      const geom_geojson = { type: "Polygon" as const, coordinates: [ring] };
      const client_op_id = newClientOpId();
      const client_updated_at = new Date().toISOString();
      const payload = {
        name: name.trim(),
        geom_geojson,
        status: "active",
      };
      const operation_hash = await computeOperationHashClient(
        "create_territory",
        payload,
        null,
      );
      const localKey = `local-${client_op_id}`;
      await putTerritoryCache({
        id: localKey,
        local_key: localKey,
        name: name.trim(),
        geom_geojson,
        status: "active",
        sync_status: "pending",
        claimed_at: client_updated_at,
      });
      await enqueueOp({
        client_op_id,
        op: "create_territory",
        payload: { ...payload, name: name.trim(), geom_geojson },
        operation_hash,
        client_updated_at,
      });
      await clearPolygonDraft();
      setDrawMode(false);
      setPoints([]);
      setName("");
      setMsg(FIELD_MESSAGES.TERRITORY_SAVED);
      void syncQueue();
      await refresh();
    } finally {
      setSaving(false);
    }
  };

  return (
    <FieldShell title="خريطة البصرة" mapMode>
      <div className="field-map-wrap">
        {drawMode && (
          <div className="field-draw-bar">
            <p>
              اضغط على الخريطة لإضافة رؤوس المضلع. آخر 5 يمكن التراجع عنها. أغلق
              الشكل ثم احفظ.
            </p>
            <input
              className="field-input"
              placeholder="اسم المنطقة (مثل: سوق العشار)"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
            <button type="button" className="field-btn ghost" onClick={undoPoint}>
              تراجع
            </button>
            <button
              type="button"
              className="field-btn danger"
              onClick={() => {
                setDrawMode(false);
                setPoints([]);
                void clearPolygonDraft();
              }}
            >
              إلغاء
            </button>
            <button
              type="button"
              className="field-btn primary"
              disabled={saving}
              onClick={() => void saveTerritory()}
            >
              حفظ المنطقة
            </button>
          </div>
        )}
        <BasraMap
          visits={visits}
          territories={territories}
          drawMode={drawMode}
          drawPoints={points}
          onMapClick={onDrawClick}
        />
        {!drawMode && (
          <div className="field-map-fab">
            <button
              type="button"
              className="field-btn primary"
              onClick={() => router.push("/field/visits/new")}
            >
              زيارة جديدة
            </button>
            <button
              type="button"
              className="field-btn"
              onClick={() => setDrawMode(true)}
            >
              رسم منطقة
            </button>
          </div>
        )}
      </div>
      {msg && <div className="field-panel"><div className="field-alert ok">{msg}</div></div>}
    </FieldShell>
  );
}
