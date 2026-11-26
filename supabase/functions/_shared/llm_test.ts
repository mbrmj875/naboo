import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildChatBody, costMicroUsd, isPeak, parseUsage, StreamAssembler } from './llm.ts';

Deno.test('thinking is explicit: off disables, low enables with effort', () => {
  const off = buildChatBody({ messages: [], temperature: 0.2 });
  assertEquals(off.thinking, { type: 'disabled' });
  assertEquals(off.temperature, 0.2);
  assertEquals(off.model, 'deepseek-flash');
  const low = buildChatBody({ messages: [], effort: 'low', temperature: 0.2 });
  assertEquals(low.thinking, { type: 'enabled' });
  assertEquals(low.reasoning_effort, 'low');
  assertEquals(low.temperature, undefined);
});

Deno.test('stream body asks for usage', () => {
  const b = buildChatBody({ messages: [], stream: true });
  assertEquals(b.stream_options, { include_usage: true });
});

Deno.test('peak hours in Baghdad time on weekdays', () => {
  // الاثنين 2026-11-23: بغداد = UTC+3.
  assert(isPeak(new Date('2026-11-23T05:00:00+03:00')));
  assert(isPeak(new Date('2026-11-23T10:30:00+03:00')));
  assert(!isPeak(new Date('2026-11-23T08:00:00+03:00')));
  assert(!isPeak(new Date('2026-11-23T20:00:00+03:00')));
  // السبت ليس ذروة.
  assert(!isPeak(new Date('2026-11-28T10:30:00+03:00')));
});

Deno.test('cost matches the measured benchmark question (ب0)', () => {
  // متوسط سؤال بلا تفكير في ب0: 382 غير مخزَّن، 5660 مخزَّن، 95 إخراج = 0.00026 $ بالذروة.
  const u = { miss: 382, hit: 5660, out: 95 };
  assertEquals(costMicroUsd(u, new Date('2026-11-23T10:00:00+03:00')), 263);
  assertEquals(costMicroUsd(u, new Date('2026-11-23T20:00:00+03:00')), 132);
});

Deno.test('parseUsage falls back when cache fields are missing', () => {
  assertEquals(parseUsage({ prompt_tokens: 100, completion_tokens: 7 }), { miss: 100, hit: 0, out: 7 });
  assertEquals(
    parseUsage({ prompt_tokens: 100, prompt_cache_hit_tokens: 60, prompt_cache_miss_tokens: 40, completion_tokens: 7 }),
    { miss: 40, hit: 60, out: 7 },
  );
});

Deno.test('stream assembler joins text and split tool calls', () => {
  const a = new StreamAssembler();
  const lines = [
    'data: {"model":"deepseek-flash","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}',
    'data: {"choices":[{"index":0,"delta":{"content":"هلا "}}]}',
    'data: {"choices":[{"index":0,"delta":{"content":"بيك"}}]}',
    'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"stock_search","arguments":""}}]}}]}',
    'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"query\\":"}}]}}]}',
    'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"5W-30\\"}"}}]}}]}',
    'data: {"choices":[{"index":0,"delta":{"content":""},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":428,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":428,"completion_tokens":40}}',
    'data: [DONE]',
  ];
  const pieces = lines.map((l) => a.feed(l)).filter(Boolean);
  assertEquals(pieces, ['هلا ', 'بيك']);
  const r = a.result('x');
  assertEquals(r.text, 'هلا بيك');
  assertEquals(r.finish, 'tool_calls');
  assertEquals(r.model, 'deepseek-flash');
  assertEquals(r.toolCalls, [{ id: 'call_1', name: 'stock_search', arguments: '{"query":"5W-30"}' }]);
  assertEquals(r.usage, { miss: 428, hit: 0, out: 40 });
});
