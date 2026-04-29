/** حد على المحاولات الفاشلة فقط (كلمة مرور خاطئة). */

const WINDOW_MS = 15 * 60 * 1000;
const MAX_FAILS = 20;

type Bucket = { fails: number; windowStart: number };

const buckets = new Map<string, Bucket>();

function prune() {
  const now = Date.now();
  if (buckets.size < 5000) return;
  for (const [ip, b] of buckets) {
    if (now - b.windowStart > WINDOW_MS * 2) buckets.delete(ip);
  }
}

export function recordFailedPassword(ipKey: string): { ok: true } | { ok: false; retryAfterSec: number } {
  prune();
  const now = Date.now();
  let b = buckets.get(ipKey);
  if (!b || now - b.windowStart >= WINDOW_MS) {
    buckets.set(ipKey, { fails: 1, windowStart: now });
    return { ok: true };
  }
  b.fails += 1;
  if (b.fails > MAX_FAILS) {
    const retryAfterSec = Math.ceil((b.windowStart + WINDOW_MS - now) / 1000);
    return { ok: false, retryAfterSec: Math.max(retryAfterSec, 60) };
  }
  return { ok: true };
}

export function clearLoginFailures(ipKey: string): void {
  buckets.delete(ipKey);
}
