import { assert, assertEquals } from 'jsr:@std/assert@1';
import { TOOL_DEFS } from '../assistant-chat/tools.ts';
import { toolsFor } from '../assistant-chat/eval_core.ts';
import { BENCH, BENCH_CATS, BENCH_PARTS, benchPart } from './bench_tasks.ts';

Deno.test('ح8: نحو 150 مهمة بلا تكرار، وكل فئة معروفة، والأجزاء تغطي الكل', () => {
  const keys = BENCH.map((b) => b.key);
  assertEquals(new Set(keys).size, keys.length);
  assert(BENCH.length >= 140 && BENCH.length <= 180, `${BENCH.length}`);
  for (const b of BENCH) assert(b.cat in BENCH_CATS, b.key);
  let n = 0;
  for (let p = 0; p < BENCH_PARTS; p++) n += benchPart(p).length;
  assertEquals(n, BENCH.length);
});

Deno.test('ح8: كل أداة في التوقعات معروفة، وكل شاشة في خريطة الخادم', async () => {
  const screens = await Deno.readTextFile(new URL('../assistant-chat/screens.ts', import.meta.url));
  for (const b of BENCH) {
    const e = b.turns[0].expect;
    const names = [...(e.must_call ?? []), ...(e.must_call_any ?? []), ...(e.must_not_call ?? []), ...(e.must_call_with ?? []).map((w) => w.name), ...(e.must_call_with_any ?? []).map((w) => w.name)];
    for (const n of names) assert(n in TOOL_DEFS, `${b.key}: ${n}`);
    for (const w of [...(e.must_call_with ?? []), ...(e.must_call_with_any ?? [])]) {
      if (w.name === 'ui_navigate') assert(screens.includes(`"${w.args.route_id}"`), `${b.key}: ${w.args.route_id}`);
    }
    assert(toolsFor(b.profile).length > 0, b.profile);
  }
});

Deno.test('ح8: كل الأدوات تُعلن للمالك، لا يُقطع منها شيء (خلل 48 من 51)', async () => {
  const { MAX_TOOLS, toolDefsFor } = await import('../assistant-chat/tools.ts');
  assert(Object.keys(TOOL_DEFS).length <= MAX_TOOLS, `${Object.keys(TOOL_DEFS).length} > ${MAX_TOOLS}`);
  assertEquals(toolDefsFor(Object.keys(TOOL_DEFS)).length, Object.keys(TOOL_DEFS).length);
});
