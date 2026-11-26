import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { carSpec, grade, isOfficial, normMake, normViscosity, parseFacts } from './car_spec.ts';
import { parseWebSources } from '../_shared/llm.ts';

const toyota = 'https://www.toyota.com/owners/manual';
const a = 'https://www.oilfinder.com/corolla';
const b = 'https://partsouq.com/x';

Deno.test('normalization: Arabic make names and viscosity forms', () => {
  assertEquals(normMake('تويوتا'), 'toyota');
  assertEquals(normMake('هيونداي'), 'hyundai');
  assertEquals(normViscosity('0w20'), '0W-20');
  assertEquals(normViscosity('SAE 5W-30'), '5W-30');
  assert(isOfficial(toyota, 'toyota'));
  assert(!isOfficial(a, 'toyota'));
});

Deno.test('grade: one official source is enough', () => {
  const f = { capacity_l: 4.2, viscosity_primary: '0W-20', per_source: [{ url: toyota, capacity_l: 4.2, viscosity: '0W-20' }] };
  assertEquals(grade(f, [], 'toyota'), 'verified');
});

Deno.test('grade: two different domains agreeing within 0.2 L = verified', () => {
  const f = {
    capacity_l: 4.2,
    viscosity_primary: '0W-20',
    per_source: [{ url: a, capacity_l: 4.2, viscosity: '0W-20' }, { url: b, capacity_l: 4.1, viscosity: '0w20' }],
  };
  assertEquals(grade(f, [], 'toyota'), 'verified');
});

Deno.test('grade: same domain twice is still one source', () => {
  const f = {
    capacity_l: 4.2,
    viscosity_primary: '0W-20',
    per_source: [{ url: a, capacity_l: 4.2 }, { url: 'https://shop.oilfinder.com/y', capacity_l: 4.2 }],
  };
  assertEquals(grade(f, [], 'toyota'), 'single_source');
});

Deno.test('grade: conflicting sources are not saved', () => {
  const f = {
    capacity_l: 4.2,
    viscosity_primary: '0W-20',
    per_source: [{ url: a, capacity_l: 4.2, viscosity: '0W-20' }, { url: b, capacity_l: 4.8, viscosity: '5W-30' }],
  };
  assertEquals(grade(f, [], 'toyota'), 'unverified');
  assertEquals(grade({ viscosity_primary: '0W-20' }, [], 'toyota'), 'unverified');
});

Deno.test('parseFacts reads the first JSON object and drops junk', () => {
  const f = parseFacts('ok {"capacity_l": "4.2", "viscosity_primary": "0w20", "filter_refs": ["04152-YZZA6"], "per_source": [{"url": "https://x.com", "capacity_l": 4.2}]} end');
  assertEquals(f?.capacity_l, 4.2);
  assertEquals(f?.viscosity_primary, '0W-20');
  assertEquals(f?.filter_refs, ['04152-YZZA6']);
  assertEquals(parseFacts('no json'), null);
});

Deno.test('web sources are read from server_tool_calls whatever the nesting', () => {
  const s = parseWebSources([{ type: 'deepseek_web_search', calls: [{ query: 'q', sources: [{ url: a, title: 'A' }, { link: b, name: 'B' }, { url: 'ftp://x' }] }] }]);
  assertEquals(s.map((x) => x.url), [a, b]);
});

/** قاعدة وهمية بقدر ما يستعمله carSpec. */
function fakeAdmin(rows: Record<string, unknown>[]) {
  const writes: { op: string; row: Record<string, unknown> }[] = [];
  const q = (table: string) => {
    let data: Record<string, unknown>[] = table === 'assistant_car_specs' ? rows : [];
    const api: Record<string, unknown> = {
      select: () => api,
      eq: (k: string, v: unknown) => ((data = data.filter((r) => r[k] === v)), api),
      lte: (k: string, v: number) => ((data = data.filter((r) => Number(r[k]) <= v)), api),
      gte: (k: string, v: number) => ((data = data.filter((r) => Number(r[k]) >= v)), api),
      order: () => api,
      limit: () => Promise.resolve({ data }),
      maybeSingle: () => Promise.resolve({ data: null }),
      update: (row: Record<string, unknown>) => (writes.push({ op: 'update', row }), { eq: () => Promise.resolve({}) }),
      insert: (row: Record<string, unknown>) => (writes.push({ op: 'insert', row }), Promise.resolve({})),
    };
    return api;
  };
  return { admin: { from: q } as never, writes };
}

