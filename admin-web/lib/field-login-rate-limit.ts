/** حد على المحاولات الفاشلة لدخول المندوبين (IP + username). */

const WINDOW_MS = 15 * 60 * 1000;
const MAX_FAILS = 10;

type Bucket = { fails: number; windowStart: number };

const buckets = new Map<string, Bucket>();

function prune() {
  const now = Date.now();
  if (buckets.size < 5000) return;
  for (const [key, b] of buckets) {
    if (now - b.windowStart > WINDOW_MS * 2) buckets.delete(key);
  }
}

function record(key: string): { ok: true } | { ok: false; retryAfterSec: number } {
  prune();
  const now = Date.now();
  let b = buckets.get(key);
  if (!b || now - b.windowStart >= WINDOW_MS) {
    buckets.set(key, { fails: 1, windowStart: now });
    return { ok: true };
  }
  b.fails += 1;
  if (b.fails > MAX_FAILS) {
    const retryAfterSec = Math.ceil((b.windowStart + WINDOW_MS - now) / 1000);
    return { ok: false, retryAfterSec: Math.max(retryAfterSec, 60) };
  }
  return { ok: true };
}

export function recordFieldLoginFailure(
  ipKey: string,
  username: string,
): { ok: true } | { ok: false; retryAfterSec: number } {
  const byIp = record(`field:ip:${ipKey}`);
  if (!byIp.ok) return byIp;
  return record(`field:user:${username.toLowerCase()}`);
}

export function clearFieldLoginFailures(ipKey: string, username: string): void {
  buckets.delete(`field:ip:${ipKey}`);
  buckets.delete(`field:user:${username.toLowerCase()}`);
}
