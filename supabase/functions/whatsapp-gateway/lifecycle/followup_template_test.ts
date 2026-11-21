import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  compileFollowupMeta,
  DEFAULT_FOLLOWUP_BODY_AR,
  followupNeedsSubmit,
} from './followup_template.ts';

Deno.test('لا يُرسل قالب معتمد أو قيد المراجعة مرة أخرى', () => {
  assertEquals(followupNeedsSubmit('approved'), false);
  assertEquals(followupNeedsSubmit('pending'), false);
});

Deno.test('يُرسل إذا لم يوجد أو رُفض أو أوقفته Meta', () => {
  for (const s of [null, undefined, 'none', 'rejected', 'disabled']) {
    assertEquals(followupNeedsSubmit(s), true, String(s));
  }
});

Deno.test('النص الافتراضي يصل Meta بخمسة متغيرات مرقمة', () => {
  const c = compileFollowupMeta(DEFAULT_FOLLOWUP_BODY_AR);
  assertEquals(c.paramKeys, ['customer', 'shop', 'car', 'odo_current', 'odo_next']);
  assertEquals(c.examples.length, 5);
  assertEquals(c.body.includes('{{5}}'), true);
  assertEquals(/\{[^{}]+\}(?!\})/.test(c.body.replace(/\{\{\d\}\}/g, '')), false);
});
