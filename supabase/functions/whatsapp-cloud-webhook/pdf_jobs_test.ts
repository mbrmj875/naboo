import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  defaultPdfStoragePath,
  idleAfterIso,
  OIL_CARD_PDF_IDLE_MS,
} from './pdf_jobs.ts';

Deno.test('مهلة PDF خمس دقائق من الآن', () => {
  const from = Date.parse('2026-08-17T05:00:00.000Z');
  const got = Date.parse(idleAfterIso(from));
  assertEquals(got - from, OIL_CARD_PDF_IDLE_MS);
});

Deno.test('مسار التخزين معزول بالمستأجر', () => {
  assertEquals(
    defaultPdfStoragePath('a66b5bad-953e-48d7-9aef-6bbe1f7f172d', '42'),
    'a66b5bad-953e-48d7-9aef-6bbe1f7f172d/42.pdf',
  );
});