const searchResult = (text: string, sources = [{ url: toyota, title: 'Toyota' }]) => () =>
  Promise.resolve({ text, toolCalls: [], finish: 'stop', usage: { miss: 100, hit: 0, out: 50 }, model: 'm', sources });

Deno.test('car_spec: a verified row in the guide answers without search', async () => {
  const { admin, writes } = fakeAdmin([
    { id: 1, make: 'toyota', model: 'corolla', year_from: 2014, year_to: 2018, oil_capacity_l: 4.2, viscosity_primary: '0W-20', confidence: 'verified', hits: 3, sources: [] },
  ]);
  let searched = false;
  const r = await carSpec({ make: 'تويوتا', model: 'Corolla', year: 2015 }, {
    admin,
    search: () => ((searched = true), searchResult('{}')()),
  });
  assert(!searched);
  assertEquals(r.usedWeb, false);
  assertEquals((r.result.rows as Record<string, unknown>[])[0].capacity_l, 4.2);
  assertEquals(writes[0].row.hits, 4);
});

Deno.test('car_spec: a new car is searched, graded and saved', async () => {
  const { admin, writes } = fakeAdmin([]);
  const r = await carSpec({ make: 'toyota', model: 'camry', year: 2019 }, {
    admin,
    search: searchResult(`{"capacity_l": 4.8, "viscosity_primary": "0W-20", "per_source": [{"url": "${toyota}", "capacity_l": 4.8, "viscosity": "0W-20"}]}`),
  });
  assertEquals(r.usedWeb, true);
  assertEquals(writes[0].op, 'insert');
  assertEquals(writes[0].row.confidence, 'verified');
  assertEquals((r.result.rows as Record<string, unknown>[])[0].confidence, 'verified');
});

Deno.test('car_spec: conflicting sources show no numbers and save nothing', async () => {
  const { admin, writes } = fakeAdmin([]);
  const r = await carSpec({ make: 'kia', model: 'sportage', year: 2017 }, {
    admin,
    search: searchResult(`{"capacity_l": 4.0, "viscosity_primary": "5W-30", "per_source": [{"url": "${a}", "capacity_l": 4.0}, {"url": "${b}", "capacity_l": 4.8}]}`, []),
  });
  assertEquals(writes.length, 0);
  assertEquals((r.result.rows as unknown[]).length, 0);
  assertEquals((r.result.extra as Record<string, unknown>).confidence, 'unverified');
});

Deno.test('keep-alive lines before the JSON body are ignored', async () => {
  const { parseChatJson } = await import('../_shared/llm.ts');
  assertEquals(parseChatJson(': keep-alive\n\n: keep-alive\n{"choices":[1]}')?.choices, [1]);
  assertEquals(parseChatJson('<html>'), null);
});

Deno.test('grade: a clear majority over one dissenting site goes to review, never verified', () => {
  const c = 'https://www.repco.com.au/x';
  const f = {
    capacity_l: 4.2,
    viscosity_primary: '0W-20',
    per_source: [
      { url: 'https://choise.ravenol.com/x', capacity_l: 4.7, viscosity: '5W-20' },
      { url: c, capacity_l: 4.2, viscosity: '0W-20' },
      { url: b, capacity_l: 4.2, viscosity: '0W-20' },
    ],
  };
  assertEquals(grade(f, [], 'toyota'), 'single_source');
  // اثنان ضد اثنين: متعارض.
  f.per_source.push({ url: 'https://shop.other.com/y', capacity_l: 4.8, viscosity: '5W-30' });
  assertEquals(grade(f, [], 'toyota'), 'unverified');
});
