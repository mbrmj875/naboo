import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { classifyDeliveryAlerts, type DeliveryLogRow } from './delivery_alerts.ts';

const NOW = Date.parse('2026-11-07T12:00:00Z');
const minsAgo = (m: number) => new Date(NOW - m * 60_000).toISOString();

function row(p: Partial<DeliveryLogRow>): DeliveryLogRow {
  return {
    tenant_user_id: 't',
    status: 'failed',
    error: JSON.stringify({ code: '131026' }),
    provider_message_id: null,
    order_ref: null,
    created_at: minsAgo(5),
    ...p,
  };
}
const rules = (rows: DeliveryLogRow[]) =>
  classifyDeliveryAlerts(rows, NOW).map((c) => c.patternKey);

Deno.test('ثلاثة أخطاء بالرمز نفسه خلال ساعة تنبّه', () => {
  assertEquals(rules([row({}), row({}), row({})]), ['delivery_code_131026']);
});

Deno.test('خطآن أو رموز مختلفة أو خطأ قديم لا تنبّه', () => {
  assertEquals(rules([row({}), row({})]), []);
  assertEquals(rules([
    row({}),
    row({}),
    row({ error: JSON.stringify({ code: '190' }) }),
  ]), []);
  assertEquals(rules([row({}), row({}), row({ created_at: minsAgo(61) })]), []);
});

Deno.test('مُرسلة بلا معرّف تنبّه', () => {
  assertEquals(rules([row({ status: 'sent', error: null })]), ['delivery_sent_no_id']);
});

Deno.test('أصل إعادة الإرسال لا ينبّه لأن المعرّف في سجله الجديد', () => {
  assertEquals(rules([
    row({ status: 'sent', error: null, order_ref: '9' }),
    row({ status: 'sent', error: null, order_ref: '9', provider_message_id: 'wamid.x' }),
  ]), []);
});

Deno.test('الطابور ينبّه بعد 15 دقيقة فقط، والعالق القديم لا يعود', () => {
  assertEquals(rules([row({ status: 'queued', created_at: minsAgo(10) })]), []);
  assertEquals(rules([row({ status: 'queued', created_at: minsAgo(16) })]), ['delivery_stuck_queued']);
  assertEquals(rules([row({ status: 'queued', created_at: minsAgo(60 * 24 * 20) })]), []);
});
