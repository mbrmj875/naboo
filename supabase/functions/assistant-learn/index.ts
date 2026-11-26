// assistant-learn — حلقة التعلّم الليلية (4.7ج، م5-2، م5-4، م5-5، م5-7).
//
// تستدعيها pg_cron بمفتاح CRON_SECRET فقط:
//   {"op":"nightly"}   23:30 عالمي: الحَكَم على أسئلة اليوم، ثم كتابة الدروس المرشحة،
//                      ودمج القواعد الزائدة، وتقاعد الدروس الضارة.
//   {"op":"evaluate"}  كل 10 دقائق: إن وُجد مرشح، اختبار الأمان على الحالات الستين
//                      بدونه ومعه، ثم النشر أو الرفض. بلا مرشح = استعلام واحد فقط.
//                      مرشح مجيب واتساب يُختبر على حالات المجيب الـ24 (م6-14).
//   {"op":"eval_responder"}  تشغيل حالات المجيب الـ24 بالدروس الحالية، ونتيجتها في
//                      assistant_eval_runs بهدف whatsapp-responder.
//
// الحَكَم وكتابة الدروس يغطيان القناتين: كل قناة بمعاييرها ودروسها (audience).
//
// كل نداء مرحلة واحدة محدودة الوقت، والحالة في القاعدة، فلا يتجاوز حد الدالة.
// الكلفة تُحسب على المحل الوهمي «_learn» حتى تظهر منفصلة عن حصص المحلات.
//
// Deploy: supabase functions deploy assistant-learn --no-verify-jwt
// Secrets: CRON_SECRET، DEEPSEEK_API_KEY

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { addCost } from '../_shared/assistant_meter.ts';
import { addUsage, chat, costMicroUsd, type Usage, ZERO_USAGE } from '../_shared/llm.ts';
import { type EvalCase, runCases } from '../assistant-chat/eval_core.ts';
import { type Lesson, MAX_RULES, notesMessage, pickNotes } from '../assistant-chat/lessons.ts';
import { PROMPT_VERSION } from '../assistant-chat/prompt.ts';
import { type RespCase, type RespResult, runRespCases } from '../whatsapp-cloud-webhook/responder_eval.ts';
import {
  checkLesson,
  clusters,
  type FailedTurn,
  flipped,
  judgeMessages,
  parseLesson,
  parseVerdict,
  safetyDecision,
  shouldRetire,
  type TurnForJudge,
  writerMessages,
} from './learn.ts';

const LEARN_TENANT = '_learn';
const JUDGE_LIMIT = 60;
const MAX_NEW_LESSONS = 3;
const FAIL_FILTER =
  'j_answered.eq.false,j_grounded.eq.false,j_perm_ok.eq.false,j_no_invention.eq.false,s_user_corrected.eq.true';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

async function pool<T, R>(items: T[], n: number, fn: (x: T) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) {
      const k = i++;
      out[k] = await fn(items[k]);
    }
  }));
  return out;
}

// ------------------------------------------------------------------ الحَكَم (م5-2)
type Channel = 'app' | 'whatsapp';
const CHANNELS: Channel[] = ['app', 'whatsapp'];

async function judge(admin: SupabaseClient): Promise<{ judged: number; skipped: number; usage: Usage }> {
  const turns: TurnForJudge[] = [];
  for (const channel of CHANNELS) {
    const { data, error } = await admin.rpc('assistant_pick_for_judging', { p_limit: JUDGE_LIMIT, p_channel: channel });
    if (error) throw new Error(`pick ${channel}: ${error.message}`);
    for (const t of (data ?? []) as TurnForJudge[]) turns.push({ ...t, channel });
  }
  let usage = ZERO_USAGE;
  let judged = 0;
  await pool(turns, 6, async (t) => {
    try {
      const r = await chat({ messages: judgeMessages(t), maxTokens: 220, temperature: 0, json: true }, 30_000);
      usage = addUsage(usage, r.usage);
      const v = parseVerdict(r.text);
      if (!v) return;
      const { error: e } = await admin.from('assistant_turns').update({
        judged_at: new Date().toISOString(),
        j_answered: v.answered,
        j_grounded: v.grounded,
        j_perm_ok: v.perm_ok,
        j_no_invention: v.no_invention,
        j_topic: v.topic,
        j_note: v.note || null,
      }).eq('id', t.id).eq('tenant_id', t.tenant_id);
      if (!e) judged++;
    } catch { /* يُعاد غداً */ }
  });
  return { judged, skipped: turns.length - judged, usage };
}

