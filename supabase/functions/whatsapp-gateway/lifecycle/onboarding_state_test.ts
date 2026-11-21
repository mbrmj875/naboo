import {
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { nextOnboardingRow, type OnboardingRow } from './onboarding_state.ts';

const t0 = '2026-11-07T10:00:00.000Z';
const t1 = '2026-11-07T10:05:00.000Z';

Deno.test('أول خطوة تبدأ وقت الربط', () => {
  const r = nextOnboardingRow(null, { step: 'started', provider: 'cloud_api', now: t0 });
  assertEquals(r.started_at, t0);
  assertEquals(r.steps.started, t0);
  assertEquals(r.completed_at, null);
});

Deno.test('المحاولة الثانية لا تغير وقت الخطوة الأولى', () => {
  const first = nextOnboardingRow(null, { step: 'started', provider: 'cloud_api', now: t0 });
  const again = nextOnboardingRow(first, { step: 'started', provider: null, now: t1 });
  assertEquals(again.steps.started, t0);
  assertEquals(again.started_at, t0);
  assertEquals(again.provider, 'cloud_api');
  assertEquals(again.updated_at, t1);
});

Deno.test('الفشل يحفظ السبب وما اكتمل، والخطوة التالية تمسح السبب', () => {
  const first = nextOnboardingRow(null, { step: 'meta_opened', provider: 'cloud_api', now: t0 });
  const failed = nextOnboardingRow(first, {
    step: 'failed',
    provider: null,
    errorCode: 'phone_register_failed',
    now: t1,
  });
  assertEquals(failed.last_error_code, 'phone_register_failed');
  assertEquals(failed.steps.meta_opened, t0);
  const next = nextOnboardingRow(failed, { step: 'meta_returned', provider: null, now: t1 });
  assertEquals(next.last_error_code, null);
});

Deno.test('وقت الاكتمال الأول يبقى بعد رسالة التجربة', () => {
  const done = nextOnboardingRow(null, { step: 'completed', provider: 'dualhook', now: t0 });
  const test: OnboardingRow = nextOnboardingRow(done, { step: 'test_sent', provider: null, now: t1 });
  assertEquals(test.completed_at, t0);
});
