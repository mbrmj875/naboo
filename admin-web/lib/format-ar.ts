/** عرض عربي مع أرقام غربية (0-9) — مصدر مركزي لكل الواجهة. */
export const AR_LATN = "ar-IQ-u-nu-latn";

const numberOpts: Intl.NumberFormatOptions = {
  numberingSystem: "latn",
};

const dateTimeOpts: Intl.DateTimeFormatOptions = {
  dateStyle: "short",
  timeStyle: "short",
  numberingSystem: "latn",
};

const dateOpts: Intl.DateTimeFormatOptions = {
  dateStyle: "short",
  numberingSystem: "latn",
};

export function formatNumberLatn(n: number): string {
  if (!Number.isFinite(n)) return "—";
  return n.toLocaleString(AR_LATN, numberOpts);
}

export function formatDateTimeLatn(iso: string | null | undefined): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString(AR_LATN, dateTimeOpts);
  } catch {
    return iso;
  }
}

export function formatDateLatn(iso: string | null | undefined): string {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleDateString(AR_LATN, dateOpts);
  } catch {
    return iso;
  }
}