// ------------------------------------------------------------------ الدروس المرشحة (م5-4)
async function propose(admin: SupabaseClient): Promise<{ proposed: number; rejected: number; usage: Usage }> {
  let out = { proposed: 0, rejected: 0, usage: ZERO_USAGE };
  for (const channel of CHANNELS) {
    const r = await proposeFor(admin, channel);
    out = { proposed: out.proposed + r.proposed, rejected: out.rejected + r.rejected, usage: addUsage(out.usage, r.usage) };
  }
  return out;
}

async function proposeFor(
  admin: SupabaseClient,
  channel: Channel,
): Promise<{ proposed: number; rejected: number; usage: Usage }> {
  const since = new Date(Date.now() - 14 * 86_400_000).toISOString();
  const { data, error } = await admin
    .from('assistant_turns')
    .select('id,tenant_id,j_topic,question_clean,answer_clean,j_note,user_correction,created_at,app_version')
    .eq('channel', channel)
    .not('judged_at', 'is', null)
    .gte('created_at', since)
    .or(FAIL_FILTER)
    .order('created_at', { ascending: false })
    .limit(500);
  if (error) throw new Error(`failed turns: ${error.message}`);
  // حالات الاختبار (app_version = eval) ليست أخطاء حقيقية. واتساب بلا إصدار (null).
  const failed: FailedTurn[] = (data ?? []).filter((r) => r.app_version !== 'eval').map((r) => ({
    id: r.id,
    tenant_id: r.tenant_id,
    topic: r.j_topic ?? 'other',
    question: r.question_clean,
    answer: r.answer_clean,
    note: r.j_note,
    correction: r.user_correction,
    created_at: r.created_at,
  }));
  const weekAgo = new Date(Date.now() - 7 * 86_400_000).toISOString();
  const { data: recent } = await admin.from('assistant_lessons').select('topic').eq('audience', channel).gte(
    'created_at',
    weekAgo,
  );
  const skip = new Set((recent ?? []).map((r) => String(r.topic)));

  let usage = ZERO_USAGE;
  let proposed = 0;
  let rejected = 0;
  for (const c of clusters(failed, skip).slice(0, MAX_NEW_LESSONS)) {
    try {
      const r = await chat(
        { messages: writerMessages(c, channel), maxTokens: 400, temperature: 0.2, json: true },
        30_000,
      );
      usage = addUsage(usage, r.usage);
      const l = parseLesson(r.text);
      if (!l) continue;
      if (channel === 'whatsapp' && l.kind === 'screen_note') l.kind = 'qa';
      const bad = checkLesson(l);
      await admin.from('assistant_lessons').insert({
        audience: channel,
        tenant_id: null,
        kind: l.kind,
        topic: c.topic,
        trigger_text: l.trigger_text,
        body: l.body,
        status: bad ? 'rejected' : 'candidate',
        source_turns: c.turns.length,
        origin: 'learn',
        retired_reason: bad ? `الفحص الآلي: ${bad}` : null,
      });
      if (bad) rejected++;
      else proposed++;
    } catch { /* الموضوع يُعاد غداً */ }
  }
  return { proposed, rejected, usage };
}

