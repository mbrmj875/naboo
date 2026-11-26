// مجموعة الاختبار الثابتة داخل الخادم (4.7هـ، م5-5).
//
// نفس فحص tool/assistant_eval.ts بلا حَكَم: الأداة المطلوبة والممنوعة، النص
// المطلوب والممنوع، والمسار. الفرق أنه يعمل داخل الدالة بلا HTTP، ويأخذ الدروس
// صراحة، فيُقارن «بدون الدرس» و«معه» على نفس الحالات.

import { addUsage, type ChatOptions, type ChatResult, type Usage, ZERO_USAGE } from '../_shared/llm.ts';
import { buildMessages, splitFollowups } from './prompt.ts';
import { toolDefsFor } from './tools.ts';

export type Expect = {
  must_call?: string[];
  must_call_any?: string[];
  must_not_call?: string[];
  must_include?: string[];
  must_include_any?: string[];
  must_not_include?: string[];
  nav_route?: string;
};

export type EvalCase = {
  case_key: string;
  category: string;
  profile: string;
  question: string;
  fixtures: Record<string, unknown>;
  expect: Expect;
};

export type CaseResult = {
  key: string;
  category: string;
  pass: boolean;
  fails: string[];
  called: string[];
  nav: string | null;
};

// ------------------------------------------------------------ الأدوات لكل ملف تعريف
const UI_TOOLS = ['ui_describe', 'ui_navigate', 'ui_highlight', 'ui_guide', 'ui_start_tour'];
const READ_TOOLS = [
  'stock_search',
  'stock_low',
  'product_detail',
  'oil_card_find',
  'car_history',
  'customer_find',
  'car_spec',
];
const REPORT_TOOLS = ['sales_summary', 'top_products', 'ratings_summary', 'staff_status', 'wa_status'];
const MONEY_TOOLS = ['debts_summary', 'cash_summary'];
const EXEC_TOOLS = [
  'prepare_oil_card',
  'prepare_car_wash',
  'prepare_customer',
  'prepare_product',
  'prepare_expense',
  'propose_price_change',
  'propose_stock_adjust',
];

export function toolsFor(profile: string): string[] {
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

export function judgeCase(e: Expect, reply: string, called: string[], nav: string | null): string[] {
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
  /** الجواب كما يراه المستخدم، والعلامات المجهولة (تظهر «—» في الهاتف). */
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

export type ChatFn = (o: ChatOptions) => Promise<ChatResult>;

export type RunOpts = {
  chat: ChatFn;
  /** دروس rule كما تُحقن في التعليمات. */
  rules: string[];
  /** دروس qa/screen_note المسترجعة لهذا السؤال (نص جاهز)، أو دالة تختارها. */
  notesFor?: (question: string) => string;
  temperature?: number;
  maxSteps?: number;
};

/** يشغّل حالة واحدة كما يشغّلها الهاتف: خطوات حتى 5، ونتائج الأدوات من fixtures. */
export async function runCase(c: EvalCase, o: RunOpts): Promise<CaseResult & { usage: Usage }> {
  const refs = new MoneyRefs();
  const tools = toolsFor(c.profile);
  const guideOnly = tools.length > 0 && tools.every((t) => t.startsWith('ui_'));
  const conv: Record<string, unknown>[] = [{ role: 'user', content: c.question }];
  const called: string[] = [];
  let reply = '';
  let nav: string | null = null;
  let usage = ZERO_USAGE;
  const maxSteps = o.maxSteps ?? 5;
  for (let s = 0; s < maxSteps; s++) {
    const last = s >= maxSteps - 1;
    const r = await o.chat({
      messages: buildMessages(
        {
          isOwner: c.profile === 'owner',
          roleKey: c.profile === 'owner' ? 'owner' : 'staff',
          guideOnly,
          routeId: 'app_oil_services_log',
          economy: false,
        },
        o.rules,
        conv,
        o.notesFor?.(c.question) ?? '',
      ),
      maxTokens: 900,
      temperature: o.temperature ?? 0.2,
      tools: toolDefsFor(tools),
      toolChoice: last ? 'none' : 'auto',
    });
    usage = addUsage(usage, r.usage);
    reply += splitFollowups(r.text).text;
    const calls = last ? [] : r.toolCalls.slice(0, 3);
    if (calls.length === 0) break;
    conv.push({
      role: 'assistant',
      content: r.text,
      tool_calls: calls.map((x) => ({
        id: x.id,
        type: 'function',
        function: { name: x.name, arguments: x.arguments },
      })),
    });
    for (const call of calls) {
      called.push(call.name);
      let args: Record<string, unknown> = {};
      try {
        args = JSON.parse(call.arguments || '{}');
      } catch { /* وسائط تالفة */ }
      if (call.name === 'ui_navigate') nav = String(args.route_id ?? '');
      const result = !tools.includes(call.name)
        ? { ok: false, error: 'forbidden' }
        : c.fixtures[call.name] ?? (call.name.startsWith('ui_') ? { ok: true } : { ok: false, error: 'no_fixture' });
      conv.push({ role: 'tool', tool_call_id: call.id, content: JSON.stringify(refs.wrap(result)) });
    }
  }
  const rawAmount = hasRawAmount(reply);
  const shown = refs.render(reply);
  const fails = judgeCase(c.expect, shown.text, called, nav);
  if (shown.unknown.length) fails.push(`علامة مبلغ مجهولة ${shown.unknown.join(' ')}`);
  if (rawAmount) fails.push('كتب مبلغاً بنفسه بدل العلامة');
  return { key: c.case_key, category: c.category, pass: fails.length === 0, fails, called, nav, usage };
}

/** يشغّل الحالات بتوازٍ محدود. الخطأ يُحسب فشلاً للحالة لا للتشغيل. */
export async function runCases(cases: EvalCase[], o: RunOpts, concurrency = 10) {
  const out: (CaseResult & { usage: Usage })[] = new Array(cases.length);
  let i = 0;
  const worker = async () => {
    while (i < cases.length) {
      const k = i++;
      const c = cases[k];
      try {
        out[k] = await runCase(c, o);
      } catch (e) {
        out[k] = {
          key: c.case_key,
          category: c.category,
          pass: false,
          fails: [`خطأ: ${String(e).slice(0, 120)}`],
          called: [],
          nav: null,
          usage: ZERO_USAGE,
        };
      }
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, cases.length) }, worker));
  return out;
}
