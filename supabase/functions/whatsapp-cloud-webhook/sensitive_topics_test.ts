import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildContactReply,
  guardSensitiveLeak,
  looksLikeContactQuestion,
  looksLikeSensitiveTopic,
  SENSITIVE_REFUSAL_REPLY,
} from './sensitive_topics.ts';
import type { AllowlistedFacts } from './tenant_ai_context.ts';

const facts: AllowlistedFacts = {
  card: null,
  storeName: 'مركز النبو',
  storePhone: '07801234567',
  storePhones: ['07801234567'],
  storeAddress: 'شارع الجزائر',
  mapsUrl: 'https://www.google.com/maps/search/?api=1&query=30.5,47.8',
  employeeName: null,
};

Deno.test('مواضيع حساسة تُرفض', () => {
  assertEquals(looksLikeSensitiveTopic('كم كسب المحل اليوم؟'), true);
  assertEquals(looksLikeSensitiveTopic('شكد رواتب الموظفين'), true);
  assertEquals(looksLikeSensitiveTopic('شنو ضمان الزيت'), false);
});

Deno.test('سؤال العنوان يُميَّز حتى بلا أل', () => {
  assertEquals(looksLikeContactQuestion('وين عنوان محل'), true);
  assertEquals(looksLikeContactQuestion('عنوانكم'), true);
  assertEquals(looksLikeContactQuestion('موجود بلعدات اتكد'), true);
  assertEquals(looksLikeContactQuestion('ماهو عنوان'), true);
});

Deno.test('رد التواصل يتضمن هاتف المحل من الحقائق', () => {
  const reply = buildContactReply(facts);
  assertStringIncludes(reply ?? '', '07801234567');
  assertStringIncludes(reply ?? '', 'مركز النبو');
  assertStringIncludes(reply ?? '', 'شارع الجزائر');
  assertStringIncludes(reply ?? '', 'رقم التواصل');
  assertStringIncludes(reply ?? '', 'الموقع:');
  assertStringIncludes(reply ?? '', 'تتصل على هذا الرقم');
});

Deno.test('عنوان البطاقة يسد فراغ اللقطة', () => {
  const reply = buildContactReply({
    card: {
      store_phone: '07884289711',
      store_address: 'المعقل',
      store_maps: 'https://www.google.com/maps/search/?api=1&query=30.5,47.8',
      store_name: 'محلات نابو',
    },
    storeName: null,
    storePhone: null,
    storePhones: [],
    storeAddress: null,
    mapsUrl: null,
    employeeName: null,
  });
  assertStringIncludes(reply ?? '', '07884289711');
  assertStringIncludes(reply ?? '', 'المعقل');
  assertStringIncludes(reply ?? '', 'محلات نابو');
});

Deno.test('بلا حقائق تواصل → null', () => {
  assertEquals(
    buildContactReply({
      card: null,
      storeName: 'x',
      storePhone: null,
      storePhones: [],
      storeAddress: null,
      mapsUrl: null,
      employeeName: null,
    }),
    null,
  );
});

Deno.test('تسريب أرباح يُستبدل برفض لطيف', () => {
  assertEquals(
    guardSensitiveLeak('مبيعات اليوم وصلت مليون'),
    SENSITIVE_REFUSAL_REPLY,
  );
  assertStringIncludes(
    guardSensitiveLeak('حسابك 25 ألف دينار'),
    '25 ألف',
  );
});