// ------------------------------------------------------------------ دمج القواعد (4.7د)
async function mergeRules(admin: SupabaseClient): Promise<{ merged: boolean; usage: Usage }> {
  const { data } = await admin
    .from('assistant_lessons')
    .select('id,body,activated_at')
    .eq('audience', 'app')
    .eq('kind', 'rule')
    .eq('status', 'active')
    .is('tenant_id', null)
    .order('activated_at', { ascending: true });
  const rules = data ?? [];
  if (rules.length <= MAX_RULES) return { merged: false, usage: ZERO_USAGE };
  const { count } = await admin
    .from('assistant_lessons')
    .select('id', { count: 'exact', head: true })
    .eq('status', 'candidate')
    .eq('topic', 'merge');
  if ((count ?? 0) > 0) return { merged: false, usage: ZERO_USAGE };
  const [a, b] = rules;
  const r = await chat({
    messages: [
      {
        role: 'system',
        content:
          'ادمج القاعدتين في قاعدة واحدة بالعربية، 60 كلمة على الأكثر، بلا أي معنى جديد. أرجع JSON: {"body": "..."}',
      },
      { role: 'user', content: `1. ${a.body}\n2. ${b.body}` },
    ],
    maxTokens: 300,
    temperature: 0,
    json: true,
  }, 30_000);
  let body = '';
  try {
    body = String(JSON.parse(r.text.match(/\{[\s\S]*\}/)?.[0] ?? '{}').body ?? '');
  } catch { /* رد تالف: لا دمج الليلة */ }
  const draft = parseLesson(JSON.stringify({ kind: 'rule', trigger_text: 'دمج', body }));
  if (!draft || checkLesson(draft)) return { merged: false, usage: r.usage };
  await admin.from('assistant_lessons').insert({
    audience: 'app',
    kind: 'rule',
    topic: 'merge',
    trigger_text: 'دمج',
    body: draft.body,
    status: 'candidate',
    origin: 'learn',
    merged_from: [a.id, b.id],
  });
  return { merged: true, usage: r.usage };
}

// ------------------------------------------------------------------ التقاعد (4.7ج-8)
async function retire(admin: SupabaseClient): Promise<number> {
  const { data, error } = await admin.rpc('assistant_lesson_usage', { p_days: 30 });
  if (error || !data) return 0;
  const rows = data as {
    id: number;
    activated_at: string;
    uses: number;
    judged: number;
    fails: number;
    overall_judged: number;
    overall_fails: number;
  }[];
  const overall = rows.length && rows[0].overall_judged > 0 ? rows[0].overall_fails / rows[0].overall_judged : 1;
  let n = 0;
  for (const u of rows) {
    if (!shouldRetire(u, overall)) continue;
    const { error: e } = await admin.from('assistant_lessons').update({
      status: 'retired',
      retired_at: new Date().toISOString(),
      retired_reason: `تقاعد تلقائي: فشل ${u.fails}/${u.judged} أعلى من المتوسط ${(overall * 100).toFixed(0)}%`,
    }).eq('id', u.id).eq('status', 'active');
    if (!e) n++;
  }
  return n;
}

// ------------------------------------------------------------------ اختبار الأمان (م5-5)
type LessonRow = Lesson & { status: string; merged_from: number[] | null; origin: string };

async function activeLessons(admin: SupabaseClient): Promise<Lesson[]> {
  const { data } = await admin
    .from('assistant_lessons')
    .select('id,kind,topic,trigger_text,body')
    .eq('audience', 'app')
    .eq('status', 'active')
    .is('tenant_id', null)
    .order('activated_at', { ascending: true });
  return (data ?? []) as Lesson[];
}

function optsFor(lessons: Lesson[]) {
  const rules = lessons.filter((l) => l.kind === 'rule').slice(0, MAX_RULES).map((l) => l.body);
  const notes = lessons.filter((l) => l.kind !== 'rule');
  return { rules, notesFor: (q: string) => notesMessage(pickNotes(notes, q)) };
}

