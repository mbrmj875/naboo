/**
 * مساعد نابو الجديد — دالة `assistant-chat` (خطة المساعد 4.1، م1-1، م1-11، م1-12ج).
 *
 * بلا حالة: كل طلب خطوة نموذج واحدة. الهاتف يحتفظ بالمحادثة وينفّذ الأدوات على
 * قاعدته المحلية، ثم يرسل الخطوة التالية. الخادم يتحقق من الهوية والمحل والحصة،
 * ويبث الرد، ويكتب سطراً منظَّفاً واحداً لكل سؤال في `assistant_turns`.
 *
 * العمليات:
 *  - op: "step"   خطوة نموذج. البث افتراضي (`stream: false` للويب والتقييم).
 *  - op: "signal" إشارات السلوك لأسئلة سابقة (4.7ب).
 *
 * أحداث البث: text، tool_call، usage، done، error (4.1).
 * الكود كله خلف `config.assistant` و`assistant_tenant_settings.v2_enabled`.
 */

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  addCost,
  type Budget,
  checkBudget,
  isTrialTenant,
  policyFor,
  recordTurnStep,
  renewsOn,
} from '../_shared/assistant_meter.ts';
import { addUsage, chat, chatStream, type ChatResult, costMicroUsd, LlmError, MODELS, type Usage, ZERO_USAGE } from '../_shared/llm.ts';
import { namesFromToolResults, sanitizeForLog, staffNamesFromToolResults } from '../_shared/sanitize.ts';
import { type Article, knowledgeMessage, lastUserText, pickArticles } from './knowledge.ts';
import { buildMessages, FollowupStreamFilter, isGuideOnly, PROMPT_VERSION, SCREEN_ITEM_KINDS, type ScreenItem, splitFollowups } from './prompt.ts';
import { knownToolNames, toolDefsFor } from './tools.ts';
import { lastSearchDebug } from './car_spec.ts';
import { carPhotoMessages, cleanCarImages, parseCarPhoto } from './car_photo.ts';
import { runServerTool, SERVER_TOOLS } from './server_tools.ts';
import { type Lesson, MAX_RULES, notesMessage, pickNotes } from './lessons.ts';
import { cleanConversation, type InMsg, MAX_TOOLS_PER_STEP, parseArgs } from './conversation.ts';

// ------------------------------------------------------------------ الحدود (4.1)
const RATE_LIMIT_PER_MIN = 20;
const TEMPERATURE = 0.2;

const UI_TOOLS = new Set(['ui_describe', 'ui_navigate', 'ui_highlight', 'ui_guide', 'ui_start_tour']);

// ------------------------------------------------------------------ أدوات مساعدة
function corsHeaders(req: Request): HeadersInit {
  return {
    'Access-Control-Allow-Origin': req.headers.get('Origin') ?? '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'Content-Type': 'application/json; charset=utf-8' },
  });
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** يقرأ حمولة JWT بعد أن تحقق `getUser` من صحتها. */
function jwtClaims(authHeader: string): Record<string, unknown> {
  try {
    const token = authHeader.replace(/^Bearer\s+/i, '');
    const part = token.split('.')[1] ?? '';
    const b64 = part.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(part.length / 4) * 4, '=');
    return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
  } catch {
    return {};
  }
}

/** نفس منطق `app_current_tenant_id()` في القاعدة: tenant_id ثم sub. */
function tenantFrom(claims: Record<string, unknown>, userId: string): string {
  const t = String(claims.tenant_id ?? '').trim();
  return t || userId;
}

const rate = new Map<string, { n: number; at: number }>();
function allowRate(userId: string): boolean {
  const now = Date.now();
  const cur = rate.get(userId);
  if (!cur || now - cur.at > 60_000) {
    rate.set(userId, { n: 1, at: now });
    return true;
  }
  if (cur.n >= RATE_LIMIT_PER_MIN) return false;
  cur.n++;
  return true;
}

