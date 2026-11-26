// استرجاع الدروس عند السؤال (4.7د، م5-6).
//
// دروس rule الفعّالة كلها في التعليمات (25 كحد). دروس qa وscreen_note: أعلى 4
// بتشابه الثلاثيات بين السؤال و trigger_text بعتبة 0.25، بنفس طريقة pg_trgm.
// الحساب هنا لا في القاعدة، حتى يختار اختبار الأمان الليلي الدروس كما تختارها
// المحادثة تماماً.

export type Lesson = {
  id: number;
  kind: 'rule' | 'qa' | 'screen_note';
  topic: string;
  trigger_text: string;
  body: string;
};

export const MAX_RULES = 25;
export const MAX_NOTES = 4;
export const NOTE_THRESHOLD = 0.25;

/** نفس تطبيع السؤال في كل مكان: الأرقام الهندية، الألف، الياء، التاء المربوطة. */
export function normLesson(s: string): string {
  return s
    .toLowerCase()
    .replace(/[٠-٩]/g, (d) => String('٠١٢٣٤٥٦٧٨٩'.indexOf(d)))
    .replace(/[إأآٱ]/g, 'ا')
    .replace(/ى/g, 'ي')
    .replace(/ة/g, 'ه')
    .replace(/[ً-ْـ]/g, '');
}

/** ثلاثيات pg_trgm: كل كلمة تُبطَّن بمسافتين قبلها ومسافة بعدها. */
export function trigrams(s: string): Set<string> {
  const out = new Set<string>();
  for (const w of normLesson(s).split(/[^\p{L}\p{N}]+/u)) {
    if (!w) continue;
    const p = `  ${w} `;
    for (let i = 0; i + 3 <= p.length; i++) out.add(p.slice(i, i + 3));
  }
  return out;
}

export function similarity(a: string, b: string): number {
  const x = trigrams(a);
  const y = trigrams(b);
  if (x.size === 0 || y.size === 0) return 0;
  let common = 0;
  for (const t of x) if (y.has(t)) common++;
  return common / (x.size + y.size - common);
}

/** أقرب دروس qa/screen_note للسؤال. */
export function pickNotes(all: Lesson[], question: string, max = MAX_NOTES, threshold = NOTE_THRESHOLD): Lesson[] {
  if (!question.trim()) return [];
  return all
    .filter((l) => l.kind !== 'rule')
    .map((l) => ({ l, s: similarity(question, l.trigger_text) }))
    .filter((x) => x.s >= threshold)
    .sort((a, b) => b.s - a.s || a.l.id - b.l.id)
    .slice(0, max)
    .map((x) => x.l);
}

/** رسالة النظام للدروس المسترجعة. فارغة إن لم يُختر شيء. */
export function notesMessage(notes: Lesson[]): string {
  if (notes.length === 0) return '';
  return 'ملاحظات تعلّمها المساعد من أسئلة مشابهة (طبّقها إن انطبقت على هذا السؤال):\n' +
    notes.map((n) => `- ${n.body}`).join('\n');
}