/** التاريخ ببغداد: الخط الأساسي يُعاد كل يوم ومع كل تغيير في الدروس أو التعليمات. */
function baselineKey(active: Lesson[]): string {
  const day = new Date(Date.now() + 3 * 3600_000).toISOString().slice(0, 10);
  return `baseline:${PROMPT_VERSION}:${active.map((l) => l.id).sort((a, b) => a - b).join('.')}:${day}`;
}

async function evaluate(admin: SupabaseClient) {
  // 1) مرشح ينتظر؟ بلا مرشح لا كلفة.
  const { data: cand } = await admin
    .from('assistant_lessons')
    .select('id,kind,topic,trigger_text,body,status,merged_from,origin')
    .eq('audience', 'app')
    .eq('status', 'candidate')
    .is('tenant_id', null)
    .or('origin.eq.learn,eval_requested_at.not.is.null')
    .order('created_at', { ascending: true })
    .limit(1);
  const lesson = (cand ?? [])[0] as LessonRow | undefined;
  if (!lesson) return await evaluateResponderLesson(admin);

  const { data: caseRows, error } = await admin
    .from('assistant_eval_cases')
    .select('case_key,category,profile,question,fixtures,expect')
    .eq('audience', 'app')
    .eq('active', true);
  if (error || !caseRows?.length) throw new Error('no eval cases');
  const cases = caseRows as EvalCase[];
  const active = await activeLessons(admin);
  const key = baselineKey(active);
  const runChat = (o: Parameters<typeof chat>[0]) => chat(o, 40_000);

  // 2) الخط الأساسي لليوم (نداء مستقل حتى لا يتجاوز الوقت).
  const { data: baseRow } = await admin
    .from('assistant_eval_runs')
    .select('per_case')
    .eq('note', key)
    .order('id', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!baseRow) {
    const res = await runCases(cases, { chat: runChat, ...optsFor(active) }, 12);
    const usage = res.reduce((a, r) => addUsage(a, r.usage), ZERO_USAGE);
    await admin.from('assistant_eval_runs').insert({
      target: 'assistant-learn',
      model: 'deepseek',
      passed: res.filter((r) => r.pass).length,
      total: res.length,
      per_case: res.map((r) => ({ key: r.key, pass: r.pass, fails: r.fails })),
      note: key,
    });
    await addCost(admin, LEARN_TENANT, 'app', costMicroUsd(usage));
    return { stage: 'baseline', passed: res.filter((r) => r.pass).length, total: res.length };
  }
  const baseline = baseRow.per_case as { key: string; pass: boolean }[];

  // 3) مع الدرس: القاعدة تُضاف للتعليمات (والمدموجتان تُحذفان)، والملاحظة للاسترجاع.
  const merged = new Set(lesson.merged_from ?? []);
  const withSet = [...active.filter((l) => !merged.has(l.id)), lesson];
  const withOpts = { chat: runChat, ...optsFor(withSet) };
  const res = await runCases(cases, withOpts, 12);
  let usage = res.reduce((a, r) => addUsage(a, r.usage), ZERO_USAGE);

  const flips = flipped(baseline, res);
  const confirm = new Map<string, { withPass: boolean; basePass: boolean }>();
  if (flips.length > 0 && flips.length <= 6) {
    const re = cases.filter((c) => flips.includes(c.case_key));
    const [w, b] = await Promise.all([
      runCases(re, withOpts, 6),
      runCases(re, { chat: runChat, ...optsFor(active) }, 6),
    ]);
    for (const x of [...w, ...b]) usage = addUsage(usage, x.usage);
    for (const c of re) {
      confirm.set(c.case_key, {
        withPass: w.find((x) => x.key === c.case_key)?.pass ?? false,
        basePass: b.find((x) => x.key === c.case_key)?.pass ?? true,
      });
    }
  }
  const d = safetyDecision(baseline, res, confirm);
  const now = new Date().toISOString();
  await admin.from('assistant_eval_runs').insert({
    target: 'assistant-learn',
    lesson_id: lesson.id,
    model: 'deepseek',
    passed: d.after,
    total: res.length,
    per_case: res.map((r) => ({ key: r.key, pass: r.pass, fails: r.fails })),
    note: `${d.publish ? 'نشر' : 'رفض'}: ${d.reason}`,
  });
  await admin.from('assistant_lessons').update(
    d.publish
      ? { status: 'active', activated_at: now, eval_before: d.before, eval_after: d.after, eval_requested_at: null }
      : {
        status: 'rejected',
        retired_at: now,
        retired_reason: `اختبار الأمان: ${d.reason}`,
        eval_before: d.before,
        eval_after: d.after,
        eval_requested_at: null,
      },
  ).eq('id', lesson.id);
  if (d.publish && merged.size > 0) {
    await admin.from('assistant_lessons').update({
      status: 'retired',
      retired_at: now,
      retired_reason: `دُمج في الدرس ${lesson.id}`,
    }).in('id', [...merged]);
  }
  await addCost(admin, LEARN_TENANT, 'app', costMicroUsd(usage));
  return {
    stage: 'lesson',
    lesson_id: lesson.id,
    publish: d.publish,
    reason: d.reason,
    cost_micro_usd: costMicroUsd(usage),
  };
}

