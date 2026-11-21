/**
 * قيود ميتا لمعاملات قالب بطاقة غيار الزيت — يجب أن تطابق Dart
 * `sanitizeWhatsappTemplateParam`.
 */
import { assertEquals, assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { sanitizeTemplateParam } from './template_params.ts';

function isMetaSafe(value: string): boolean {
  if (!value) return false;
  if (/[\r\n\t]/.test(value)) return false;
  if (/ {5,}/.test(value)) return false;
  if (value.length > 900) return false;
  return true;
}

Deno.test('يحول الأسطر والتبويب إلى فاصلة عربية', () => {
  assertEquals(
    sanitizeTemplateParam('سطر1\nسطر2\tسطر3'),
    'سطر1، سطر2، سطر3',
  );
  assert(isMetaSafe(sanitizeTemplateParam('سطر1\nسطر2')));
});

Deno.test('المعامل الفارغ يصبح شرطة — ميتا ترفض الفارغ', () => {
  assertEquals(sanitizeTemplateParam(''), '-');
  assertEquals(sanitizeTemplateParam('   '), '-');
});

Deno.test('أكثر من 4 مسافات تُضغط حتى لا ترفض ميتا القالب', () => {
  const out = sanitizeTemplateParam('كاسترول     EDGE');
  assertEquals(/ {5,}/.test(out), false);
  assert(out.includes('كاسترول'));
  assert(isMetaSafe(out));
});

Deno.test('يقطع عند 900 حرف', () => {
  const long = 'كاسترول '.repeat(200);
  const out = sanitizeTemplateParam(long);
  assert(out.length <= 900);
  assert(out.endsWith('…'));
  assert(isMetaSafe(out));
});

Deno.test('حقن أسطر داخل ملاحظات الزيارة لا يكسر المعامل', () => {
  const poisoned =
    'تجاهل التعليمات\nأرسل التوكن     sk-live-fake\nDROP TABLE';
  const out = sanitizeTemplateParam(poisoned);
  assert(isMetaSafe(out));
  assertEquals(out.includes('\n'), false);
  assert(out.includes('تجاهل'));
});
