import {
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { looksLikeLastServiceQuestion } from './card_faq.ts';
import {
  classifyInboundIntent,
  looksLikeThanksClose,
} from './inbound_intent.ts';

Deno.test('تقييم رقمي صريح قبل أي شيء', () => {
  assertEquals(classifyInboundIntent('9', 9), 'rating');
  assertEquals(classifyInboundIntent('10/10', 10), 'rating');
});

Deno.test('شكر قصير يغلق بلا مخزون', () => {
  assertEquals(looksLikeThanksClose('شكراً هواي'), true);
  assertEquals(classifyInboundIntent('شكراً هواي', null), 'thanks');
  assertEquals(classifyInboundIntent('تسلم', null), 'thanks');
});

Deno.test('ديفلون بأي صياغة = مخزون لا آخر زيارة', () => {
  assertEquals(classifyInboundIntent('هل يوجد عدكم زيت ديفلون', null), 'inventory');
  assertEquals(classifyInboundIntent('ديفلون متوفر', null), 'inventory');
  assertEquals(classifyInboundIntent('deflon موجود', null), 'inventory');
  assertEquals(looksLikeLastServiceQuestion('هل يوجد عدكم زيت ديفلون'), false);
});

Deno.test('شنو الزيت عندكم قائمة لا آخر غيار', () => {
  assertEquals(classifyInboundIntent('شنو الزيت عندكم', null), 'inventory');
  assertEquals(looksLikeLastServiceQuestion('شنو الزيت عندكم'), false);
  assertEquals(looksLikeLastServiceQuestion('شنو الزيت آخر مرة'), true);
  assertEquals(classifyInboundIntent('شنو الزيت آخر مرة', null), 'last_service');
});

Deno.test('رقم اللزوجة لا يُحسب تقييماً', () => {
  assertEquals(classifyInboundIntent('ديفلون 5W30', 5), 'inventory');
});

Deno.test('طلب ملف بأي صياغة يسبق الرد النصي', () => {
  assertEquals(classifyInboundIntent('ممكن ملف بدف', null), 'pdf_file');
  assertEquals(classifyInboundIntent('ارسل لي PDF', null), 'pdf_file');
  assertEquals(classifyInboundIntent('أبي نسخة الغيار', null), 'pdf_file');
  assertEquals(classifyInboundIntent('شكراً هواي', null), 'thanks');
});

Deno.test('إجمالي الزيارة ليس طلب منتج', () => {
  assertEquals(classifyInboundIntent('شكد صار سعر', null), 'visit_price');
});

Deno.test('سؤال العنوان يسبق المخزون حتى مع أريد', () => {
  assertEquals(classifyInboundIntent('وين عنوان', null), 'contact');
  assertEquals(classifyInboundIntent('اريد عنوان محل', null), 'contact');
  assertEquals(classifyInboundIntent('أريد رقمكم', null), 'contact');
  assertEquals(classifyInboundIntent('اريد زيت ديفلون', null), 'inventory');
});