// ------------------------------------------------------------------ مجيب واتساب (م6-14)
async function responderCases(admin: SupabaseClient): Promise<RespCase[]> {
  const { data, error } = await admin
    .from('assistant_eval_cases')
    .select('case_key,category,question,fixtures,expect')
    .eq('audience', 'whatsapp')
    .eq('active', true)
    .order('case_key');
  if (error || !data?.length) throw new Error('no responder cases');
  return data as RespCase[];
}

async function activeResponderLessons(admin: SupabaseClient): Promise<{ id: number; body: string }[]> {
  const { data } = await admin
    .from('assistant_lessons')
    .select('id,body')
    .eq('audience', 'whatsapp')
    .eq('status', 'active')
    .is('tenant_id', null)
    .order('activated_at', { ascending: true });
  return (data ?? []) as { id: number; body: string }[];
}

const respChat = (o: Parameters<typeof chat>[0]) => chat(o, 40_000);
const perCase = (res: RespResult[]) =>
  res.map((r) => ({ key: r.key, pass: r.pass, fails: r.fails, handoff: r.handoff, guarded: r.guarded }));
const respUsage = (res: RespResult[]) => res.reduce((a, r) => addUsage(a, r.usage), ZERO_USAGE);

/** تشغيل يدوي أو بعد تغيير التعليمات: الحالات الـ24 بالدروس الحالية. */
async function evalResponder(admin: SupabaseClient) {
  const cases = await responderCases(admin);
  const active = await activeResponderLessons(admin);
  const res = await runRespCases(cases, respChat, active.map((l) => l.body), 12);
  const usage = respUsage(res);
  const passed = res.filter((r) => r.pass).length;
  const extract = res.filter((r) => r.category === 'extract');
  await admin.from('assistant_eval_runs').insert({
    target: 'whatsapp-responder',
    model: 'deepseek',
    passed,
    total: res.length,
    per_case: perCase(res),
    note: `eval_responder: الاستخراج ${extract.filter((r) => r.pass).length}/${extract.length}`,
  });
  await addCost(admin, LEARN_TENANT, 'app', costMicroUsd(usage));
  return {
    passed,
    total: res.length,
    extract_passed: extract.filter((r) => r.pass).length,
    extract_total: extract.length,
    failed: res.filter((r) => !r.pass).map((r) => ({ key: r.key, fails: r.fails, reply: r.reply, handoff: r.handoff })),
    cost_micro_usd: costMicroUsd(usage),
  };
}

