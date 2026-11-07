/**
 * إثراء DeepSeek فقط — ممنوع تغيير severity أو اقتراح hard_reset/QR كفعل آلي.
 */
import {
  formatLessonsForPrompt,
  type LessonHit,
} from './lesson_types.ts';
import { PLAYBOOK, type PlaybookStepId, type Severity } from './constants.ts';

export type EnrichInput = {
  severity: Severity;
  patternKey: string;
  playbookStepId: PlaybookStepId;
  titleAr: string;
  summaryAr: string;
  sessionName: string;
  factsDigestAr: string;
  lessons: LessonHit[];
};

export type EnrichResult = {
  enrichmentAr: string;
  skipped: boolean;
  reason?: string;
};

const FORBIDDEN_ACTION_HINTS = [
  'hard_reset',
  'hard reset',
  'امسح qr الآن كإجراء تلقائي',
  'غيّر الخطورة',
  'severity:',
];

export function buildEnrichmentPrompt(input: EnrichInput): string {
  const pb = PLAYBOOK[input.playbookStepId];
  const lessons = formatLessonsForPrompt(input.lessons);
  return [
    'أنت محلل عمليات واتساب لمتجر. اكتب بالعربية الفصحى المبسّطة.',
    'مهمتك: إثراء تقرير حادث مُصنَّف مسبقاً — لا تغيّر الخطورة ولا تقترح hard_reset أو مسح QR كفعل آلي.',
    `الخطورة الثابتة: ${input.severity}`,
    `النمط: ${input.patternKey}`,
    `الجلسة: ${input.sessionName}`,
    `العنوان: ${input.titleAr}`,
    `الملخص: ${input.summaryAr}`,
    `دليل التشغيل (${pb.title_ar}): ${pb.steps_ar.join('؛ ')}`,
    `دروس مشابهة:\n${lessons}`,
    `حقائق حديثة:\n${input.factsDigestAr}`,
    'اكتب فقرة قصيرة (4–8 جمل) توضّح السياق التشغيلي وما يجب أن يراجعه المشغّل يدوياً فقط.',
  ].join('\n');
}

export function sanitizeEnrichment(text: string): string {
  let out = text.trim();
  for (const bad of FORBIDDEN_ACTION_HINTS) {
    if (out.toLowerCase().includes(bad.toLowerCase())) {
      out = out.replace(new RegExp(bad, 'ig'), '[محذوف]');
    }
  }
  out = out.replace(/P[123]\s*→\s*P[123]/gi, '[تصنيف ثابت]');
  return out.slice(0, 4000);
}

export async function enrichWithDeepSeek(
  input: EnrichInput,
): Promise<EnrichResult> {
  const apiKey = Deno.env.get('DEEPSEEK_API_KEY') ?? '';
  if (!apiKey) {
    return {
      enrichmentAr: '',
      skipped: true,
      reason: 'DEEPSEEK_API_KEY missing',
    };
  }

  const prompt = buildEnrichmentPrompt(input);
  try {
    const res = await fetch('https://api.deepseek.com/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: Deno.env.get('DEEPSEEK_MODEL') ?? 'deepseek-chat',
        temperature: 0.2,
        messages: [
          {
            role: 'system',
            content:
              'مساعد تحليل فقط. لا تغيّر severity. لا تطلب hard_reset أو QR تلقائي.',
          },
          { role: 'user', content: prompt },
        ],
      }),
    });
    if (!res.ok) {
      const body = await res.text();
      return {
        enrichmentAr: '',
        skipped: true,
        reason: `deepseek_http_${res.status}:${body.slice(0, 120)}`,
      };
    }
    const json = (await res.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const raw = json.choices?.[0]?.message?.content ?? '';
    return {
      enrichmentAr: sanitizeEnrichment(raw),
      skipped: false,
    };
  } catch (e) {
    return {
      enrichmentAr: '',
      skipped: true,
      reason: String(e).slice(0, 200),
    };
  }
}
