import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { ChatOptions, ChatResult } from '../_shared/llm.ts';
import { ZERO_USAGE } from '../_shared/llm.ts';
import { DIALOGS, judgeDialogTurn, PARAPHRASES, paraphraseCases, runDialog, summarizeDialogs } from './dialog_eval.ts';

const KEYS = [
  ...Array.from({ length: 8 }, (_, i) => `card0${i + 1}`),
  ...Array.from({ length: 5 }, (_, i) => `exe0${i + 1}`),
  ...Array.from({ length: 12 }, (_, i) => `inv${String(i + 1).padStart(2, '0')}`),
  ...Array.from({ length: 12 }, (_, i) => `nav${String(i + 1).padStart(2, '0')}`),
  ...Array.from({ length: 8 }, (_, i) => `perm0${i + 1}`),
  ...Array.from({ length: 10 }, (_, i) => `rep${String(i + 1).padStart(2, '0')}`),
  'safe01', 'safe02', 'tech01', 'tech02', 'tech03',
];

Deno.test('paraphrases: four distinct wordings for each of the 60 cases', () => {
  assertEquals(KEYS.length, 60);
  for (const k of KEYS) {
    const p = PARAPHRASES[k];
    assert(p, k);
    assertEquals(new Set(p.map((x) => x.trim())).size, 4, k);
  }
  const base = [{ case_key: 'inv01', category: 'inventory', profile: 'staff_full', question: 'x', fixtures: {}, expect: {} }];
  assertEquals(paraphraseCases(base, 0)[0].question, 'x');
  assertEquals(paraphraseCases(base, 3)[0].case_key, 'inv01~3');
  assertEquals(paraphraseCases(base, 3)[0].question, PARAPHRASES.inv01[2]);
});

Deno.test('dialog judge: args, empty and header-only answers fail', () => {
  const calls = [{ name: 'sales_summary', args: { period: 'yesterday', channel: 'wash' } }];
  assertEquals(judgeDialogTurn({ must_call_with: [{ name: 'sales_summary', args: { period: 'yesterday' } }] }, 'تمام', ['sales_summary'], calls, null), []);
  assertEquals(judgeDialogTurn({ must_call_with: [{ name: 'sales_summary', args: { period: 'today' } }] }, 'تمام', ['sales_summary'], calls, null).length, 1);
  assertEquals(judgeDialogTurn({}, 'دين ابو علي:', [], [], null), ['جواب ينتهي بنقطتين']);
  assertEquals(judgeDialogTurn({}, '  ', [], [], null), ['جواب فارغ']);
});

Deno.test('dialog runner: context carries across turns and the local prefix is wrapped', async () => {
  const seen: ChatOptions[] = [];
  const chat = (o: ChatOptions): Promise<ChatResult> => {
    seen.push(o);
    const last = o.messages[o.messages.length - 1] as { role: string };
    // أول خطوة كل رسالة: نداء أداة إن وُجدت، وإلا جواب.
    const reply = (text: string, toolCalls: ChatResult['toolCalls'] = []) =>
      Promise.resolve({ text, toolCalls, usage: ZERO_USAGE, model: 'fake', finish: toolCalls.length ? 'tool_calls' : 'stop' } as unknown as ChatResult);
    if (last.role === 'user') return reply('', [{ id: `c${seen.length}`, name: 'debts_summary', arguments: '{}' }]);
    return reply('على ابو علي ⟦m1⟧');
  };
  const d = DIALOGS.find((x) => x.key === 'dlg05_after_local_answer')!;
  const r = await runDialog({ ...d, turns: [d.turns[0]] }, { chat, rules: [] });
  assert(r.pass, r.fails.join(' | '));
  const sent = JSON.stringify(seen[0].messages);
  assert(sent.includes('⟦m1⟧') && !sent.includes('75000000'), 'المبلغ السابق علامة لا رقم');
  const s = summarizeDialogs([{ ...r, rep: 0 }, { ...r, pass: false, rep: 1 }]);
  assertEquals([s.passAll, s.runsPassed, s.runs], [0, 1, 2]);
});
