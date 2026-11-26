/** Run: deno test supabase/functions/owner-alert-push-cron/schedule_test.ts */
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { baghdadYmd } from './evaluate_alerts.ts';
import { pushAllowedForUser } from './fcm.ts';
import { shouldEvaluateSnapshot } from './schedule.ts';

Deno.test('baghdadYmd: 22:30 UTC is already the next day in Baghdad', () => {
  assertEquals(baghdadYmd(new Date('2026-11-23T22:30:00Z')), '2026-11-24');
  assertEquals(baghdadYmd(new Date('2026-11-23T20:59:00Z')), '2026-11-23');
});

Deno.test('unchanged snapshot skipped mid-hour, evaluated at top of hour', () => {
  const old = '2026-11-23T08:00:00Z';
  assertEquals(shouldEvaluateSnapshot(old, new Date('2026-11-23T12:30:00Z')), false);
  assertEquals(shouldEvaluateSnapshot(old, new Date('2026-11-23T12:00:00Z')), true);
});

Deno.test('changed snapshot evaluated mid-hour; force always', () => {
  const now = new Date('2026-11-23T12:30:00Z');
  assertEquals(shouldEvaluateSnapshot('2026-11-23T12:20:00Z', now), true);
  assertEquals(shouldEvaluateSnapshot('2026-11-23T08:00:00Z', now, true), true);
  assertEquals(shouldEvaluateSnapshot(null, now), false);
});

Deno.test('pushAllowedForUser fails closed', () => {
  Deno.env.delete('PUSH_ALLOWED_USER_IDS');
  assertEquals(pushAllowedForUser('a'), false);
  Deno.env.set('PUSH_ALLOWED_USER_IDS', 'a, b');
  assertEquals(pushAllowedForUser('b'), true);
  assertEquals(pushAllowedForUser('c'), false);
  Deno.env.set('PUSH_ALLOWED_USER_IDS', '*');
  assertEquals(pushAllowedForUser('c'), true);
  Deno.env.delete('PUSH_ALLOWED_USER_IDS');
});