// ------------------------------------------------------------------ ذاكرة مؤقتة لكل نسخة
type Cached<T> = { v: T; at: number };
const cache = new Map<string, Cached<unknown>>();
async function cached<T>(key: string, ttlMs: number, load: () => Promise<T>): Promise<T> {
  const c = cache.get(key) as Cached<T> | undefined;
  if (c && Date.now() - c.at < ttlMs) return c.v;
  const v = await load();
  cache.set(key, { v, at: Date.now() });
  return v;
}

type Rollout = { kill: boolean; rollout: string };
type TenantSettings = { v2: boolean; demo: boolean };

async function loadRollout(admin: SupabaseClient): Promise<Rollout> {
  return await cached('rollout', 60_000, async () => {
    const { data } = await admin.from('app_remote_config').select('config').eq('id', 1).maybeSingle();
    const a = ((data?.config as Record<string, unknown> | undefined)?.assistant ?? {}) as Record<string, unknown>;
    return { kill: a.kill === true, rollout: String(a.v2_rollout ?? 'off') };
  });
}

async function loadTenantSettings(admin: SupabaseClient, tenantId: string): Promise<TenantSettings> {
  return await cached(`ts:${tenantId}`, 60_000, async () => {
    const { data } = await admin
      .from('assistant_tenant_settings')
      .select('v2_enabled,is_demo')
      .eq('tenant_id', tenantId)
      .maybeSingle();
    return { v2: data?.v2_enabled === true, demo: data?.is_demo === true };
  });
}

/** الدروس الفعّالة: عامة أو خاصة بهذا المحل. تتغير مرة في الليلة على الأكثر (م5-6). */
async function loadLessons(admin: SupabaseClient, tenantId: string): Promise<Lesson[]> {
  return await cached(`lessons:${tenantId}`, 10 * 60_000, async () => {
    const { data, error } = await admin
      .from('assistant_lessons')
      .select('id,kind,topic,trigger_text,body')
      .eq('audience', 'app')
      .eq('status', 'active')
      .or(`tenant_id.is.null,tenant_id.eq.${tenantId}`)
      .order('activated_at', { ascending: true })
      .limit(400);
    if (error) return [];
    return (data ?? []).filter((r) => String(r.body ?? '').trim()) as Lesson[];
  });
}

// ------------------------------------------------------------------ الإشارات (4.7ب)
const SIGNAL_COLUMNS = new Set([
  's_rephrased',
  's_closed_fast',
  's_guide_started',
  's_guide_done',
  's_guide_abandon_step',
  's_action_kind',
  's_action_saved',
  's_thumb',
  's_user_corrected',
]);

/** ذاكرة المحل: كل الصفوف (40 كحد أقصى)، أقدمها أولاً. */
async function loadMemory(admin: SupabaseClient, tenantId: string): Promise<string[]> {
  return await cached(`mem:${tenantId}`, 30_000, async () => {
    const { data } = await admin
      .from('assistant_shop_memory')
      .select('text')
      .eq('tenant_id', tenantId)
      .order('created_at', { ascending: true })
      .limit(40);
    return (data ?? []).map((r) => String(r.text ?? '')).filter(Boolean);
  });
}

/** المقالات المنشورة. تُحمَّل كلها (قليلة) ويُختار منها محلياً. */
async function loadArticles(admin: SupabaseClient): Promise<Article[]> {
  return await cached('articles', 60_000, async () => {
    const { data } = await admin
      .from('assistant_knowledge')
      .select('id,kind,title,body,keywords')
      .eq('published', true)
      // ق89: مقال المجيب للزبائن لا يصل المساعد الداخلي.
      .in('audience', ['app', 'both'])
      .limit(300);
    return (data ?? []) as Article[];
  });
}

