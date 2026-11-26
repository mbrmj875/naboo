/**
 * عدّاد الكلفة وسجل الأسئلة المشترك بين المساعد ومجيب واتساب
 * (خطة المساعد ق15، ق51، ق54، ق88، م1-11، م6-3).
 *
 * الأرقام كلها في قاعدة البيانات (`assistant_budget_check`، `assistant_budget_add`)
 * حتى يبقى الحساب واحداً مهما تعددت نسخ الدالة. هذا الملف يقرأها ويحوّلها إلى سلوك.
 */
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import type { Usage } from './llm.ts';

export type Channel = 'app' | 'whatsapp';
export type BudgetMode = 'full' | 'economy' | 'exhausted';

export type Budget = {
  mode: BudgetMode;
  used: number;
  usedToday: number;
  monthly: number;
  daily: number;
  pct: number;
};

/** حدود كل وضع (4.14): الاقتصادي 3 خطوات و500 رمز بلا صور. */
export type ModePolicy = {
  maxSteps: number;
  maxTokens: number;
  images: boolean;
  /** البحث للسيارات غير الموجودة في الدليل فقط في الوضعين. */
  web: boolean;
};

export function policyFor(mode: BudgetMode): ModePolicy {
  switch (mode) {
    case 'full':
      return { maxSteps: 5, maxTokens: 900, images: true, web: true };
    case 'economy':
      return { maxSteps: 3, maxTokens: 500, images: false, web: true };
    default:
      return { maxSteps: 0, maxTokens: 0, images: false, web: false };
  }
}

/** أول يوم في الشهر القادم بتوقيت بغداد، يُعرض للمستخدم عند النفاد. */
export function renewsOn(now: Date = new Date()): string {
  const bg = new Date(now.getTime() + 3 * 3600_000);
  const y = bg.getUTCFullYear();
  const m = bg.getUTCMonth();
  const next = new Date(Date.UTC(m === 11 ? y + 1 : y, (m + 1) % 12, 1));
  return next.toISOString().slice(0, 10);
}

/**
 * الحساب التجريبي (ق51): لا ترخيص فعّال مرتبط بالحساب.
 * أي خطأ في القراءة يُعامَل كغير تجريبي، فلا يُعاقَب محل مشترك بسقف أصغر.
 */
export async function isTrialTenant(admin: SupabaseClient, tenantId: string): Promise<boolean> {
  try {
    const { data, error } = await admin
      .from('licenses')
      .select('id')
      .eq('assigned_user_id', tenantId)
      .eq('status', 'active')
      .limit(1);
    if (error) return false;
    return (data ?? []).length === 0;
  } catch {
    return false;
  }
}

export async function checkBudget(
  admin: SupabaseClient,
  tenantId: string,
  channel: Channel,
  isTrial: boolean,
): Promise<Budget> {
  const { data, error } = await admin.rpc('assistant_budget_check', {
    p_tenant: tenantId,
    p_channel: channel,
    p_is_trial: isTrial,
  });
  if (error || !data) {
    // العدّاد غير متاح: نعمل بالوضع الاقتصادي بدل أن نوقف المساعد أو نصرف بلا حد.
    console.warn('assistant_budget_check failed', error?.message);
    return { mode: 'economy', used: 0, usedToday: 0, monthly: 0, daily: 0, pct: 0 };
  }
  const d = data as Record<string, unknown>;
  return {
    mode: (['full', 'economy', 'exhausted'].includes(String(d.mode)) ? d.mode : 'economy') as BudgetMode,
    used: Number(d.used ?? 0),
    usedToday: Number(d.used_today ?? 0),
    monthly: Number(d.monthly ?? 0),
    daily: Number(d.daily ?? 0),
    pct: Number(d.pct ?? 0),
  };
}

export async function addCost(
  admin: SupabaseClient,
  tenantId: string,
  channel: Channel,
  microUsd: number,
  extra: { searches?: number; images?: number } = {},
): Promise<void> {
  if (microUsd <= 0 && !extra.searches && !extra.images) return;
  const { error } = await admin.rpc('assistant_budget_add', {
    p_tenant: tenantId,
    p_micro_usd: Math.max(0, Math.round(microUsd)),
    p_searches: extra.searches ?? 0,
    p_images: extra.images ?? 0,
    p_channel: channel,
  });
  if (error) console.warn('assistant_budget_add failed', error.message);
}

