"use client";

import { useEffect, useRef, useState } from "react";
import type { Map as LeafletMap, LatLngExpression } from "leaflet";
import { BASRA_CENTER } from "@/lib/field-geo";

export type MapVisitPin = {
  id: string;
  lat: number;
  lng: number;
  interest: string;
  shop_name: string;
  owner_name?: string;
  phone?: string | null;
};

export type MapTerritory = {
  id: string;
  name: string;
  geom_geojson: {
    type: "Polygon";
    coordinates: [number, number][][];
  };
};

const INTEREST_COLOR: Record<string, string> = {
  rejected: "#e35d5d",
  warm: "#e3923a",
  interested: "#3dba7a",
  purchased: "#3b82f6",
};

type Props = {
  visits: MapVisitPin[];
  territories?: MapTerritory[];
  drawMode?: boolean;
  drawPoints?: [number, number][];
  onMapClick?: (lat: number, lng: number) => void;
  pickMode?: boolean;
  pickLatLng?: { lat: number; lng: number; accuracy?: number | null } | null;
  onPick?: (lat: number, lng: number) => void;
  /** عند النقر على نقطة — لفتح التفاصيل الكاملة */
  onVisitClick?: (visitId: string) => void;
  className?: string;
  /** توسيط الخريطة على نقطة — tick لإعادة التوسيط حتى لو الإحداثيات نفسها */
  centerOn?: { lat: number; lng: number; zoom?: number; tick?: number } | null;
};

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export function BasraMap({
  visits,
  territories = [],
  drawMode = false,
  drawPoints = [],
  onMapClick,
  pickMode = false,
  pickLatLng = null,
  onPick,
  onVisitClick,
  className,
  centerOn = null,
}: Props) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<LeafletMap | null>(null);
  const layersRef = useRef<{ clear: () => void } | null>(null);
  const onVisitClickRef = useRef(onVisitClick);
  onVisitClickRef.current = onVisitClick;
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const L = (await import("leaflet")).default;
      await import("leaflet/dist/leaflet.css");
      try {
        await import("leaflet.markercluster/dist/MarkerCluster.css");
        await import("leaflet.markercluster/dist/MarkerCluster.Default.css");
        await import("leaflet.markercluster");
      } catch {
        /* cluster optional */
      }

      if (cancelled || !containerRef.current || mapRef.current) return;

      const map = L.map(containerRef.current, {
        zoomControl: false,
        attributionControl: true,
      }).setView(
        [BASRA_CENTER.lat, BASRA_CENTER.lng] as LatLngExpression,
        13,
      );

      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution:
          '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
        subdomains: "abc",
        maxZoom: 19,
      }).addTo(map);

      L.control.zoom({ position: "bottomright" }).addTo(map);

      map.on("click", (e) => {
        if (drawMode || pickMode) {
          onMapClick?.(e.latlng.lat, e.latlng.lng);
          onPick?.(e.latlng.lat, e.latlng.lng);
        }
      });

      mapRef.current = map;
      setReady(true);
      setTimeout(() => map.invalidateSize(), 80);
    })();

    return () => {
      cancelled = true;
      mapRef.current?.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready || !centerOn) return;
    map.setView([centerOn.lat, centerOn.lng], centerOn.zoom ?? 16, {
      animate: true,
    });
    setTimeout(() => map.invalidateSize(), 50);
  }, [
    centerOn?.lat,
    centerOn?.lng,
    centerOn?.zoom,
    centerOn?.tick,
    ready,
  ]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !ready) return;
    let cancelled = false;

    (async () => {
      const L = (await import("leaflet")).default;
      if (cancelled) return;

      layersRef.current?.clear();
      const group = L.layerGroup().addTo(map);

      for (const t of territories) {
        const rings = t.geom_geojson?.coordinates?.[0];
        if (!rings?.length) continue;
        const latlngs = rings.map(
          ([lng, lat]) => [lat, lng] as [number, number],
        );
        L.polygon(latlngs, {
          color: "#c9a227",
          weight: 2,
          fillOpacity: 0.15,
        })
          .bindTooltip(t.name)
          .addTo(group);
      }

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const ClusterGroup = (L as any).markerClusterGroup;
      const markerLayer = ClusterGroup
        ? ClusterGroup({ maxClusterRadius: 48, showCoverageOnHover: false })
        : L.layerGroup();

      for (const v of visits) {
        const color = INTEREST_COLOR[v.interest] ?? "#8aa0b8";
        const icon = L.divIcon({
          className: "",
          html: `<div class="field-marker-icon" style="background:${color}"></div>`,
          iconSize: [16, 16],
          iconAnchor: [8, 8],
        });
        const phoneLine = v.phone
          ? `<div style="direction:ltr;margin-top:2px">${escapeHtml(v.phone)}</div>`
          : "";
        const ownerLine = v.owner_name
          ? `<div style="opacity:.85;margin-top:2px">${escapeHtml(v.owner_name)}</div>`
          : "";
        const popupHtml = `
          <div style="min-width:140px;font-family:Tajawal,sans-serif;text-align:right;direction:rtl">
            <strong>${escapeHtml(v.shop_name)}</strong>
            ${ownerLine}
            ${phoneLine}
            <div style="margin-top:6px;font-size:12px;color:#c9a227">اضغط للتفاصيل</div>
          </div>`;
        const marker = L.marker([v.lat, v.lng], { icon })
          .bindPopup(popupHtml, { closeButton: true, maxWidth: 220 })
          .addTo(markerLayer);
        marker.on("click", () => {
          onVisitClickRef.current?.(v.id);
        });
      }
      markerLayer.addTo(group);

      if (drawPoints.length >= 1) {
        const latlngs = drawPoints.map(
          ([lat, lng]) => [lat, lng] as [number, number],
        );
        L.polyline(latlngs, { color: "#c9a227", weight: 3 }).addTo(group);
        for (const [lat, lng] of drawPoints) {
          L.circleMarker([lat, lng], {
            radius: 5,
            color: "#c9a227",
            fillColor: "#c9a227",
            fillOpacity: 1,
          }).addTo(group);
        }
        if (drawPoints.length >= 3) {
          L.polygon(latlngs, {
            color: "#c9a227",
            weight: 2,
            fillOpacity: 0.2,
            dashArray: "4 4",
          }).addTo(group);
        }
      }

      if (pickLatLng) {
        const pinIcon = L.divIcon({
          className: "field-pick-pin-wrap",
          html: `<div class="field-pick-pin" aria-hidden="true"></div>`,
          iconSize: [28, 28],
          iconAnchor: [14, 28],
        });
        L.marker([pickLatLng.lat, pickLatLng.lng], {
          icon: pinIcon,
          zIndexOffset: 1000,
        }).addTo(group);
        if (typeof (pickLatLng as { accuracy?: number }).accuracy === "number") {
          const acc = (pickLatLng as { accuracy?: number }).accuracy!;
          if (acc > 0 && acc < 500) {
            L.circle([pickLatLng.lat, pickLatLng.lng], {
              radius: acc,
              color: "#2563eb",
              weight: 1,
              fillColor: "#2563eb",
              fillOpacity: 0.12,
            }).addTo(group);
          }
        }
      }

      layersRef.current = {
        clear: () => {
          group.clearLayers();
          map.removeLayer(group);
        },
      };
    })();

    return () => {
      cancelled = true;
    };
  }, [visits, territories, drawPoints, pickLatLng, ready]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    map.off("click");
    map.on("click", (e) => {
      if (drawMode) onMapClick?.(e.latlng.lat, e.latlng.lng);
      if (pickMode) onPick?.(e.latlng.lat, e.latlng.lng);
    });
  }, [drawMode, pickMode, onMapClick, onPick]);

  return (
    <div
      ref={containerRef}
      className={className}
      role="application"
      aria-label="خريطة البصرة"
      style={{ width: "100%", height: "100%", minHeight: "inherit" }}
    />
  );
}
