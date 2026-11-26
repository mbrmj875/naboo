/**
 * تقييم المساعد على مجموعة الاختبار الثابتة (خطة المساعد، م0-4 و م0-5).
 *
 * التشغيل:
 *   deno run -A tool/assistant_eval.ts --target guide-assistant   # خط الأساس (م0-6)
 *   deno run -A tool/assistant_eval.ts --target assistant-chat    # المساعد الجديد
 *   deno run -A tool/assistant_eval.ts --emit-seed-sql            # يطبع SQL لرفع الحالات
 *
 * المتغيرات:
 *   SUPABASE_URL, SUPABASE_ANON_KEY
 *   EVAL_ACCESS_TOKEN   رمز جلسة حساب المحل النموذجي (لا حساب محل حقيقي)
 *
 * الفحص آلي بلا حَكَم: الأداة المطلوبة، الأداة الممنوعة، النص المطلوب والممنوع، والمسار.
 * الخادم لا يملك قاعدة الهاتف، فالسكربت يحاكي الهاتف ويعيد نتائج الأدوات الجاهزة (fixtures).
 */

type Expect = {
  must_call?: string[];
  must_call_any?: string[];
  must_not_call?: string[];
  must_include?: string[];
  must_include_any?: string[];
  must_not_include?: string[];
  nav_route?: string;
};

type EvalCase = {
  case_key: string;
  category: string;
  profile: string;
  question: string;
  fixtures: Record<string, unknown>;
  expect: Expect;
};

type CaseResult = {
  key: string;
  category: string;
  pass: boolean;
  fails: string[];
  reply: string;
  called: string[];
  nav: string | null;
  ms: number;
};

const args = new Map<string, string | true>();
for (let i = 0; i < Deno.args.length; i++) {
  const a = Deno.args[i];
  if (!a.startsWith('--')) continue;
  const next = Deno.args[i + 1];
  if (next && !next.startsWith('--')) {
    args.set(a.slice(2), next);
    i++;
  } else {
    args.set(a.slice(2), true);
  }
}

const casesPath = new URL('../test/assistant/golden/cases.json', import.meta.url);
const all: EvalCase[] = JSON.parse(await Deno.readTextFile(casesPath)).cases;
const only = args.get('only');
const cases = typeof only === 'string'
  ? all.filter((c) => only.split(',').includes(c.case_key) || c.category === only)
  : all;

// ------------------------------------------------------------ رفع الحالات
if (args.has('emit-seed-sql')) {
  const q = (s: string) => `'${s.replaceAll("'", "''")}'`;
  const rows = all.map((c) =>
    `(${q(c.case_key)}, 'app', ${q(c.category)}, ${q(c.profile)}, ${q(c.question)}, ` +
    `${q(JSON.stringify(c.fixtures))}::jsonb, ${q(JSON.stringify(c.expect))}::jsonb)`
  );
  console.log(
    'insert into public.assistant_eval_cases ' +
      '(case_key, audience, category, profile, question, fixtures, expect) values\n' +
      rows.join(',\n') +
      '\non conflict (case_key) do update set category = excluded.category, ' +
      'profile = excluded.profile, question = excluded.question, fixtures = excluded.fixtures, ' +
      'expect = excluded.expect, active = true, updated_at = now();',
  );
  Deno.exit(0);
}

const url = Deno.env.get('SUPABASE_URL') ?? '';
const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
const token = Deno.env.get('EVAL_ACCESS_TOKEN') ?? '';
if (!url || !anon || !token) {
  console.error('SUPABASE_URL و SUPABASE_ANON_KEY و EVAL_ACCESS_TOKEN مطلوبة');
  Deno.exit(2);
}
const target = (args.get('target') as string) ?? 'assistant-chat';

// ------------------------------------------------------------ الأدوات لكل ملف تعريف
const UI_TOOLS = ['ui_describe', 'ui_navigate', 'ui_highlight', 'ui_guide', 'ui_start_tour'];
const READ_TOOLS = [
  'stock_search', 'stock_low', 'product_detail', 'oil_card_find', 'car_history',
  'customer_find', 'car_spec',
];
const REPORT_TOOLS = ['sales_summary', 'top_products', 'ratings_summary', 'staff_status', 'wa_status'];
const MONEY_TOOLS = ['debts_summary', 'cash_summary'];
const EXEC_TOOLS = [
  'prepare_oil_card', 'prepare_car_wash', 'prepare_customer', 'prepare_product',
  'prepare_expense', 'propose_price_change', 'propose_stock_adjust',
];