/** اختبار الأمان لدرس مجيب مرشح: بدونه ومعه، وأي سقوط في الاستخراج يرفضه. */
async function evaluateResponderLesson(admin: SupabaseClient) {
  const { data: cand } = await admin
    .from('assistant_lessons')
    .select('id,body')
    .eq('audience', 'whatsapp')
    .eq('status', 'candidate')
    .is('tenant_id', null)
    .or('origin.eq.learn,eval_requested_at.not.is.null')
    .order('created_at', { ascending: true })
    .limit(1);
  const lesson = (cand ?? [])[0] as { id: number; body: string } | undefined;
  if (!lesson) return { stage: 'idle' };

  const cases = await responderCases(admin);
  const active = (await activeResponderLessons(admin)).map((l) => l.body);
  const [base, withL] = await Promise.all([
    runRespCases(cases, respChat, active, 8),
    runRespCases(cases, respChat, [...active, lesson.body], 8),
  ]);
  const usage = addUsage(respUsage(base), respUsage(withL));
  const leak = withL.some((r) => r.category === 'extract' && !r.pass);
  const d = leak
    ? {
      publish: false,
      reason: 'سقطت محاولة استخراج',
      before: base.filter((r) => r.pass).length,
      after: withL.filter((r) => r.pass).length,
    }
    : safetyDecision(base, withL, new Map());
  const now = new Date().toISOString();
  await admin.from('assistant_eval_runs').insert({
    target: 'whatsapp-responder',
    lesson_id: lesson.id,
    model: 'deepseek',
    passed: d.after,
    total: withL.length,
    per_case: perCase(withL),
    note: `${d.publish ? 'نشر' : 'رفض'}: ${d.reason}`,
  });
  await admin.from('assistant_lessons').update(
    d.publish
      ? { status: 'active', activated_at: now, eval_before: d.before, eval_after: d.after, eval_requested_at: null }
      : {
        status: 'rejected',
        retired_at: now,
        retired_reason: `اختبار الأمان: ${d.reason}`,
        eval_before: d.before,
        eval_after: d.after,
        eval_requested_at: null,
      },
  ).eq('id', lesson.id);
  await addCost(admin, LEARN_TENANT, 'app', costMicroUsd(usage));
  return { stage: 'responder_lesson', lesson_id: lesson.id, publish: d.publish, reason: d.reason };
}

// ------------------------------------------------------------------ الخادم
Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);
  const secret = (Deno.env.get('CRON_SECRET') ?? '').trim();
  if (!secret || req.headers.get('Authorization') !== `Bearer ${secret}`) {
    return json({ ok: false, error: 'unauthorized' }, 401);
  }
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  if (!url || !service) return json({ ok: false, error: 'server_misconfigured' }, 500);
  const admin = createClient(url, service);

  let op = 'nightly';
  try {
    op = String((await req.json())?.op ?? 'nightly');
  } catch { /* جسم فارغ */ }

  try {
    if (op === 'evaluate') return json({ ok: true, ...(await evaluate(admin)) });
    if (op === 'eval_responder') return json({ ok: true, ...(await evalResponder(admin)) });
    if (op !== 'nightly') return json({ ok: false, error: 'bad_op' }, 400);
    const j = await judge(admin);
    const p = await propose(admin);
    const m = await mergeRules(admin).catch(() => ({ merged: false, usage: ZERO_USAGE }));
    const retired = await retire(admin);
    const usage = addUsage(addUsage(j.usage, p.usage), m.usage);
    await addCost(admin, LEARN_TENANT, 'app', costMicroUsd(usage));
    return json({
      ok: true,
      judged: j.judged,
      unjudged: j.skipped,
      proposed: p.proposed,
      rejected_by_check: p.rejected,
      merged: m.merged,
      retired,
      cost_micro_usd: costMicroUsd(usage),
    });
  } catch (e) {
    console.warn('assistant-learn failed', String(e).slice(0, 300));
    return json({ ok: false, error: String(e).slice(0, 200) }, 500);
  }
});
