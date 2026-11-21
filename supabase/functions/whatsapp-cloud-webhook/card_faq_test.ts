import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildCardFaqReply,
  buildEmployeeReply,
  buildLastServiceReply,
  buildPriceReply,
  looksLikeEmployeeQuestion,
  looksLikeLastServiceQuestion,
  looksLikePriceQuestion,
} from './card_faq.ts';
import { looksLikeFeedback } from './conversation.ts';

Deno.test('يُميّز أسئلة الموظف والسعر كما في المحادثة', () => {
  assertEquals(looksLikeEmployeeQuestion('من هو موظف'), true);
  assertEquals(looksLikeEmployeeQuestion('ماهو اسم موظف'), true);
  assertEquals(looksLikePriceQuestion('شكد صار سعر'), true);
  assertEquals(looksLikeEmployeeQuestion('خوش شغل'), false);
});

Deno.test('يرد باسم الفني من الإسناد', () => {
  assertStringIncludes(
    buildEmployeeReply({ employeeName: 'ali', card: null }) ?? '',
    'ali',
  );
});

Deno.test('يرد بمبلغ البطاقة', () => {
  const reply = buildPriceReply({
    total: '8,588 د.ع',
    paid: '8,588 د.ع',
    remaining: '-',
  });
  assertStringIncludes(reply ?? '', '8,588');
  assertStringIncludes(reply ?? '', 'الإجمالي');
});

Deno.test('آخر غيار من البطاقة', () => {
  assertEquals(looksLikeLastServiceQuestion('شنو الزيت آخر مرة'), true);
  const reply = buildLastServiceReply({
    customer: 'باقر',
    car: 'كامري',
    oil_brand: 'كاسترول',
    oil_grade: '5W30',
    odo_current: '20005 كم',
    odo_next: '25005 كم',
    employee: 'ali',
  });
  assertStringIncludes(reply ?? '', 'كاسترول');
  assertStringIncludes(reply ?? '', '20005');
});

Deno.test('ضمان بلا أرقام يعطي وعداً بالتأكد لا شكراً أعمى', () => {
  const reply = buildCardFaqReply({
    message: 'ماهو ضمان',
    employeeName: 'ali',
    card: { total: '1000' },
    warrantyReply: null,
    isWarrantyQuestion: true,
  });
  assertStringIncludes(reply ?? '', 'الضمان');
  assertEquals(reply?.includes('ملاحظتك'), false);
});

Deno.test('ماهو ضمان / من هو موظف ليسا رأياً بالخدمة', () => {
  assertEquals(looksLikeFeedback('ماهو ضمان'), false);
  assertEquals(looksLikeFeedback('من هو موظف'), false);
  assertEquals(looksLikeFeedback('شكد صار سعر'), false);
});

Deno.test('شنو الزيت عندكم ليست آخر غيار', () => {
  assertEquals(looksLikeLastServiceQuestion('شنو الزيت عندكم'), false);
  assertEquals(looksLikeLastServiceQuestion('شنو الزيت آخر مرة'), true);
});
