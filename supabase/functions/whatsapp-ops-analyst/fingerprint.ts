/** بصمة الحادث — بدون user_id داخل الـ hash. */
export async function incidentFingerprint(parts: {
  ruleId: string;
  sessionName: string;
  patternKey: string;
  severity: string;
}): Promise<string> {
  const material = [
    parts.ruleId.trim(),
    parts.sessionName.trim(),
    parts.patternKey.trim(),
    parts.severity.trim(),
  ].join('|');
  const buf = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(material),
  );
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** بصمة هاتف مبسّطة (آخر 8 أرقام فقط — لا تخزين كامل). */
export function phoneFingerprint(phone: string | null | undefined): string | null {
  const digits = String(phone ?? '').replace(/\D/g, '');
  if (digits.length < 8) return null;
  return `p_${digits.slice(-8)}`;
}
