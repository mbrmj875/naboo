import { assertEquals, assertStringIncludes } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  templateStatusEmailCopy,
  waDropEmailCopy,
  waLinkEmailCopy,
  welcomeEmailCopy,
} from './owner_email_copy.ts';

Deno.test('ترحيب البريد يذكر PIN ولا يذكر كلمة السر', () => {
  const card = welcomeEmailCopy({ channel: 'email', displayName: 'أحمد', recreated: false });
  assertEquals(card.subject, 'أهلاً بك في نابو');
  assertStringIncludes(card.text, 'تم فتح حسابك');
  assertStringIncludes(card.text, 'رمز PIN');
  assertStringIncludes(card.text, '15 يوماً');
  assertEquals(card.text.includes('كلمة السر'), false);
  assertStringIncludes(card.html, '#0b1f4a');
  assertStringIncludes(card.html, 'dir="rtl"');
});

Deno.test('ترحيب Google لا يذكر البريد وكلمة السر', () => {
  const card = welcomeEmailCopy({ channel: 'google', displayName: '', recreated: false });
  assertEquals(card.subject, 'أهلاً بك في نابو');
  assertStringIncludes(card.text, 'زر Google');
  assertEquals(card.text.includes('مرحباً'), false);
  assertEquals(card.text.includes('كلمة السر'), false);
});

Deno.test('إعادة الإنشاء مع تجربة سابقة لا تعد بـ 15 يوماً', () => {
  const card = welcomeEmailCopy({
    channel: 'email',
    displayName: 'ليلى',
    recreated: true,
    previousTrialStartedAt: '2026-01-01T00:00:00Z',
  });
  assertEquals(card.subject, 'تم إنشاء حسابك من جديد — نابو');
  assertStringIncludes(card.text, 'مدة التجربة تبقى كما كانت');
  assertEquals(card.text.includes('15'), false);
  assertStringIncludes(card.text, 'ادخل بالبريد ورمز PIN');
  assertEquals(card.text.includes('Google'), false);
});

Deno.test('فشل إنشاء القالب لا يقول قيد المراجعة', () => {
  const card = templateStatusEmailCopy({
    kind: 'submit_failed',
    templateKey: 'oil_change_followup',
    templateName: 'oil_fu_a66b5bad',
    language: 'ar',
  });
  assertStringIncludes(card.subject, 'تعذّر إرسال قالب تذكير غيار الزيت');
  assertStringIncludes(card.text, 'لم يصل');
  assertEquals(card.text.includes('قيد المراجعة'), false);
  assertStringIncludes(card.html, 'dir="ltr"');
});

Deno.test('موافقة التذكير تختلف عن موافقة البطاقة', () => {
  const follow = templateStatusEmailCopy({
    kind: 'approved',
    templateKey: 'oil_change_followup',
    templateName: 'oil_fu_x',
    language: 'ar',
  });
  const card = templateStatusEmailCopy({
    kind: 'approved',
    templateKey: 'oil_change_card',
    templateName: 'oil_card_lines_ar',
    language: 'ar_EG',
  });
  assertStringIncludes(follow.subject, 'تذكير غيار الزيت');
  assertStringIncludes(follow.text, 'التذكير يشتغل');
  assertStringIncludes(card.subject, 'بطاقة غيار الزيت');
  assertStringIncludes(card.text, 'بطاقة الغيار');
});

Deno.test('ربط QR يظهر الرقم ولا يخترعه إن غاب', () => {
  const withPhone = waLinkEmailCopy({ method: 'qr', phone: '+9647701234567' });
  assertStringIncludes(withPhone.text, '9647701234567');
  const bare = waLinkEmailCopy({ method: 'dualhook', phone: null });
  assertStringIncludes(bare.text, 'رقم نابو الرسمي');
  assertEquals(bare.text.includes('رقم واتساب:'), false);
});

Deno.test('انقطاع QR الدائم يطلب المسح وMeta لا يطلبه', () => {
  const qr = waDropEmailCopy({ permanent: true, method: 'qr' });
  assertStringIncludes(qr.subject, 'إعادة المسح');
  const meta = waDropEmailCopy({ permanent: true, method: 'cloud_api' });
  assertEquals(meta.text.includes('QR'), false);
  assertStringIncludes(meta.text, 'شاشة واتساب');
});
