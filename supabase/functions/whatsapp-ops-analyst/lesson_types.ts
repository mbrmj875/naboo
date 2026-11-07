export type LessonHit = {
  id: string;
  pattern_key: string;
  severity: string;
  title_ar: string;
  summary_ar: string;
  root_cause_ar: string | null;
  resolution_ar: string | null;
  playbook_step_id: string | null;
  times_confirmed: number;
};

export function formatLessonsForPrompt(lessons: LessonHit[]): string {
  if (lessons.length === 0) return 'لا دروس سابقة مشابهة.';
  return lessons
    .map(
      (l, i) =>
        `${i + 1}) [${l.severity}/${l.pattern_key}] ${l.title_ar}: ${l.summary_ar}` +
        (l.resolution_ar ? ` → ${l.resolution_ar}` : ''),
    )
    .join('\n');
}
