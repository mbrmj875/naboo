import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  allowedCurrentStatusesFor,
  formatWaLogError,
  isRetryableCode,
} from '../whatsapp-gateway/wa_log_error.ts';

Deno.test('formatWaLogError ينتج JSON منظم', () => {
  const raw = formatWaLogError({
    source: 'meta',
    code: '131026',
    title: 'Undeliverable',
    message: 'Message undeliverable',
  });
  const parsed = JSON.parse(raw);
  assertEquals(parsed.source, 'meta');
  assertEquals(parsed.code, '131026');
  assertEquals(parsed.retryable, false);
});

Deno.test('تصنيف retryable للبوابة وميتا', () => {
  assertEquals(isRetryableCode('timeout', 'gateway'), true);
  assertEquals(isRetryableCode('preparing', 'gateway'), true);
  assertEquals(isRetryableCode('invalid_phone', 'gateway'), false);
  assertEquals(isRetryableCode('131026', 'meta'), false);
  assertEquals(isRetryableCode('131042', 'meta'), true);
  assertEquals(isRetryableCode('141006', 'meta'), true);
});

Deno.test('مصفوفة الانتقال الأحادي', () => {
  assertEquals(allowedCurrentStatusesFor('delivered'), ['sent', 'failed']);
  assertEquals(allowedCurrentStatusesFor('read'), ['sent', 'delivered', 'failed']);
  assertEquals(allowedCurrentStatusesFor('failed'), ['sent']);
  assertEquals(allowedCurrentStatusesFor('failed').includes('delivered'), false);
  assertEquals(allowedCurrentStatusesFor('failed').includes('read'), false);
});
