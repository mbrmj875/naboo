/**
 * خطوات ربط واتساب في whatsapp_onboarding_state.
 * فشل الكتابة لا يوقف الربط، فهذا الجدول للاستكمال والقياس فقط.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

export type OnboardingStep =
  | 'started'
  | 'meta_opened'
  | 'meta_returned'
  | 'completed'
  | 'test_sent'
  | 'failed';

export type OnboardingRow = {
  provider: string | null;
  current_step: OnboardingStep;
  steps: Record<string, string>;
  last_error_code: string | null;
  started_at: string;
  completed_at: string | null;
  updated_at: string;
};

/** أول وقت لكل خطوة يبقى كما هو، حتى يقاس الزمن من أول محاولة. */
export function nextOnboardingRow(
  existing: OnboardingRow | null,
  args: {
    step: OnboardingStep;
    provider: string | null;
    errorCode?: string | null;
    now: string;
  },
): OnboardingRow {
  const steps = { ...(existing?.steps ?? {}) };
  if (!steps[args.step]) steps[args.step] = args.now;
  return {
    provider: args.provider ?? existing?.provider ?? null,
    current_step: args.step,
    steps,
    last_error_code: args.step === 'failed' ? (args.errorCode ?? 'unknown') : null,
    started_at: existing?.started_at ?? args.now,
    completed_at: existing?.completed_at ??
      (args.step === 'completed' ? args.now : null),
    updated_at: args.now,
  };
}

export async function recordOnboardingStep(
  db: SupabaseClient,
  tenantUserId: string,
  step: OnboardingStep,
  options: { provider?: string | null; errorCode?: string | null } = {},
): Promise<void> {
  try {
    const { data } = await db
      .from('whatsapp_onboarding_state')
      .select(
        'provider, current_step, steps, last_error_code, started_at, completed_at, updated_at',
      )
      .eq('user_id', tenantUserId)
      .maybeSingle();
    const row = nextOnboardingRow((data as OnboardingRow | null) ?? null, {
      step,
      provider: options.provider ?? null,
      errorCode: options.errorCode,
      now: new Date().toISOString(),
    });
    const { error } = await db
      .from('whatsapp_onboarding_state')
      .upsert({ user_id: tenantUserId, ...row }, { onConflict: 'user_id' });
    if (error) console.warn('onboarding step write failed', error.message);
  } catch (e) {
    console.warn('onboarding step exception', String(e).slice(0, 160));
  }
}

/** للشاشة: آخر خطوة وسبب التوقف فقط. */
export async function readOnboardingSummary(
  db: SupabaseClient,
  tenantUserId: string,
): Promise<{ step: string; error_code: string | null } | null> {
  try {
    const { data, error } = await db
      .from('whatsapp_onboarding_state')
      .select('current_step, last_error_code')
      .eq('user_id', tenantUserId)
      .maybeSingle();
    if (error || !data) return null;
    return {
      step: String(data.current_step),
      error_code: data.last_error_code ? String(data.last_error_code) : null,
    };
  } catch {
    return null;
  }
}
