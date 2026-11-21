/** مركز البصرة (العشار) — نفس قيمة Flutter الحالية */
export const BASRA_CENTER = { lat: 30.5085, lng: 47.7835 } as const;
export const BASRA_MAX_KM = 15;
export const GPS_WEAK_ACCURACY_M = 50;

/** نطاق محافظة تقريبي لرفض الإحداثيات العشوائية */
export const BASRA_BOUNDS = {
  latMin: 29.5,
  latMax: 31.5,
  lngMin: 46.5,
  lngMax: 48.5,
} as const;

/** مسافة Haversine بالكيلومتر */
export function geoDistanceKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const R = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function distanceFromBasraCenter(lat: number, lng: number): number {
  return geoDistanceKm(lat, lng, BASRA_CENTER.lat, BASRA_CENTER.lng);
}

export function isWithinBasraGovernorate(lat: number, lng: number): boolean {
  return (
    lat >= BASRA_BOUNDS.latMin &&
    lat <= BASRA_BOUNDS.latMax &&
    lng >= BASRA_BOUNDS.lngMin &&
    lng <= BASRA_BOUNDS.lngMax
  );
}

export type GeoCheckResult = {
  ok: boolean;
  code?: "GEO_CONFIRM_REQUIRED" | "OUT_OF_GOVERNORATE";
  distanceKm: number;
  geoWarning: "out_of_basra" | "weak_accuracy" | null;
};

export function checkVisitGeo(input: {
  lat: number;
  lng: number;
  gpsAccuracy?: number | null;
  geoConfirmed?: boolean;
}): GeoCheckResult {
  const distanceKm = distanceFromBasraCenter(input.lat, input.lng);

  if (!isWithinBasraGovernorate(input.lat, input.lng)) {
    return {
      ok: false,
      code: "OUT_OF_GOVERNORATE",
      distanceKm,
      geoWarning: "out_of_basra",
    };
  }

  let geoWarning: GeoCheckResult["geoWarning"] = null;
  if (
    typeof input.gpsAccuracy === "number" &&
    input.gpsAccuracy > GPS_WEAK_ACCURACY_M
  ) {
    geoWarning = "weak_accuracy";
  }

  if (distanceKm > BASRA_MAX_KM) {
    if (!input.geoConfirmed) {
      return {
        ok: false,
        code: "GEO_CONFIRM_REQUIRED",
        distanceKm,
        geoWarning: "out_of_basra",
      };
    }
    geoWarning = "out_of_basra";
  }

  return { ok: true, distanceKm, geoWarning };
}
