/** عكس الإحداثيات إلى عنوان مقروء عبر Nominatim (OSM) */

export type ReverseGeocodeResult = {
  displayName: string;
  shortLabel: string;
};

export async function reverseGeocode(
  lat: number,
  lng: number,
  signal?: AbortSignal,
): Promise<ReverseGeocodeResult | null> {
  const url = new URL("https://nominatim.openstreetmap.org/reverse");
  url.searchParams.set("format", "jsonv2");
  url.searchParams.set("lat", String(lat));
  url.searchParams.set("lon", String(lng));
  url.searchParams.set("accept-language", "ar");
  url.searchParams.set("zoom", "18");
  url.searchParams.set("addressdetails", "1");

  const res = await fetch(url.toString(), {
    signal,
    headers: {
      Accept: "application/json",
    },
  });
  if (!res.ok) return null;
  const data = (await res.json()) as {
    display_name?: string;
    address?: Record<string, string>;
  };
  const a = data.address ?? {};
  const parts = [
    a.road,
    a.neighbourhood || a.suburb || a.quarter,
    a.city || a.town || a.village || a.county,
  ].filter(Boolean);
  const shortLabel =
    parts.length > 0 ? parts.join(" · ") : (data.display_name ?? "").split(",")[0] ?? "";
  const displayName = data.display_name?.trim() || shortLabel;
  if (!displayName) return null;
  return { displayName, shortLabel: shortLabel || displayName };
}