function toolsFor(profile: string): string[] {
  switch (profile) {
    case 'owner':
      return [...UI_TOOLS, ...READ_TOOLS, ...REPORT_TOOLS, ...MONEY_TOOLS, ...EXEC_TOOLS, 'reorder_suggest'];
    case 'staff_full':
      return [...UI_TOOLS, ...READ_TOOLS, 'prepare_oil_card', 'prepare_car_wash', 'prepare_customer'];
    case 'staff_limited':
      return [...UI_TOOLS, 'stock_search', 'stock_low', 'oil_card_find', 'car_history'];
    case 'guide_only':
      return [...UI_TOOLS];
    default:
      return [];
  }
}

function normalize(s: string): string {
  return s
    .replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)))
    .replace(/[,،]/g, '')
    .toLowerCase();
}

function judge(c: EvalCase, reply: string, called: string[], nav: string | null): string[] {
  const e = c.expect;
  const r = normalize(reply);
  const fails: string[] = [];
  for (const t of e.must_call ?? []) if (!called.includes(t)) fails.push(`لم يستدعِ ${t}`);
  if (e.must_call_any && !e.must_call_any.some((t) => called.includes(t))) {
    fails.push(`لم يستدعِ أياً من ${e.must_call_any.join('/')}`);
  }
  for (const t of e.must_not_call ?? []) if (called.includes(t)) fails.push(`استدعى الممنوع ${t}`);
  for (const s of e.must_include ?? []) if (!r.includes(normalize(s))) fails.push(`ينقصه «${s}»`);
  if (e.must_include_any && !e.must_include_any.some((s) => r.includes(normalize(s)))) {
    fails.push(`ينقصه أحد: ${e.must_include_any.join(' / ')}`);
  }
  for (const s of e.must_not_include ?? []) if (r.includes(normalize(s))) fails.push(`فيه الممنوع «${s}»`);
  if (e.nav_route && nav !== e.nav_route) fails.push(`المسار ${nav ?? 'لا شيء'} بدل ${e.nav_route}`);
  return fails;
}

// ------------------------------------------------------------ المساعد الحالي (خط الأساس)
const LEGACY_SCOPE = (profile: string) => ({
  is_owner: profile === 'owner',
  role_key: profile === 'owner' ? 'owner' : 'staff',
  oil_enabled: true,
  car_wash_enabled: true,
  can_whatsapp: profile === 'owner',
  can_customize_home: profile === 'owner',
  can_manage_users: profile === 'owner',
  can_owner_dashboard: profile === 'owner',
  can_manage_products: profile !== 'guide_only' && profile !== 'staff_limited',
  can_view_inventory: profile !== 'guide_only',
});

async function runLegacy(c: EvalCase): Promise<CaseResult> {
  const t0 = Date.now();
  const res = await fetch(`${url}/functions/v1/guide-assistant`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      question: c.question,
      route_id: 'app_oil_services_log',
      scope: LEGACY_SCOPE(c.profile),
      history: [],
    }),
  });
  const body = await res.json().catch(() => ({}));
  const reply = String(body.reply ?? body.error ?? '');
  const tour = String(body.tour_id ?? 'none');
  // القديم لا يستدعي أدوات. الجولة تُحسب كتنقل بلا مسار محدد.
  const called = tour !== 'none' ? ['ui_start_tour'] : [];
  const fails = judge(c, reply, called, null);
  return { key: c.case_key, category: c.category, pass: fails.length === 0, fails, reply, called, nav: null, ms: Date.now() - t0 };
}

// ------------------------------------------------------------ المساعد الجديد (بث + أدوات)
type Msg = Record<string, unknown>;

async function step(c: EvalCase, messages: Msg[], stepNo: number, turnId: string, threadId: string) {
  // حد الدالة 20 طلباً بالدقيقة لكل محل: ننتظر ونعيد بدل أن يُحسب رفضاً.
  for (let attempt = 0; ; attempt++) {
    const r = await stepOnce(c, messages, stepNo, turnId, threadId);
    if (r !== 'rate_limited') return r;
    if (attempt >= 4) throw new Error('HTTP 429 بعد 4 محاولات');
    await new Promise((ok) => setTimeout(ok, 61_000));
  }
}

async function stepOnce(c: EvalCase, messages: Msg[], stepNo: number, turnId: string, threadId: string) {
  const res = await fetch(`${url}/functions/v1/assistant-chat`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, apikey: anon, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      op: 'step',
      thread_id: threadId,
      turn_id: turnId,
      step: stepNo,
      route_id: 'app_oil_services_log',
      role_key: c.profile === 'owner' ? 'owner' : 'staff',
      is_owner: c.profile === 'owner',
      app_version: 'eval',
      eval: true,
      stream: false,
      tools: toolsFor(c.profile),
      messages,
    }),
  });
  if (res.status === 429) {
    await res.body?.cancel();
    return 'rate_limited' as const;
  }
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
  return await res.json() as {
    text?: string;
    tool_calls?: { id: string; name: string; arguments: Record<string, unknown> }[];
    finish?: string;
  };
}

