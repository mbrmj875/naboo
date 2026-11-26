import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { type Lesson, notesMessage, pickNotes, similarity } from '../assistant-chat/lessons.ts';
import { judgeCase } from '../assistant-chat/eval_core.ts';
import {
  checkLesson,
  clusters,
  type FailedTurn,
  flipped,
  judgeMessages,
  normTopic,
  parseLesson,
  parseVerdict,
  safetyDecision,
  shouldRetire,
  verdictFailed,
} from './learn.ts';

const ft = (id: string, tenant: string, topic: string, correction: string | null = null): FailedTurn => ({
  id,
  tenant_id: tenant,
  topic,
  question: `س ${id}`,
  answer: 'ج',
  note: null,
  correction,
  created_at: `2026-11-24T10:0${id.length}:00Z`,
});

Deno.test('الحَكَم: الحكم يُقرأ، والموضوع من القائمة أو شاشة معروفة', () => {
  const v = parseVerdict(
    '```json\n{"answered":true,"grounded":false,"perm_ok":true,"no_invention":"true","topic":"guide:app_oil_change_create","note":"رقم 123456 بلا أداة"}\n```',
  );
  assertEquals(v?.grounded, false);
  assertEquals(v?.topic, 'guide:app_oil_change_create');
  assertEquals(v?.note, 'رقم [رقم] بلا أداة');
  assert(verdictFailed(v!));
  assertEquals(normTopic('guide:app_made_up'), 'guide:unknown');
  assertEquals(normTopic('weird'), 'other');
  assertEquals(parseVerdict('{"answered":true}'), null, 'حكم ناقص لا يُحفظ');
  assertEquals(parseVerdict('لا أعرف'), null);
});

Deno.test('الحَكَم يرى أسماء الأدوات ونجاحها والتصحيح، لا نتائجها', () => {
  const m = judgeMessages({
    id: 'x',
    tenant_id: 't',
    is_owner: false,
    role_key: 'cashier',
    route_id: 'app_home',
    question_clean: 'شكد باقي؟',
    answer_clean: 'باقي 4',
    tools: [{ name: 'stock_search', ok: false, rows: 0 }],
    finish: 'stop',
    user_correction: 'باقي 2',
  });
  const u = String(m[1].content);
  assert(u.includes('stock_search:fail(0)'));
  assert(u.includes('تصحيح المستخدم: باقي 2'));
});

Deno.test('م5-4 التجميع: 3 إخفاقات من محلَّين على الأقل، والتصحيح أولاً', () => {
  const failed = [
    ft('a', 't1', 'stock'),
    ft('bb', 't1', 'stock'),
    ft('ccc', 't2', 'stock', 'الصحيح كذا'),
    ft('d', 't1', 'reports'),
    ft('ee', 't1', 'reports'),
    ft('fff', 't1', 'reports'), // محل واحد: لا درس
    ft('g', 't1', 'off_topic'),
    ft('hh', 't2', 'off_topic'),
    ft('iii', 't3', 'off_topic'),
  ];
  const c = clusters(failed);
  assertEquals(c.map((x) => x.topic), ['stock']);
  assertEquals(c[0].turns[0].id, 'ccc');
  assertEquals(clusters(failed, new Set(['stock'])), [], 'موضوع له درس حديث يُترك');
});

Deno.test('الفحص الآلي للدرس', () => {
  const ok = {
    kind: 'screen_note' as const,
    trigger_text: 'وين أغيّر سعر الغيار؟',
    body: 'سعر الغيار في شاشة app_oil_change_create.',
  };
  assertEquals(checkLesson(ok), null);
  assertEquals(checkLesson({ ...ok, body: 'الزيت 5W-30 مناسب' }), null, 'اللزوجة ليست رقماً ممنوعاً');
  assert(checkLesson({ ...ok, body: 'خذ 500 مل' }) == null);
  assert(checkLesson({ ...ok, body: 'اتصل على 07701234567' })?.includes('رقم'));
  assert(checkLesson({ ...ok, body: 'قل للـ[زبون] كذا' })?.includes('منظّفة'));
  assert(checkLesson({ ...ok, body: 'اضغط زر oil_price_btn' })?.includes('oil_price_btn'));
  assertEquals(checkLesson({ ...ok, body: 'استعمل stock_search ثم ui_navigate' }), null);
  assert(checkLesson({ ...ok, body: 'كلمة '.repeat(80) })?.includes('70'));
  assertEquals(parseLesson('{"skip": true}'), null);
  assertEquals(parseLesson('{"kind":"other","trigger_text":"س","body":"ب"}'), null);
});

