import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildCardFacts,
  buildSystemPrompt,
  buildUserPrompt,
  buildWarrantyReply,
  DEFLECTION_REPLY,
  looksLikeWarrantyQuestion,
  parseAiPayload,
  parseOdometerKm,
  sanitizeAiReply,
  warrantyKmFromCard,
} from './ai_reply.ts';
import { looksLikeFeedback } from './conversation.ts';
import type { AllowlistedFacts } from './tenant_ai_context.ts';

Deno.test('يزيل علامات الاقتباس المحيطة', () => {
  assertEquals(
    sanitizeAiReply('"شكراً على ردك، إحنا بالخدمة دائماً"'),
    'شكراً على ردك، إحنا بالخدمة دائماً',
  );
});

Deno.test('يرفض القالب غير المعبّأ والمخرَج غير العربي', () => {
  assertEquals(sanitizeAiReply('شكراً {{name}} على تقييمك الجميل جداً'), null);
  assertEquals(sanitizeAiReply('Thanks for your rating!'), null);
  assertEquals(sanitizeAiReply('   '), null);
});

Deno.test('يفكّ JSON النموذج مع التصنيف', () => {
  const out = parseAiPayload(
    '{"is_feedback": true, "reply": "آسفين على التأخير، راح نتحسّن"}',
  );
  assertEquals(out?.isFeedback, true);
  assertEquals(out?.reply, 'آسفين على التأخير، راح نتحسّن');
});

Deno.test('سطر حقيقي داخل JSON لا يمنع استخراج الرد', () => {
  const out = parseAiPayload(
    '{"is_feedback": true, "reply": "تسلم باقر،\nثناءك يوصل للفني علي"}',
  );
  assertEquals(out?.isFeedback, true);
  assertStringIncludes(out?.reply ?? '', 'ثناءك يوصل للفني علي');
  assertEquals(out?.reply.includes('{'), false);
});

Deno.test('غلاف JSON مكسور لا يُرسل نصاً خاماً للزبون', () => {
  assertEquals(
    parseAiPayload('{"is_feedback": true, "reply": "تسلم باقر ثناءك يوصل'),
    null,
  );
  assertEquals(
    sanitizeAiReply('{"is_feedback": true, "reply": "تسلم باقر يا غالي"}'),
    null,
  );
});

Deno.test('نص خام بلا JSON يُقبل رداً بلا تصنيف', () => {
  const out = parseAiPayload('هلا بيك، الفني اللي خدمك كان كرار');
  assertEquals(out?.isFeedback, false);
  assertStringIncludes(out?.reply ?? '', 'كرار');
});

Deno.test('حقائق البطاقة تتجاهل الحقول الفارغة', () => {
  const facts = buildCardFacts({
    car: 'تويوتا كامري',
    oil_brand: 'كاسترول',
    filters: '-',
    products: '—',
    total: '25,000 د.ع',
    details: 'كتلة نصية لا تُعرض',
  });
  assertEquals(facts, [
    'السيارة: تويوتا كامري',
    'نوع الزيت: كاسترول',
    'إجمالي الحساب: 25,000 د.ع',
  ]);
});

Deno.test('يغلّف رسالة الزبون كبيانات ويضم الحقائق والسياق', () => {
  const prompt = buildUserPrompt({
    score: null,
    message: 'شنو اسم الفني؟',
    employeeName: 'كرار',
    card: { car: 'تويوتا كامري' },
    history: [
      { role: 'customer', text: 'خوش شغل' },
      { role: 'shop', text: 'شكراً على ردك' },
    ],
  });
  assertStringIncludes(prompt, 'اسم الفني اللي خدمه: كرار');
  assertStringIncludes(prompt, 'السيارة: تويوتا كامري');
  assertStringIncludes(prompt, 'الزبون: خوش شغل');
  assertStringIncludes(prompt, 'المحل: شكراً على ردك');
  assertStringIncludes(prompt, '<<<شنو اسم الفني؟>>>');
});

Deno.test('ادعاء العنوان أو الدوام يُستبدل بجواب آمن', () => {
  assertEquals(
    parseAiPayload(
      '{"is_feedback": false, "reply": "دوامنا من الساعة 9 الصبح للعصر"}',
    )?.reply,
    DEFLECTION_REPLY,
  );
  assertEquals(
    parseAiPayload(
      '{"is_feedback": false, "reply": "عنواننا بشارع الصناعة قرب التقاطع"}',
    )?.reply,
    DEFLECTION_REPLY,
  );
});

