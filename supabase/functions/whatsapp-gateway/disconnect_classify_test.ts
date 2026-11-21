/**
 * اختبارات classifyDisconnect — تشغيل:
 *   deno test supabase/functions/whatsapp-gateway/disconnect_classify_test.ts
 */
import {
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  canAttemptRestart,
  classifyDisconnect,
  RESTART_COOLDOWN_MS,
} from './disconnect_classify.ts';

Deno.test('device_removed → permanent', () => {
  assertEquals(
    classifyDisconnect({ state: 'close', statusReason: '401', rawSnippet: 'conflict type=device_removed' }),
    'permanent',
  );
});

Deno.test('loggedOut → permanent', () => {
  assertEquals(
    classifyDisconnect({ state: 'close', statusReason: 'loggedOut' }),
    'permanent',
  );
});

Deno.test('phoneDisconnected → temporary', () => {
  assertEquals(
    classifyDisconnect({ state: 'close', statusReason: 'phoneDisconnected' }),
    'temporary',
  );
});

Deno.test('401 alone → permanent', () => {
  assertEquals(
    classifyDisconnect({ state: 'close', statusReason: 401 }),
    'permanent',
  );
});

Deno.test('401 after recent 515 → temporary', () => {
  assertEquals(
    classifyDisconnect({
      state: 'close',
      statusReason: 401,
      recent515WithinWindow: true,
    }),
    'temporary',
  );
});

Deno.test('515 → temporary', () => {
  assertEquals(
    classifyDisconnect({ state: 'close', statusReason: '515' }),
    'temporary',
  );
});

Deno.test('WORKING→FAILED (prev connected) → permanent', () => {
  assertEquals(
    classifyDisconnect({
      state: 'close',
      statusReason: 'FAILED',
      prevGateStatus: 'connected',
      wahaStatus: 'FAILED',
    }),
    'permanent',
  );
});

Deno.test('FAILED without prior connected → temporary unless tokens', () => {
  assertEquals(
    classifyDisconnect({
      state: 'close',
      statusReason: 'FAILED',
      prevGateStatus: 'connecting',
      wahaStatus: 'FAILED',
    }),
    'temporary',
  );
});

Deno.test('LoggedOut blob → permanent', () => {
  assertEquals(
    classifyDisconnect({
      state: 'close',
      statusReason: '401',
      rawSnippet: '{"engine_event":"events.LoggedOut","reason":401}',
    }),
    'permanent',
  );
});

Deno.test('canAttemptRestart respects cooldown', () => {
  const now = Date.now();
  const blocked = canAttemptRestart({
    restartAttempts: 1,
    lastRestartAt: new Date(now - 10_000).toISOString(),
    nowMs: now,
  });
  assertEquals(blocked.ok, false);
  assertEquals(blocked.reason, 'cooldown');

  const ok = canAttemptRestart({
    restartAttempts: 1,
    lastRestartAt: new Date(now - RESTART_COOLDOWN_MS - 1).toISOString(),
    nowMs: now,
  });
  assertEquals(ok.ok, true);
});