Deno.test('م5-5 اختبار الأمان: لا تراجع، والنتيجة لا تنزل، والتذبذب لا يُحسب', () => {
  const base = [{ key: 'a', pass: true }, { key: 'b', pass: true }, { key: 'c', pass: false }];
  // تحسّن بلا تراجع: يُنشر.
  assertEquals(
    safetyDecision(base, [{ key: 'a', pass: true }, { key: 'b', pass: true }, { key: 'c', pass: true }]).publish,
    true,
  );
  // حالة ناجحة فشلت وتأكد فشلها: يُرفض حتى لو تحسنت أخرى.
  const bad = [{ key: 'a', pass: false }, { key: 'b', pass: true }, { key: 'c', pass: true }];
  assertEquals(flipped(base, bad), ['a']);
  const d = safetyDecision(base, bad, new Map([['a', { withPass: false, basePass: true }]]));
  assertEquals(d.publish, false);
  assertEquals(d.regressions, ['a']);
  // نجحت في الإعادة مع الدرس: تذبذب، يُنشر.
  assertEquals(safetyDecision(base, bad, new Map([['a', { withPass: true, basePass: true }]])).publish, true);
  // فشلت بدون الدرس أيضاً في الإعادة: الحالة متذبذبة، ليست تراجعاً، لكن النتيجة لا تنزل.
  const flaky = safetyDecision(
    base,
    [{ key: 'a', pass: false }, { key: 'b', pass: true }, { key: 'c', pass: false }],
    new Map([['a', { withPass: false, basePass: false }]]),
  );
  assertEquals(flaky.publish, false);
  assert(flaky.reason.includes('نزلت'));
});

Deno.test('التقاعد: 14 يوماً و20 استعمالاً وفشل أعلى من المتوسط', () => {
  const now = new Date('2026-12-20T00:00:00Z');
  const u = { id: 1, activated_at: '2026-12-01T00:00:00Z', uses: 30, judged: 20, fails: 8 };
  assertEquals(shouldRetire(u, 0.2, now), true);
  assertEquals(shouldRetire(u, 0.5, now), false);
  assertEquals(shouldRetire({ ...u, uses: 10 }, 0.2, now), false);
  assertEquals(shouldRetire({ ...u, activated_at: '2026-12-15T00:00:00Z' }, 0.2, now), false);
});

Deno.test('م5-6 الاسترجاع: الأقرب فوق العتبة، والقواعد لا تُسترجع', () => {
  const ls: Lesson[] = [
    { id: 1, kind: 'qa', topic: 'x', trigger_text: 'وين اغير سعر تبديل الزيت', body: 'من إعدادات الخدمات' },
    { id: 2, kind: 'qa', topic: 'y', trigger_text: 'شكد بعت اليوم', body: 'sales_summary' },
    { id: 3, kind: 'rule', topic: 'z', trigger_text: 'وين أغيّر سعر تبديل الزيت', body: 'قاعدة' },
  ];
  assert(similarity('وين أغيّر سعر تبديل الزيت؟', 'وين اغير سعر تبديل الزيت') > 0.9);
  assertEquals(pickNotes(ls, 'وين أغير سعر تبديل الزيت؟').map((l) => l.id), [1]);
  assertEquals(pickNotes(ls, 'عندي مشكلة بالطابعة'), []);
  assert(notesMessage(pickNotes(ls, 'وين أغير سعر تبديل الزيت')).includes('من إعدادات الخدمات'));
});

Deno.test('فحص الحالات في الخادم مطابق لسكربت التقييم', () => {
  const e = { must_call: ['stock_search'], must_include_any: ['5W-30', '٥w٣٠'], nav_route: 'app_inventory' };
  assertEquals(judgeCase(e, 'باقي 12 لتر 5W-30', ['stock_search'], 'app_inventory'), []);
  assertEquals(judgeCase(e, 'ما أعرف', [], null).length, 3);
});
