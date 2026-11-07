/**
 * دروس RAG عبر المستأجرين — upsert عند تأكيد الحادث + استرجاع للتشابه.
 */
import type { Severity } from './constants.ts';
import {
  formatLessonsForPrompt,
  type LessonHit,
} from './lesson_types.ts';

export type { LessonHit };
export { formatLessonsForPrompt };

export async function upsertLessonFromIncident(args: {
  // deno-lint-ignore no-explicit-any
  sb: any;
  incidentId: string;
  patternKey: string;
  severity: Severity;
  titleAr: string;
  summaryAr: string;
  playbookStepId: string;
  rootCauseAr?: string;
  resolutionAr?: string;
  evalFixtureId?: string | null;
}): Promise<string | null> {
  const { data: existing } = await args.sb
    .from('whatsapp_ops_lessons')
    .select('id, times_confirmed')
    .eq('pattern_key', args.patternKey)
    .eq('severity', args.severity)
    .maybeSingle();

  const now = new Date().toISOString();
  if (existing?.id) {
    await args.sb
      .from('whatsapp_ops_lessons')
      .update({
        title_ar: args.titleAr,
        summary_ar: args.summaryAr,
        root_cause_ar: args.rootCauseAr ?? null,
        resolution_ar: args.resolutionAr ?? null,
        playbook_step_id: args.playbookStepId,
        eval_fixture_id: args.evalFixtureId ?? null,
        times_confirmed: Number(existing.times_confirmed ?? 1) + 1,
        last_confirmed_at: now,
        source_incident_id: args.incidentId,
        updated_at: now,
      })
      .eq('id', existing.id);
    return existing.id as string;
  }

  const { data: inserted, error } = await args.sb
    .from('whatsapp_ops_lessons')
    .insert({
      pattern_key: args.patternKey,
      severity: args.severity,
      title_ar: args.titleAr,
      summary_ar: args.summaryAr,
      root_cause_ar: args.rootCauseAr ?? null,
      resolution_ar: args.resolutionAr ?? null,
      playbook_step_id: args.playbookStepId,
      eval_fixture_id: args.evalFixtureId ?? null,
      times_confirmed: 1,
      last_confirmed_at: now,
      source_incident_id: args.incidentId,
    })
    .select('id')
    .maybeSingle();

  if (error) {
    console.warn('lesson upsert failed', error.message);
    return null;
  }
  return (inserted?.id as string) ?? null;
}

/** استرجاع أعلى دروس مشابهة بالنمط ثم الخطورة. */
export async function retrieveSimilarLessons(args: {
  // deno-lint-ignore no-explicit-any
  sb: any;
  patternKey: string;
  severity: Severity;
  limit?: number;
}): Promise<LessonHit[]> {
  const limit = args.limit ?? 3;
  const { data: exact } = await args.sb
    .from('whatsapp_ops_lessons')
    .select(
      'id, pattern_key, severity, title_ar, summary_ar, root_cause_ar, resolution_ar, playbook_step_id, times_confirmed',
    )
    .eq('pattern_key', args.patternKey)
    .order('times_confirmed', { ascending: false })
    .limit(limit);

  const hits = (exact ?? []) as LessonHit[];
  if (hits.length >= limit) return hits;

  const { data: bySev } = await args.sb
    .from('whatsapp_ops_lessons')
    .select(
      'id, pattern_key, severity, title_ar, summary_ar, root_cause_ar, resolution_ar, playbook_step_id, times_confirmed',
    )
    .eq('severity', args.severity)
    .neq('pattern_key', args.patternKey)
    .order('times_confirmed', { ascending: false })
    .limit(limit - hits.length);

  const seen = new Set(hits.map((h) => h.id));
  for (const row of (bySev ?? []) as LessonHit[]) {
    if (seen.has(row.id)) continue;
    hits.push(row);
  }
  return hits;
}
