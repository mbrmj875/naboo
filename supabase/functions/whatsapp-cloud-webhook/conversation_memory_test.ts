import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { summarizeOlderTurns } from './conversation.ts';

Deno.test('ملخص الذاكرة يلتقط الضمان والتواصل', () => {
  const summary = summarizeOlderTurns([
    { role: 'customer', text: 'اكو ضمان؟' },
    { role: 'shop', text: 'اي الضمان 5000 كم' },
    { role: 'customer', text: 'رقمكم؟' },
  ]);
  assertStringIncludes(summary ?? '', 'الضمان');
  assertStringIncludes(summary ?? '', 'التواصل');
});

Deno.test('ملخص فارغ التاريخ يرجع null', () => {
  assertEquals(summarizeOlderTurns([]), null);
});
