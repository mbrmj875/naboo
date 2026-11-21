/**
 * تحقق توقيع Meta webhook: X-Hub-Signature-256 = sha256=<hex>
 * HMAC-SHA256(rawBody, META_APP_SECRET) بمقارنة ثابتة الزمن.
 */

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) {
    out |= a.charCodeAt(i)! ^ b.charCodeAt(i)!;
  }
  return out === 0;
}

async function hmacSha256Hex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(body),
  );
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/** يستخرج hex من هيدر Meta (مع أو بدون بادئة sha256=). */
export function normalizeMetaSignatureHeader(header: string): string {
  const t = header.trim().toLowerCase();
  if (t.startsWith('sha256=')) return t.slice('sha256='.length).trim();
  return t;
}

export async function verifyMetaHubSignature(
  rawBody: string,
  signatureHeader: string,
  appSecret: string,
): Promise<boolean> {
  const secret = appSecret.trim();
  const provided = normalizeMetaSignatureHeader(signatureHeader);
  if (!secret || !provided || !/^[0-9a-f]+$/.test(provided)) return false;
  const expected = await hmacSha256Hex(secret, rawBody);
  return timingSafeEqualHex(expected, provided);
}

export function readMetaHubSignatureHeader(req: Request): string {
  return (
    req.headers.get('X-Hub-Signature-256') ??
    req.headers.get('x-hub-signature-256') ??
    ''
  ).trim();
}