/**
 * نفس ما يفعله الهاتف (AssistantMoneyRefs + الحارس): كل حقل *_fils يصير علامة
 * قبل أن يراه النموذج، والجواب يُطبع بالعلامات. نسخة لكل محادثة.
 */
export class MoneyRefs {
  private fils = new Map<string, number>();
  private next = 1;
  wrap(v: unknown): unknown {
    if (Array.isArray(v)) return v.map((x) => this.wrap(x));
    if (v && typeof v === 'object') {
      const out: Record<string, unknown> = {};
      for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
        if (k.endsWith('_fils') && typeof x === 'number') {
          const t = `⟦m${this.next++}⟧`;
          this.fils.set(t, Math.round(x));
          out[k.slice(0, -5)] = t;
        } else out[k] = this.wrap(x);
      }
      return out;
    }
    return v;
  }
  /** الجواب كما يراه المستخدم، وعدد العلامات المجهولة (تظهر «—» في الهاتف). */
  render(text: string): { text: string; unknown: string[] } {
    const unknown: string[] = [];
    const out = text.replace(/⟦m\d{1,12}⟧/g, (t) => {
      const f = this.fils.get(t);
      if (f == null) {
        unknown.push(t);
        return '—';
      }
      return `${Math.round(f / 1000).toLocaleString('en-US')} د.ع`;
    });
    return { text: out, unknown };
  }
}

/** مبلغ بالدينار كتبه النموذج بنفسه بدل العلامة. */
export function hasRawAmount(text: string): boolean {
  return /\d[\d,٬.]*\s*(?:الف|ألف)?\s*(?:دينار|د\.?\s?ع)/.test(text);
}

async function runNew(c: EvalCase): Promise<CaseResult> {
  const refs = new MoneyRefs();
  const t0 = Date.now();
  const turnId = crypto.randomUUID();
  const threadId = crypto.randomUUID();
  const messages: Msg[] = [{ role: 'user', content: c.question }];
  const called: string[] = [];
  let reply = '';
  let nav: string | null = null;
  for (let s = 0; s < 5; s++) {
    const out = await step(c, messages, s, turnId, threadId);
    reply += out.text ?? '';
    const calls = out.tool_calls ?? [];
    if (calls.length === 0) break;
    messages.push({ role: 'assistant', content: out.text ?? '', tool_calls: calls });
    for (const call of calls) {
      called.push(call.name);
      if (call.name === 'ui_navigate') nav = String(call.arguments?.route_id ?? '');
      const allowed = toolsFor(c.profile).includes(call.name);
      const result = !allowed
        ? { ok: false, error: 'forbidden' }
        : c.fixtures[call.name] ?? (call.name.startsWith('ui_') ? { ok: true } : { ok: false, error: 'no_fixture' });
      messages.push({ role: 'tool', tool_call_id: call.id, content: JSON.stringify(refs.wrap(result)) });
    }
  }
  // يُفحص قبل الطباعة: بعدها تصبح العلامات مبالغ «د.ع» مشروعة.
  const rawAmount = hasRawAmount(reply);
  const shown = refs.render(reply);
  reply = shown.text;
  const fails = judge(c, reply, called, nav);
  if (shown.unknown.length) fails.push(`علامة مبلغ مجهولة ${shown.unknown.join(' ')}`);
  if (rawAmount) fails.push('كتب مبلغاً بنفسه بدل العلامة');
  return { key: c.case_key, category: c.category, pass: fails.length === 0, fails, reply, called, nav, ms: Date.now() - t0 };
}

// ------------------------------------------------------------ التشغيل
const results: CaseResult[] = [];
for (const c of cases) {
  try {
    results.push(target === 'guide-assistant' ? await runLegacy(c) : await runNew(c));
  } catch (e) {
    results.push({ key: c.case_key, category: c.category, pass: false, fails: [`خطأ: ${e}`], reply: '', called: [], nav: null, ms: 0 });
  }
  const r = results.at(-1)!;
  console.error(`${r.pass ? '✓' : '✗'} ${r.key} ${r.fails.join(' | ')}`);
}

const byCat = new Map<string, { pass: number; total: number }>();
for (const r of results) {
  const x = byCat.get(r.category) ?? { pass: 0, total: 0 };
  x.total++;
  if (r.pass) x.pass++;
  byCat.set(r.category, x);
}
const passed = results.filter((r) => r.pass).length;
console.log(JSON.stringify({
  target,
  passed,
  total: results.length,
  by_category: Object.fromEntries(byCat),
  avg_ms: Math.round(results.reduce((a, r) => a + r.ms, 0) / Math.max(results.length, 1)),
  per_case: results,
}, null, 1));