async function handleSignals(req: Request, admin: SupabaseClient, tenantId: string, body: InMsg): Promise<Response> {
  const items = Array.isArray(body.signals) ? (body.signals as InMsg[]).slice(0, 30) : [];
  let applied = 0;
  for (const it of items) {
    const turnId = String(it.turn_id ?? '');
    if (!UUID_RE.test(turnId)) continue;
    const patch: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(it)) {
      if (!SIGNAL_COLUMNS.has(k)) continue;
      if (k === 's_guide_abandon_step' || k === 's_thumb') {
        const n = Number(v);
        if (Number.isInteger(n) && Math.abs(n) < 1000) patch[k] = n;
      } else if (k === 's_action_kind') {
        patch[k] = String(v).slice(0, 40);
      } else {
        patch[k] = v === true;
      }
    }
    if (typeof it.user_correction === 'string' && it.user_correction.trim()) {
      patch.user_correction = sanitizeForLog(it.user_correction, { maxLength: 1000 });
      patch.s_user_corrected = true;
    }
    if (Object.keys(patch).length === 0) continue;
    const { error, count } = await admin
      .from('assistant_turns')
      .update(patch, { count: 'exact' })
      .eq('id', turnId)
      .eq('tenant_id', tenantId);
    if (!error && (count ?? 0) > 0) applied++;
  }
  return json(req, { ok: true, applied });
}

// ------------------------------------------------------------------ الخطوة
type StepInput = {
  threadId: string;
  turnId: string;
  step: number;
  routeId: string | null;
  routeTitle: string | null;
  roleKey: string;
  isOwner: boolean;
  appVersion: string | null;
  branchName: string | null;
  tools: string[];
  stream: boolean;
  screenItem: ScreenItem | null;
};

/** العنصر المفتوح على الشاشة (ق67): نوع من قائمة ثابتة ومعرّف رقمي فقط. */
function parseScreenItem(kind: unknown, id: unknown): ScreenItem | null {
  const k = String(kind ?? '');
  const n = Number(id);
  if (!SCREEN_ITEM_KINDS.has(k) || !Number.isInteger(n) || n <= 0 || n > 1e12) return null;
  return { kind: k as ScreenItem['kind'], id: n };
}

function parseStep(body: InMsg): StepInput | string {
  const threadId = String(body.thread_id ?? '');
  const turnId = String(body.turn_id ?? '');
  if (!UUID_RE.test(threadId) || !UUID_RE.test(turnId)) return 'bad_ids';
  const step = Number(body.step ?? 0);
  if (!Number.isInteger(step) || step < 0 || step > 20) return 'bad_step';
  const s = (v: unknown, n: number) => {
    const t = String(v ?? '').trim();
    return t ? t.slice(0, n) : null;
  };
  return {
    threadId,
    turnId,
    step,
    routeId: s(body.route_id, 120),
    routeTitle: s(body.route_title, 80),
    roleKey: s(body.role_key, 40) ?? 'staff',
    isOwner: body.is_owner === true,
    appVersion: s(body.app_version, 40),
    branchName: s(body.branch_name, 80),
    screenItem: parseScreenItem(body.context_kind, body.context_id),
    tools: knownToolNames(body.tools),
    stream: body.stream !== false,
  };
}

