/**
 * Regression evals للـ WhatsApp Ops Analyst — تشغيل:
 *   deno test supabase/functions/whatsapp-ops-analyst/evals/run_evals_test.ts
 */
import {
  assert,
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  classifyTenant,
  countFlapTransitions,
  detect463Then401,
} from '../classifier.ts';
import { evaluatePersistencePure } from '../pure_gate.ts';
import { incidentFingerprint } from '../fingerprint.ts';
import { sanitizeEnrichment } from '../enrich.ts';
import baqir from './fixtures/baqir_463_to_401.json' with { type: 'json' };
import flapping from './fixtures/session_flapping_6.json' with { type: 'json' };
import persistence from './fixtures/persistence_silent_fail.json' with {
  type: 'json',
};

Deno.test('fingerprint excludes user_id from hash material', async () => {
  const a = await incidentFingerprint({
    ruleId: 'rule_repair_needed',
    sessionName: 'shop_abc',
    patternKey: 'repair_needed',
    severity: 'P1',
  });
  const b = await incidentFingerprint({
    ruleId: 'rule_repair_needed',
    sessionName: 'shop_abc',
    patternKey: 'repair_needed',
    severity: 'P1',
  });
  assertEquals(a, b);
  assertEquals(a.length, 64);
});

Deno.test('baqir fixture: 463 then 401 → number lock / P1 immediate', () => {
  const facts = baqir.facts as Array<{
    fact_type: string;
    code: string | null;
    created_at: string;
  }>;
  assert(detect463Then401(facts));
  const conditions = classifyTenant({
    userId: baqir.user_id as string,
    sessionName: baqir.session_name as string,
    repairNeeded: true,
    liveStatus: 'disconnected',
    flapCount1h: 0,
    auth401Count1h: 1,
    code463Count1h: 2,
    provisionStorm1h: 0,
    falseAlarm1h: 0,
    sendAccepted1h: 1,
    deliveryAck1h: 0,
    sendFailed1h: 2,
    numberLockSignal: true,
    chain463Then401: true,
  });
  const lock = conditions.find((c) => c.patternKey === 'number_activity_lock');
  assert(lock);
  assertEquals(lock!.severity, 'P1');
  assertEquals(lock!.immediate, true);
  const expected = baqir.expected as { pattern_keys: string[] };
  for (const key of expected.pattern_keys) {
    assert(conditions.some((c) => c.patternKey === key), `missing ${key}`);
  }
});

Deno.test('flapping fixture: ≥6 transitions → session_flapping P2', () => {
  const facts = flapping.facts as Array<{
    fact_type: string;
    code: string | null;
    created_at: string;
  }>;
  const flaps = countFlapTransitions(facts);
  assert(flaps >= 6, `flaps=${flaps}`);
  const conditions = classifyTenant({
    userId: 'u1',
    sessionName: flapping.session_name as string,
    repairNeeded: false,
    liveStatus: 'disconnected',
    flapCount1h: flaps,
    auth401Count1h: 0,
    code463Count1h: 0,
    provisionStorm1h: 0,
    falseAlarm1h: 0,
    sendAccepted1h: 0,
    deliveryAck1h: 0,
    sendFailed1h: 0,
    numberLockSignal: false,
    chain463Then401: false,
  });
  const flap = conditions.find((c) => c.patternKey === 'session_flapping');
  assert(flap);
  assertEquals(flap!.severity, 'P2');
  assertEquals(flap!.immediate, true);
});

Deno.test('persistence: non-immediate waits 5m before promote', () => {
  const now = Date.parse(persistence.now as string);
  const first = Date.parse(persistence.first_seen_at as string);
  assertEquals(
    evaluatePersistencePure({
      immediate: false,
      firstSeenAtMs: null,
      nowMs: now,
    }),
    'create_candidate',
  );
  assertEquals(
    evaluatePersistencePure({
      immediate: false,
      firstSeenAtMs: first,
      nowMs: first + 2 * 60_000,
    }),
    'still_waiting',
  );
  assertEquals(
    evaluatePersistencePure({
      immediate: false,
      firstSeenAtMs: first,
      nowMs: first + 5 * 60_000,
    }),
    'promote',
  );
  assertEquals(
    evaluatePersistencePure({
      immediate: true,
      firstSeenAtMs: null,
      nowMs: now,
    }),
    'open_now',
  );
});

Deno.test('silent undelivered classified as P1 non-immediate', () => {
  const signals = persistence.signals as {
    sendAccepted1h: number;
    deliveryAck1h: number;
  };
  const conditions = classifyTenant({
    userId: 'u1',
    sessionName: 'shop_x',
    repairNeeded: false,
    liveStatus: 'connected',
    flapCount1h: 0,
    auth401Count1h: 0,
    code463Count1h: 0,
    provisionStorm1h: 0,
    falseAlarm1h: 0,
    sendAccepted1h: signals.sendAccepted1h,
    deliveryAck1h: signals.deliveryAck1h,
    sendFailed1h: 0,
    numberLockSignal: false,
    chain463Then401: false,
  });
  const silent = conditions.find(
    (c) => c.patternKey === 'silent_undelivered_spike',
  );
  assert(silent);
  assertEquals(silent!.severity, 'P1');
  assertEquals(silent!.immediate, false);
});

Deno.test('enrichment sanitizer strips hard_reset hints', () => {
  const out = sanitizeEnrichment('يجب عمل hard_reset فوراً ثم severity: P3');
  assert(!out.toLowerCase().includes('hard_reset'));
});
