import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  CONNECT_TEST_DAILY_LIMIT,
  connectTestAllowed,
  connectTestKey,
  connectTestKeyPrefix,
} from './connect_test.ts';

Deno.test('حد رسائل التجربة اليومي', () => {
  assertEquals(connectTestAllowed(0), true);
  assertEquals(connectTestAllowed(CONNECT_TEST_DAILY_LIMIT - 1), true);
  assertEquals(connectTestAllowed(CONNECT_TEST_DAILY_LIMIT), false);
});

Deno.test('مفتاح التجربة يبدأ ببادئة المتجر نفسه فقط', () => {
  assertEquals(connectTestKey('a', 5).startsWith(connectTestKeyPrefix('a')), true);
  assertEquals(connectTestKey('a', 5).startsWith(connectTestKeyPrefix('b')), false);
});
