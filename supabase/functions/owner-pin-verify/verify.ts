/**
 * منطق التحقق من رمز PIN المالك — بلا شبكة، قابل للاختبار.
 *
 * الصيغة تطابق lib/services/password_hashing.dart حرفياً:
 * - الحديثة: `pbkdf2$<iterations>$<base64url(PBKDF2-HMAC-SHA256(pin.trim(), utf8(salt), 32 bytes))>`
 * - القديمة: hex(SHA-256(utf8("<salt>:<pin.trim()>")))
 */

const enc = new TextEncoder();
const MAX_ITERATIONS = 2_000_000;

export function base64UrlPadded(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_');
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** مقارنة بزمن ثابت لا يكشف موضع الاختلاف. */
export function constantTimeEquals(a: string, b: string): boolean {
  const ba = enc.encode(a);
  const bb = enc.encode(b);
  let diff = ba.length ^ bb.length;
  const n = Math.max(ba.length, bb.length);
  for (let i = 0; i < n; i++) diff |= (ba[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}

export async function pbkdf2(pin: string, salt: string, iterations: number): Promise<string> {
  const key = await crypto.subtle.importKey('raw', enc.encode(pin), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt: enc.encode(salt), iterations },
    key,
    256,
  );
  return base64UrlPadded(new Uint8Array(bits));
}

export async function verifyPinHash(pin: string, salt: string, stored: string): Promise<boolean> {
  const p = pin.trim();
  if (!p || !salt || !stored) return false;
  if (stored.startsWith('pbkdf2$')) {
    const parts = stored.split('$');
    if (parts.length !== 3) return false;
    const iterations = Number.parseInt(parts[1], 10);
    if (!Number.isFinite(iterations) || iterations < 1 || iterations > MAX_ITERATIONS) return false;
    return constantTimeEquals(await pbkdf2(p, salt, iterations), parts[2]);
  }
  const digest = await crypto.subtle.digest('SHA-256', enc.encode(`${salt}:${p}`));
  return constantTimeEquals(hex(new Uint8Array(digest)), stored);
}

export interface PinStore {
  /** يحجز محاولة قبل الحساب. */
  begin(userId: string): Promise<{ allowed: boolean; locked_until: string | null; remaining: number }>;
  success(userId: string): Promise<void>;
  secret(userId: string): Promise<{ phone: string; pin_hash: string; pin_salt: string } | null>;
}

export type VerifyResult =
  | { status: 200; body: { ok: true; phone: string } }
  | { status: 200; body: { ok: false; reason: 'wrong_pin'; remaining: number; locked_until: string | null } }
  | { status: 200; body: { ok: false; reason: 'no_secret' } }
  | { status: 400; body: { ok: false; reason: 'bad_pin' } }
  | { status: 429; body: { ok: false; reason: 'locked'; locked_until: string | null } };

export async function verifyOwnerPin(store: PinStore, userId: string, pin: unknown): Promise<VerifyResult> {
  const p = typeof pin === 'string' ? pin.trim() : '';
  if (!/^\d{4,8}$/.test(p)) return { status: 400, body: { ok: false, reason: 'bad_pin' } };

  const secret = await store.secret(userId);
  if (!secret || !secret.pin_hash || !secret.pin_salt) {
    return { status: 200, body: { ok: false, reason: 'no_secret' } };
  }

  const gate = await store.begin(userId);
  if (!gate.allowed) {
    return { status: 429, body: { ok: false, reason: 'locked', locked_until: gate.locked_until } };
  }

  if (await verifyPinHash(p, secret.pin_salt, secret.pin_hash)) {
    await store.success(userId);
    return { status: 200, body: { ok: true, phone: secret.phone ?? '' } };
  }
  return {
    status: 200,
    body: { ok: false, reason: 'wrong_pin', remaining: gate.remaining, locked_until: gate.locked_until },
  };
}
