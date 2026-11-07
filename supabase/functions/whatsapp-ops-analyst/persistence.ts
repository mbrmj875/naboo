/**
 * بوابة استمرار الشرط — غير P1 الفوري يحتاج X=5د متصلة.
 */
import { evaluatePersistencePure } from './pure_gate.ts';
import type { ClassifiedCondition } from './classifier.ts';
import { incidentFingerprint } from './fingerprint.ts';

export { evaluatePersistencePure } from './pure_gate.ts';

export type CandidateRow = {
  fingerprint: string;
  user_id: string;
  session_name: string;
  condition_key: string;
  severity_intent: string;
  pattern_key: string;
  playbook_step_id: string;
  rule_id: string;
  first_seen_at: string;
  last_seen_at: string;
};

export async function applyPersistenceGate(args: {
  // deno-lint-ignore no-explicit-any
  sb: any;
  userId: string;
  sessionName: string;
  conditions: ClassifiedCondition[];
  nowMs?: number;
}): Promise<{
  toOpen: Array<{ condition: ClassifiedCondition; fingerprint: string }>;
  tracked: string[];
  cleared: string[];
}> {
  const now = args.nowMs ?? Date.now();
  const nowIso = new Date(now).toISOString();
  const activeFingerprints = new Set<string>();
  const toOpen: Array<{ condition: ClassifiedCondition; fingerprint: string }> =
    [];
  const tracked: string[] = [];

  for (const condition of args.conditions) {
    const fingerprint = await incidentFingerprint({
      ruleId: condition.ruleId,
      sessionName: args.sessionName,
      patternKey: condition.patternKey,
      severity: condition.severity,
    });
    activeFingerprints.add(fingerprint);

    if (condition.immediate) {
      toOpen.push({ condition, fingerprint });
      await args.sb
        .from('whatsapp_ops_condition_candidates')
        .delete()
        .eq('fingerprint', fingerprint);
      continue;
    }

    const { data: existing } = await args.sb
      .from('whatsapp_ops_condition_candidates')
      .select('*')
      .eq('fingerprint', fingerprint)
      .maybeSingle();

    const decision = evaluatePersistencePure({
      immediate: false,
      firstSeenAtMs: existing?.first_seen_at
        ? new Date(existing.first_seen_at as string).getTime()
        : null,
      nowMs: now,
    });

    if (decision === 'create_candidate') {
      await args.sb.from('whatsapp_ops_condition_candidates').upsert({
        fingerprint,
        user_id: args.userId,
        session_name: args.sessionName,
        condition_key: condition.ruleId,
        severity_intent: condition.severity,
        pattern_key: condition.patternKey,
        playbook_step_id: condition.playbookStepId,
        rule_id: condition.ruleId,
        first_seen_at: nowIso,
        last_seen_at: nowIso,
      });
      tracked.push(fingerprint);
      continue;
    }

    await args.sb
      .from('whatsapp_ops_condition_candidates')
      .update({ last_seen_at: nowIso })
      .eq('fingerprint', fingerprint);

    if (decision === 'promote') {
      toOpen.push({ condition, fingerprint });
      await args.sb
        .from('whatsapp_ops_condition_candidates')
        .delete()
        .eq('fingerprint', fingerprint);
    } else {
      tracked.push(fingerprint);
    }
  }

  const { data: stale } = await args.sb
    .from('whatsapp_ops_condition_candidates')
    .select('fingerprint')
    .eq('user_id', args.userId)
    .eq('session_name', args.sessionName);

  const cleared: string[] = [];
  for (const row of stale ?? []) {
    const fp = row.fingerprint as string;
    if (!activeFingerprints.has(fp)) {
      await args.sb
        .from('whatsapp_ops_condition_candidates')
        .delete()
        .eq('fingerprint', fp);
      cleared.push(fp);
    }
  }

  return { toOpen, tracked, cleared };
}