/** prior: نتيجة أداة من رسالة سابقة في المحادثة نفسها (ذ9)، يراها الحَكَم سياقاً لا نداءً جديداً. */
export type TurnToolLog = { name: string; ok: boolean; rows?: number; prior?: boolean };

export type TurnStep = {
  turnId: string;
  threadId: string;
  tenantId: string;
  userId: string | null;
  channel: Channel;
  roleKey: string;
  isOwner: boolean;
  routeId: string | null;
  appVersion: string | null;
  /** السؤال بعد التنظيف. يُكتب في أول خطوة فقط. */
  questionClean: string;
  /** الجواب بعد التنظيف، في الخطوة الأخيرة فقط. */
  answerClean: string | null;
  tools: TurnToolLog[];
  usage: Usage;
  costMicroUsd: number;
  latencyMs: number;
  model: string;
  finish: string;
  budgetMode: BudgetMode;
  /** الدروس المستعملة في هذا السؤال (4.7د). تُكتب في أول خطوة. */
  lessonIds?: number[];
  hasImage: boolean;
  usedWeb: boolean;
};

/**
 * يكتب سطراً واحداً لكل سؤال، ويجمع الخطوات اللاحقة فوقه.
 * نتائج الأدوات لا تُحفظ أبداً: الاسم والنجاح وعدد الصفوف فقط.
 */
export async function recordTurnStep(admin: SupabaseClient, s: TurnStep): Promise<void> {
  try {
    const { data: prev } = await admin
      .from('assistant_turns')
      .select('tools,steps,tokens_in,tokens_cached,tokens_out,latency_ms,cost_micro_usd,has_image,used_web')
      .eq('id', s.turnId)
      .eq('tenant_id', s.tenantId)
      .maybeSingle();

    if (!prev) {
      const { error } = await admin.from('assistant_turns').insert({
        id: s.turnId,
        tenant_id: s.tenantId,
        user_id: s.userId,
        thread_id: s.threadId,
        channel: s.channel,
        role_key: s.roleKey,
        is_owner: s.isOwner,
        route_id: s.routeId,
        app_version: s.appVersion,
        question_clean: s.questionClean || '—',
        answer_clean: s.answerClean,
        tools: s.tools,
        steps: 1,
        finish: s.finish,
        model: s.model,
        tokens_in: s.usage.miss + s.usage.hit,
        tokens_cached: s.usage.hit,
        tokens_out: s.usage.out,
        latency_ms: s.latencyMs,
        cost_micro_usd: s.costMicroUsd,
        budget_mode: s.budgetMode,
        has_image: s.hasImage,
        used_web: s.usedWeb,
        lesson_ids: s.lessonIds ?? [],
      });
      if (error) console.warn('assistant_turns insert failed', error.message);
      return;
    }

    const p = prev as Record<string, unknown>;
    const n = (v: unknown) => Number(v ?? 0);
    const patch: Record<string, unknown> = {
      tools: [...((p.tools as TurnToolLog[] | null) ?? []), ...s.tools].slice(0, 40),
      steps: Math.min(n(p.steps) + 1, 32000),
      finish: s.finish,
      model: s.model,
      tokens_in: n(p.tokens_in) + s.usage.miss + s.usage.hit,
      tokens_cached: n(p.tokens_cached) + s.usage.hit,
      tokens_out: n(p.tokens_out) + s.usage.out,
      latency_ms: n(p.latency_ms) + s.latencyMs,
      cost_micro_usd: n(p.cost_micro_usd) + s.costMicroUsd,
      budget_mode: s.budgetMode,
      has_image: Boolean(p.has_image) || s.hasImage,
      used_web: Boolean(p.used_web) || s.usedWeb,
    };
    if (s.answerClean != null) patch.answer_clean = s.answerClean;
    const { error } = await admin
      .from('assistant_turns')
      .update(patch)
      .eq('id', s.turnId)
      .eq('tenant_id', s.tenantId);
    if (error) console.warn('assistant_turns update failed', error.message);
  } catch (e) {
    console.warn('recordTurnStep failed', String(e).slice(0, 200));
  }
}