Deno.test('هاتف وعنوان مؤكدان يُسمح بذكرهما', () => {
  const facts: AllowlistedFacts = {
    card: null,
    storeName: 'مركز النبو',
    storePhone: '07801234567',
    storePhones: ['07801234567'],
    storeAddress: 'شارع الجزائر',
    mapsUrl: null,
    employeeName: null,
  };
  const out = parseAiPayload(
    '{"is_feedback": false, "reply": "تكدر تتواصل على الرقم 07801234567 عنواننا شارع الجزائر"}',
    facts,
  );
  assertStringIncludes(out?.reply ?? '', '07801234567');
  assertStringIncludes(out?.reply ?? '', 'شارع الجزائر');
});

Deno.test('persona في الـ system prompt محترمة ولهجة عراقية', () => {
  const p = buildSystemPrompt();
  assertStringIncludes(p, 'محترم أولاً');
  assertStringIncludes(p, 'لهجة عراقية');
  assertStringIncludes(p, 'رقمكم؟');
});

Deno.test('الـ user prompt يضم حقائق المتجر والذاكرة', () => {
  const prompt = buildUserPrompt({
    score: null,
    message: 'رقمكم؟',
    employeeName: null,
    card: { customer: 'باقر' },
    history: [{ role: 'customer', text: 'شكراً' }],
    memorySummary: 'تم شكره سابقاً',
    allowlisted: {
      card: { customer: 'باقر' },
      storeName: 'مركز النبو',
      storePhone: '07801234567',
      storePhones: ['07801234567'],
      storeAddress: null,
      mapsUrl: null,
      employeeName: null,
    },
  });
  assertStringIncludes(prompt, 'هاتف المحل للتواصل: 07801234567');
  assertStringIncludes(prompt, 'تم شكره سابقاً');
  assertStringIncludes(prompt, '<<<رقمكم؟>>>');
});

Deno.test('جواب الحساب المشروع لا يُحجب', () => {
  const out = parseAiPayload(
    '{"is_feedback": false, "reply": "حسابك 25 ألف دينار ودفعته كامل"}',
  );
  assertStringIncludes(out?.reply ?? '', '25 ألف');
});

Deno.test('السؤال لا يُعد رأياً بالخدمة', () => {
  assertEquals(looksLikeFeedback('شنو اسمى فني اريد اعرف هو اهني'), false);
  assertEquals(looksLikeFeedback('منو الفني؟'), false);
  assertEquals(looksLikeFeedback('شكد صار الحساب'), false);
});

Deno.test('الرأي والشكوى يُعدّان تقييماً', () => {
  assertEquals(looksLikeFeedback('خوش شغل بس ماعجبني أسلوب الفني'), true);
  assertEquals(looksLikeFeedback('الخدمة سريعة والمكان نظيف'), true);
});

Deno.test('قراءة العداد تُستخرج من صيغ متعددة', () => {
  assertEquals(parseOdometerKm('5,000 كم'), 5000);
  assertEquals(parseOdometerKm('10000'), 10000);
  assertEquals(parseOdometerKm('١٠٠٠٠ كم'), 10000);
  assertEquals(parseOdometerKm('-'), null);
  assertEquals(parseOdometerKm(''), null);
});

Deno.test('الضمان = القراءة اللاحقة ناقص الحالية', () => {
  assertEquals(
    warrantyKmFromCard({
      odo_current: '5,000 كم',
      odo_next: '10,000 كم',
    }),
    5000,
  );
  assertEquals(
    warrantyKmFromCard({
      odo_current: '120000',
      odo_next: '125000',
    }),
    5000,
  );
  assertEquals(
    warrantyKmFromCard({ odo_current: '10000', odo_next: '9000' }),
    null,
  );
  assertEquals(warrantyKmFromCard({ odo_current: '5000' }), null);
});

Deno.test('حقائق البطاقة تتضمن الضمان المحسوب', () => {
  const facts = buildCardFacts({
    odo_current: '5,000 كم',
    odo_next: '10,000 كم',
    oil_grade: '0W8',
  });
  assertEquals(
    facts.some((f) => f.includes('ضمان الزيت بالكيلومتر: 5,000 كم')),
    true,
  );
  assertEquals(facts.some((f) => f.includes('درجة الزيت: 0W8')), true);
});

Deno.test('سؤال الضمان يُميَّز وله رد محسوب', () => {
  assertEquals(looksLikeWarrantyQuestion('اكو ضمان على زيت'), true);
  assertEquals(looksLikeWarrantyQuestion('شكد سعر صار'), false);
  const reply = buildWarrantyReply({
    card: {
      customer: 'باقر',
      odo_current: '5000',
      odo_next: '10000',
    },
  });
  assertStringIncludes(reply ?? '', '5,000 كم');
  assertStringIncludes(reply ?? '', 'باقر');
});
