import type { LicenseRow, UserRow } from "./dashboard-data";

function normalizePhone(value: string): string {
  return value.replace(/\s+/g, "");
}

/** نفس منطق بحث صفحة الحسابات — بريد/هاتف/اسم/جزء مفتاح. */
export function matchesAccountSearch(
  user: UserRow,
  license: LicenseRow | null,
  rawQuery: string,
): boolean {
  const q = rawQuery.trim().toLowerCase();
  if (!q) return true;

  const phoneNorm = normalizePhone((user.phone ?? "").toLowerCase());
  const qPhone = normalizePhone(q);

  const hay = [
    user.email ?? "",
    user.display_name ?? "",
    user.phone ?? "",
    license?.license_key ?? "",
  ]
    .join(" ")
    .toLowerCase();

  if (hay.includes(q)) return true;
  if (qPhone && phoneNorm.includes(qPhone)) return true;
  return false;
}
