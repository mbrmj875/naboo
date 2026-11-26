// اختبارات التنظيف (م1-2): 20 مثالاً من كلام المحلات.
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { namesFromToolResults, sanitizeForLog, staffNamesFromToolResults, westernDigits } from './sanitize.ts';

const cases: [string, string, string[]?][] = [
  // هواتف
  ['رقمه 07701234567 اتصل بيه', 'رقمه [هاتف] اتصل بيه'],
  ['دز للرقم 0770 123 4567', 'دز للرقم [هاتف]'],
  ['+9647712345678 هذا رقم الزبون', '[هاتف] هذا رقم الزبون'],
  ['٠٧٨٠١٢٣٤٥٦٧ رقم ابو علي', '[هاتف] رقم [زبون]', ['ابو علي']],
  // مبالغ
  ['بعت اليوم بمليون و 250,000 دينار', 'بعت اليوم بمليون و [مبلغ]'],
  ['سعره 28000 دينار', 'سعره [مبلغ]'],
  ['سجل مصروف كهرباء خمسين الف', 'سجل مصروف كهرباء [مبلغ]'],
  ['الدين 75 الف على الزبون', 'الدين [مبلغ] على الزبون'],
  ['الرصيد 320,000 د.ع', 'الرصيد [مبلغ]'],
  // لوحات
  ['شوكت اخر مرة بدلت السيارة 12345 ب؟', 'شوكت اخر مرة بدلت السيارة [لوحة]؟'],
  ['اللوحة ب 777 جاية اليوم', 'اللوحة [لوحة] جاية اليوم'],
  ['سجل غسيل للسيارة 777 ج', 'سجل غسيل للسيارة [لوحة]'],
  // أرقام طويلة
  ['الفاتورة 4471234 مالتي', 'الفاتورة [رقم] مالتي'],
  ['العداد 118000 كم', 'العداد [رقم] كم'],
  // أسماء
  ['شكد دين مرتضى؟', 'شكد دين [زبون]؟', ['مرتضى']],
  ['طلعلي بطاقات حسين علي', 'طلعلي بطاقات [زبون]', ['حسين علي']],
  // لزوجات تبقى
  ['شكد باقي دهن 5W-30؟', 'شكد باقي دهن 5W-30؟'],
  ['اكو 10W40 و 0w-20؟', 'اكو 10W40 و 0w-20؟'],
  ['زيت توتال 5W-30 4 لتر', 'زيت توتال 5W-30 4 لتر'],
  // أرقام قصيرة عادية تبقى
  ['اكو بطاقات معلقة؟ عندي 2 بس', 'اكو بطاقات معلقة؟ عندي 2 بس'],
];

for (const [input, expected, names] of cases) {
  Deno.test(`sanitize: ${input}`, () => {
    assertEquals(sanitizeForLog(input, { names }), expected);
  });
}

Deno.test('westernDigits', () => {
  assertEquals(westernDigits('٥ ٣٠ و ۱۲'), '5 30 و 12');
});

Deno.test('namesFromToolResults reads customer fields only', () => {
  const names = namesFromToolResults([
    { rows: [{ customer: 'مرتضى', plate: '5555 د' }, { name: 'زيت توتال' }] },
    { ok: true, rows: [{ customer_name: 'ابو علي' }] },
  ]);
  assertEquals(names.sort(), ['ابو علي', 'مرتضى'].sort());
});

Deno.test('length is capped', () => {
  assertEquals(sanitizeForLog('ا'.repeat(3000)).length, 2000);
});

Deno.test('أسماء الموظفين من نتائج الأدوات تُستبدل بـ[موظف] (ت4.10)', () => {
  const results = [
    {
      extra: {
        technician_moves: [
          { name: 'جبار', a_count: 0, b_count: 15 },
          { name: 'HAIDER', a_count: 11, b_count: 0 },
        ],
        product_moves: [{ name: 'زيت توتال 5W-30', a_fils: 1, b_fils: 2 }],
      },
    },
    { rows: [{ technician: 'حيدر', plate: '1234' }, { staff: ['كرار'] }] },
  ];
  const staff = staffNamesFromToolResults(results);
  assertEquals(staff.sort(), ['HAIDER', 'جبار', 'حيدر', 'كرار'].sort());
  const out = sanitizeForLog('الأسبوع الماضي جبار 15 بطاقة، وهالأسبوع Haider 11 وحيدر 2 وزيت توتال 5W-30', { staff });
  assertEquals(out.includes('جبار') || out.includes('Haider') || out.includes('حيدر'), false);
  assertEquals(out.includes('[موظف]'), true);
  assertEquals(out.includes('زيت توتال 5W-30'), true);
});
