/** رسالة التجربة بعد الربط: مجانية، فحدها اليومي يمنع استخدامها للإرسال. */

export const CONNECT_TEST_DAILY_LIMIT = 3;

export function connectTestKey(tenantUserId: string, nowMs: number): string {
  return `connect_test:${tenantUserId}:${nowMs}`;
}

export function connectTestKeyPrefix(tenantUserId: string): string {
  return `connect_test:${tenantUserId}:`;
}

export function connectTestAllowed(sentInLast24h: number): boolean {
  return sentInLast24h < CONNECT_TEST_DAILY_LIMIT;
}
