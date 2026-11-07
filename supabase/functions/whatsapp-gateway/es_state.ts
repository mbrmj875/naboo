/**
 * توقيع state لصفحة Embedded Signup — يمنع إكمال الربط لمستأجر آخر.
 * السر: META_APP_SECRET (أو META_ES_STATE_SECRET إن وُجد).
 */

function stateSecret(): string | null {
  return Deno.env.get('META_ES_STATE_SECRET')?.trim() ||
    Deno.env.get('META_APP_SECRET')?.trim() ||
    null;
}

function b64url(bytes: Uint8Array): string {
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function b64urlFromText(text: string): string {
  return b64url(new TextEncoder().encode(text));
}

function fromB64url(s: string): string {
  const pad = s.length % 4 === 0 ? '' : '='.repeat(4 - (s.length % 4));
  const b64 = s.replace(/-/g, '+').replace(/_/g, '/') + pad;
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new TextDecoder().decode(bytes);
}

async function hmacHex(secret: string, message: string): Promise<string> {
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
    new TextEncoder().encode(message),
  );
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

const STATE_TTL_SEC = 45 * 60;

/** يُمرَّر في رابط صفحة ES كـ state= */
export async function signEsState(tenantUserId: string): Promise<string | null> {
  const secret = stateSecret();
  if (!secret) return null;
  const uid = tenantUserId.trim();
  if (!uid.includes('-')) return null;
  const exp = Math.floor(Date.now() / 1000) + STATE_TTL_SEC;
  const nonce = crypto.randomUUID();
  const payload = `${uid}.${exp}.${nonce}`;
  const sig = await hmacHex(secret, payload);
  return `${b64urlFromText(payload)}.${sig}`;
}

export async function verifyEsState(
  state: string,
): Promise<
  | { ok: true; tenantUserId: string; nonce: string | null }
  | { ok: false; detail: string }
> {
  const secret = stateSecret();
  if (!secret) return { ok: false, detail: 'meta_app_secret_missing' };
  const raw = String(state ?? '').trim();
  const dot = raw.lastIndexOf('.');
  if (dot <= 0) return { ok: false, detail: 'state_malformed' };
  const payloadB64 = raw.slice(0, dot);
  const sig = raw.slice(dot + 1);
  let payload: string;
  try {
    payload = fromB64url(payloadB64);
  } catch {
    return { ok: false, detail: 'state_malformed' };
  }
  const expected = await hmacHex(secret, payload);
  if (expected !== sig) return { ok: false, detail: 'state_invalid' };
  const parts = payload.split('.');
  const uid = parts[0];
  const exp = Number(parts[1]);
  const nonce = parts.length >= 3 ? parts[2] : null;
  if (!uid?.includes('-') || !Number.isFinite(exp)) {
    return { ok: false, detail: 'state_malformed' };
  }
  if (nonce !== null && !/^[0-9a-f-]{36}$/i.test(nonce)) {
    return { ok: false, detail: 'state_malformed' };
  }
  if (Math.floor(Date.now() / 1000) > exp) {
    return { ok: false, detail: 'state_expired' };
  }
  return { ok: true, tenantUserId: uid, nonce };
}
