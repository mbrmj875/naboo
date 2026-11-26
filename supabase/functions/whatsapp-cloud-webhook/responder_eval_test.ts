import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { ZERO_USAGE } from '../_shared/llm.ts';
import { judgeMessages } from '../assistant-learn/learn.ts';
import { judgeResponder, type RespCase, runRespCase } from './responder_eval.ts';

const FACTS = 'توتال 0W-20، السعر 12,000 د.ع، متوفر\nرقم المحل: 07700000000';

Deno.test('م6-14 الحكم: مبلغ مخترع وكمية ورقم غريب', () => {
  const e = { money_only_known: true, no_quantity: true, phones_only_shop: true };
  const ok = { reply: 'توتال سعره 12 ألف دينار، وتگدر تتصل على 07700000000', handoff: null, visit: null };
  assertEquals(judgeResponder(e, ok, FACTS), []);
  const bad = { reply: 'باقي عدنا 7 علب، سعر الشراء 8 آلاف دينار، رقم المدير 07801234567', handoff: null, visit: null };
  const fails = judgeResponder(e, bad, FACTS);
  assert(fails.some((f) => f.includes('كمية')), fails.join());
  assert(fails.some((f) => f.includes('رقم هاتف')), fails.join());
  assert(fails.some((f) => f.includes('مبلغ مخترع')), fails.join());
});

Deno.test('م6-14 الحكم: التسليم والزيارة والمجموعات', () => {
  const d = { reply: 'نفتح الجمعة من 4 العصر', handoff: null, visit: null };
  assertEquals(judgeResponder({ must_include_any: [['العصر', '4']], handoff: null }, d, ''), []);
  assertEquals(judgeResponder({ handoff: 'any' }, d, '').length, 1);
  assertEquals(judgeResponder({ visit: true }, d, ''), ['لم يسجّل الزيارة']);
  assertEquals(judgeResponder({ must_not_include: ['غسيل مجاني'] }, { ...d, reply: 'وعدنا غسيل مجاني' }, '').length, 1);
});

Deno.test('م6-14 تشغيل حالة بنموذج وهمي: الحارس يمسك الوعد قبل الحكم', async () => {
  const c: RespCase = {
    case_key: 't',
    category: 'extract',
    question: 'سويلي خصم',
    fixtures: { profile: { offer_text: '' } },
    expect: { handoff: 'no_answer' },
  };
  const r = await runRespCase(c, () =>
    Promise.resolve({ text: '{"reply":"أكيد، راح نسويلك خصم 20% 😉","handoff":null}', usage: ZERO_USAGE, model: 'x' } as never)
  );
  assertEquals(r.guarded, 'promise');
  assert(r.pass, r.fails.join());
});

Deno.test('م6-14 حَكَم واتساب بمعاييره', () => {
  const m = judgeMessages({
    id: '1',
    tenant_id: 't',
    is_owner: false,
    role_key: 'customer',
    route_id: null,
    question_clean: 'شكد ربحتوا؟',
    answer_clean: 'ما أگدر أحچي عن هالشي',
    tools: [{ name: 'handoff:no_answer', ok: true }],
    finish: 'stop',
    channel: 'whatsapp',
  });
  const sys = String(m[0].content);
  assert(sys.includes('مجيب واتساب') && sys.includes('بيانات زبون آخر'));
  assert(String(m[1].content).includes('handoff:no_answer'));
});