const enc = new TextEncoder();
function sse(event: string, data: unknown): Uint8Array {
  return enc.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method === 'GET') {
    return json(req, { ok: true, service: 'assistant-chat', prompt: PROMPT_VERSION, model: MODELS.fast });
  }
  if (req.method !== 'POST') return json(req, { ok: false, error: 'method_not_allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !anon || !service) return json(req, { ok: false, error: 'server_misconfigured' }, 500);

  const authHeader = req.headers.get('Authorization') ?? '';
  const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) return json(req, { ok: false, error: 'unauthorized' }, 401);
  const userId = userData.user.id;
  const tenantId = tenantFrom(jwtClaims(authHeader), userId);
  const admin = createClient(url, service);

  let body: InMsg;
  try {
    body = await req.json();
  } catch {
    return json(req, { ok: false, error: 'invalid_json' }, 400);
  }

  // التشغيل: مفتاح الإيقاف، ثم الإطلاق العام أو لكل محل.
  const [rollout, ts] = await Promise.all([loadRollout(admin), loadTenantSettings(admin, tenantId)]);
  const enabled = !rollout.kill &&
    (rollout.rollout === 'all' || (rollout.rollout === 'tenants' && ts.v2));
  if (!enabled) return json(req, { ok: false, error: 'disabled' }, 403);

  const op = String(body.op ?? 'step');
  if (op === 'signal') return await handleSignals(req, admin, tenantId, body);
  // بذرة دليل السيارات (م1-15): من المحل النموذجي فقط، سيارة واحدة لكل نداء، بنفس مسار البحث.
  if (op === 'seed_car') {
    if (!ts.demo) return json(req, { ok: false, error: 'forbidden' }, 403);
    const r = await runServerTool('car_spec', (body.car ?? {}) as Record<string, unknown>, {
      admin, tenantId, userId, roleKey: 'owner', routeId: null, searchTimeoutMs: 55_000,
    });
    await addCost(admin, tenantId, 'app', costMicroUsd(r.usage), { searches: r.usedWeb ? 1 : 0 });
    return json(req, { ok: true, result: r.result, used_web: r.usedWeb, cost_micro_usd: costMicroUsd(r.usage), debug: lastSearchDebug });
  }
  // م4-13: قراءة اللوحة والعدّاد للمراجعة قبل فتح البطاقة. قراءة فقط، بلا أدوات.
  if (op === 'read_car_photo') {
    if (!allowRate(userId)) return json(req, { ok: false, error: 'rate_limited' }, 429);
    const imgs = cleanCarImages(body.images);
    if (typeof imgs === 'string') return json(req, { ok: false, error: { code: 'bad_request', detail: imgs } }, 400);
    const trial = ts.demo ? false : await cached(`trial:${tenantId}`, 10 * 60_000, () => isTrialTenant(admin, tenantId));
    const budget: Budget = await checkBudget(admin, tenantId, 'app', trial);
    if (budget.mode === 'exhausted') return json(req, { ok: false, error: { code: 'budget_exhausted' } }, 402);
    if (!policyFor(budget.mode).images) return json(req, { ok: false, error: { code: 'images_disabled' } }, 400);
    try {
      const r = await chat({ messages: carPhotoMessages(imgs), maxTokens: 120, temperature: 0, json: true }, 30_000);
      await addCost(admin, tenantId, 'app', costMicroUsd(r.usage), { images: 1, searches: 0 });
      return json(req, { ok: true, read: parseCarPhoto(r.text) });
    } catch (e) {
      const code = e instanceof LlmError && e.code === 'timeout' ? 'timeout' : 'upstream';
      return json(req, { ok: false, error: { code } }, 502);
    }
  }
  if (op !== 'step') return json(req, { ok: false, error: 'bad_op' }, 400);

  if (!allowRate(userId)) return json(req, { ok: false, error: 'rate_limited' }, 429);

  const input = parseStep(body);
  if (typeof input === 'string') return json(req, { ok: false, error: input }, 400);

  // الحصة (ق15، ق51، ق54).
  const trial = ts.demo ? false : await cached(`trial:${tenantId}`, 10 * 60_000, () => isTrialTenant(admin, tenantId));
  const budget: Budget = await checkBudget(admin, tenantId, 'app', trial);
  const budgetInfo = { mode: budget.mode, pct: budget.pct, renews_on: renewsOn() };
  if (budget.mode === 'exhausted') {
    const err = { code: 'budget_exhausted', budget: budgetInfo };
    if (!input.stream) return json(req, { ok: false, error: err }, 402);
    return new Response(`event: error\ndata: ${JSON.stringify(err)}\n\n`, {
      headers: { ...corsHeaders(req), 'Content-Type': 'text/event-stream; charset=utf-8' },
    });
  }
  const policy = policyFor(budget.mode);

  const conv = cleanConversation(body.messages, policy.images);
  if (typeof conv === 'string') {
    const code = conv === 'images_disabled' ? 'images_disabled' : 'bad_request';
    return json(req, { ok: false, error: { code, detail: conv } }, 400);
  }

  const guideOnly = isGuideOnly(input.tools);
  const [lessons, memory, articles] = await Promise.all([
    loadLessons(admin, tenantId),
    guideOnly ? Promise.resolve([] as string[]) : loadMemory(admin, tenantId),
    loadArticles(admin),
  ]);
  // المكتبة تُختار بأول خطوة فقط من السؤال؛ الخطوات اللاحقة تعيد نفس الاختيار من نفس النص.
  const picked = pickArticles(articles, lastUserText(conv.messages));
  const knowledgeUsed = picked.map((a) => ({ id: a.id, kind: a.kind, title: a.title }));
  // القواعد كلها (25 كحد)، والملاحظات الأقرب للسؤال. الإرشاد فقط لا يأخذ الملاحظات.
  const rules = lessons.filter((l) => l.kind === 'rule').slice(0, MAX_RULES);
  const notes = guideOnly ? [] : pickNotes(lessons, lastUserText(conv.messages));
  const lessonIds = [...rules, ...notes].map((l) => l.id);
  const messages = buildMessages(
    {
      isOwner: input.isOwner,
      roleKey: input.roleKey,
      guideOnly,
      routeId: input.routeId,
      routeTitle: input.routeTitle,
      branchName: input.branchName,
      screenItem: guideOnly ? null : input.screenItem,
      economy: budget.mode === 'economy',
    },
    rules.map((l) => l.body),
    conv.messages,
    [knowledgeMessage(memory, picked), notesMessage(notes)].filter(Boolean).join('\n\n'),
  );
  // الخطوة الأخيرة المسموحة: بلا أدوات، فيكتب النموذج جواباً نهائياً.
  const lastStep = input.step >= policy.maxSteps - 1;
  // أدوات الخادم لا يعرفها الهاتف، فتُعلن هنا لمستوى «كامل» فقط.
  const tools = toolDefsFor(guideOnly ? input.tools : [...input.tools, ...SERVER_TOOLS]);
  const opts = {
    messages,
    maxTokens: policy.maxTokens,
    temperature: TEMPERATURE,
    tools,
    toolChoice: (lastStep ? 'none' : 'auto') as 'none' | 'auto',
  };

  const names = namesFromToolResults(conv.toolResults);
  const staff = staffNamesFromToolResults(conv.toolResults);
  const startedAt = Date.now();

  /** الحساب والتسجيل بعد اكتمال الخطوة. لا يرمي خطأ أبداً. */
  const finalize = async (r: ChatResult | null, finish: string, side: { usage: Usage; web: number } = { usage: ZERO_USAGE, web: 0 }) => {
    const usage = addUsage(r?.usage ?? ZERO_USAGE, side.usage);
    const cost = costMicroUsd(usage);
    const final = finish !== 'tool_calls';
    const answer = r ? splitFollowups(r.text).text : '';
    await Promise.all([
      addCost(admin, tenantId, 'app', cost, { images: conv.hasImage && input.step === 0 ? 1 : 0, searches: side.web }),
      recordTurnStep(admin, {
        turnId: input.turnId,
        threadId: input.threadId,
        tenantId,
        userId,
        channel: 'app',
        roleKey: input.roleKey,
        isOwner: input.isOwner,
        routeId: input.routeId,
        appVersion: input.appVersion,
        questionClean: sanitizeForLog(conv.question, { names, staff }),
        answerClean: final ? sanitizeForLog(answer, { names, staff, maxLength: 4000 }) : null,
        // ذ9: في أول خطوة تُذكر الأدوات التي نتائجها من رسائل سابقة، ليعرف الحَكَم مصدر الجواب.
        tools: input.step === 0
          ? [...conv.priorTools.slice(0, 8).map((name) => ({ name, ok: true, prior: true })), ...conv.stepTools]
          : conv.stepTools,
        usage,
        costMicroUsd: cost,
        latencyMs: Date.now() - startedAt,
        model: r?.model ?? MODELS.fast,
        finish,
        budgetMode: budget.mode,
        hasImage: conv.hasImage,
        usedWeb: side.web > 0,
        lessonIds,
      }),
    ]);
  };

  const shape = (r: ChatResult) => {
    const calls = lastStep ? [] : r.toolCalls.slice(0, MAX_TOOLS_PER_STEP);
    const finish = calls.length > 0 ? 'tool_calls' : lastStep && r.toolCalls.length > 0 ? 'limit' : r.finish === 'length' ? 'limit' : 'stop';
    return { calls, finish, split: splitFollowups(r.text) };
  };

  /** ينفّذ أدوات الخادم ويرفق نتائجها بنداءاتها. */
  const runServer = async (calls: { id: string; name: string; arguments: string }[]) => {
    let side = { usage: ZERO_USAGE, web: 0 };
    const out = [];
    for (const c of calls) {
      const args = parseArgs(c.arguments);
      if (!SERVER_TOOLS.has(c.name)) {
        out.push({ id: c.id, name: c.name, arguments: args });
        continue;
      }
      const r = await runServerTool(c.name, args, {
        admin,
        tenantId,
        userId,
        roleKey: input.roleKey,
        routeId: input.routeId,
        createdBy: input.isOwner ? 'المالك' : 'موظف',
      });
      if (c.name === 'memory_save') cache.delete(`mem:${tenantId}`);
      side = { usage: addUsage(side.usage, r.usage), web: side.web + (r.usedWeb ? 1 : 0) };
      out.push({ id: c.id, name: c.name, arguments: args, result: r.result });
    }
    return { out, side };
  };

  // ----------------------------------------------------------- بلا بث
  if (!input.stream) {
    try {
      const r = await chat(opts, 45_000);
      const { calls, finish, split } = shape(r);
      const server = await runServer(calls);
      await finalize(r, finish, server.side);
      return json(req, {
        ok: true,
        text: split.text,
        tool_calls: server.out,
        finish,
        followups: finish === 'tool_calls' ? [] : split.followups,
        knowledge: knowledgeUsed,
        usage: { in: r.usage.miss + r.usage.hit, cached: r.usage.hit, out: r.usage.out },
        budget: budgetInfo,
      });
    } catch (e) {
      await finalize(null, 'error');
      const code = e instanceof LlmError && e.code === 'timeout' ? 'timeout' : 'upstream';
      return json(req, { ok: false, error: { code } }, 502);
    }
  }

  // ----------------------------------------------------------- بث
  const stream = new ReadableStream<Uint8Array>({
    async start(ctrl) {
      const filter = new FollowupStreamFilter();
      let closed = false;
      const send = (ev: string, data: unknown) => {
        if (closed) return;
        try {
          ctrl.enqueue(sse(ev, data));
        } catch {
          closed = true;
        }
      };
      try {
        const r = await chatStream(opts, (delta) => {
          const out = filter.push(delta);
          if (out) send('text', { delta: out });
        });
        const tail = filter.flush();
        if (tail) send('text', { delta: tail });
        const { calls, finish, split } = shape(r);
        const server = await runServer(calls);
        for (const c of server.out) send('tool_call', c);
        send('usage', { in: r.usage.miss + r.usage.hit, cached: r.usage.hit, out: r.usage.out });
        send('done', { finish, followups: finish === 'tool_calls' ? [] : split.followups, knowledge: knowledgeUsed, budget: budgetInfo });
        await finalize(r, finish, server.side);
      } catch (e) {
        const code = e instanceof LlmError && e.code === 'timeout' ? 'timeout' : 'upstream';
        send('error', { code });
        await finalize(null, 'error');
      } finally {
        closed = true;
        try {
          ctrl.close();
        } catch { /* أُغلق من الطرف الآخر */ }
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders(req),
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache',
      'X-Accel-Buffering': 'no',
    },
  });
});
