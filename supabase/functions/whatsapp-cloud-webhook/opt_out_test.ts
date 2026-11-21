import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { isOptInRequest, isOptOutRequest } from './opt_out.ts';

Deno.test('كلمات الإيقاف بأشكالها', () => {
  for (const t of ['إيقاف', 'ايقاف', ' إيقاف. ', 'STOP', 'إلغاء الاشتراك', 'ايقاف التذكيرات']) {
    assertEquals(isOptOutRequest(t), true, t);
  }
});

Deno.test('الزبون يعيد التذكيرات بنفسه', () => {
  for (const t of ['تفعيل', 'START', 'تفعيل التذكيرات']) {
    assertEquals(isOptInRequest(t), true, t);
  }
  assertEquals(isOptInRequest('تفعيل الحساب عندكم'), false);
});

Deno.test('الجمل العادية لا تعد إيقافًا', () => {
  for (const t of ['', null, 'لا', 'شكرا', 'توقف الدفع عندي', 'متى ايقاف المحل', 'ممتاز 5']) {
    assertEquals(isOptOutRequest(t), false, String(t));
  }
});
