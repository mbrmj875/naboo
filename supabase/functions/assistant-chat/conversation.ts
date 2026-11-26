/**
 * فحص محادثة الهاتف قبل إرسالها للنموذج (4.1 «حدود ثابتة»).
 */
import type { TurnToolLog } from '../_shared/assistant_meter.ts';

// ذ1: نتائج البطاقات صارت تُحفظ في السياق، فالحد يتسع لنحو 8 أسئلة معها.
export const MAX_HISTORY = 40;
export const MAX_TOOL_RESULT_CHARS = 6000;
export const MAX_TOOLS_PER_STEP = 3;
export const MAX_USER_CHARS = 2000;
export const MAX_IMAGE_CHARS = 1_400_000; // نحو 1 ميغابايت بعد base64

// ------------------------------------------------------------------ فحص المحادثة
export type InMsg = Record<string, unknown>;

export type CleanConversation = {
  messages: Record<string, unknown>[];
  question: string;
  hasImage: boolean;
  /** نتائج الأدوات التي أُرسلت في هذه الخطوة (رد على خطوة سابقة). */
  stepTools: TurnToolLog[];
  /** ذ9: أسماء الأدوات التي نتائجها في رسائل سابقة من المحادثة (قبل السؤال الحالي). */
  priorTools: string[];
  toolResults: unknown[];
};

export function textOf(content: unknown): string {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map((p) => (p && typeof p === 'object' && (p as InMsg).type === 'text' ? String((p as InMsg).text ?? '') : ''))
      .join(' ');
  }
  return '';
}

/**
 * يحوّل محادثة الهاتف إلى صيغة DeepSeek ويقصّها بأمان:
 * لا رسائل نظام من الهاتف، نتائج الأدوات مقصوصة، والتاريخ يبدأ دائماً برسالة مستخدم
 * حتى لا تنقطع سلسلة نداء أداة ونتيجته.
 */
export function cleanConversation(raw: unknown, allowImages: boolean): CleanConversation | string {
  if (!Array.isArray(raw) || raw.length === 0) return 'messages_required';
  const out: Record<string, unknown>[] = [];
  const callNames = new Map<string, string>();
  let hasImage = false;

  for (const m of raw as InMsg[]) {
    const role = String(m?.role ?? '');
    if (role === 'user') {
      if (Array.isArray(m.content)) {
        const parts: Record<string, unknown>[] = [];
        for (const p of m.content as InMsg[]) {
          if (p?.type === 'text') parts.push({ type: 'text', text: String(p.text ?? '').slice(0, MAX_USER_CHARS) });
          if (p?.type === 'image_url') {
            const url = String((p.image_url as InMsg | undefined)?.url ?? '');
            if (!url.startsWith('data:image/')) return 'bad_image';
            if (url.length > MAX_IMAGE_CHARS) return 'image_too_large';
            if (!allowImages) return 'images_disabled';
            hasImage = true;
            parts.push({ type: 'image_url', image_url: { url } });
          }
        }
        out.push({ role: 'user', content: parts });
      } else {
        out.push({ role: 'user', content: String(m.content ?? '').slice(0, MAX_USER_CHARS) });
      }
    } else if (role === 'assistant') {
      const calls = Array.isArray(m.tool_calls) ? (m.tool_calls as InMsg[]).slice(0, MAX_TOOLS_PER_STEP) : [];
      const msg: Record<string, unknown> = { role: 'assistant', content: String(m.content ?? '').slice(0, 4000) };
      if (calls.length > 0) {
        msg.tool_calls = calls.map((c) => {
          const id = String(c.id ?? '');
          const name = String(c.name ?? (c.function as InMsg | undefined)?.name ?? '');
          callNames.set(id, name);
          const args = c.arguments ?? (c.function as InMsg | undefined)?.arguments ?? {};
          return {
            id,
            type: 'function',
            function: { name, arguments: typeof args === 'string' ? args : JSON.stringify(args) },
          };
        });
      }
      out.push(msg);
    } else if (role === 'tool') {
      let content = String(m.content ?? '');
      if (content.length > MAX_TOOL_RESULT_CHARS) {
        content = content.slice(0, MAX_TOOL_RESULT_CHARS) + '…{"truncated":true}';
      }
      out.push({ role: 'tool', tool_call_id: String(m.tool_call_id ?? ''), content });
    }
  }

  // القص: آخر MAX_HISTORY رسالة، تبدأ برسالة مستخدم.
  let start = Math.max(0, out.length - MAX_HISTORY);
  while (start < out.length && out[start].role !== 'user') start++;
  const kept = out.slice(start);
  if (kept.length === 0) return 'messages_required';

  // آخر رسالة مستخدم = السؤال الحالي.
  let lastUser = -1;
  for (let i = kept.length - 1; i >= 0; i--) {
    if (kept[i].role === 'user') {
      lastUser = i;
      break;
    }
  }
  const question = textOf(kept[lastUser]?.content).trim();

  // نتائج أدوات هذه الخطوة: بعد آخر رسالة مساعد.
  let lastAssistant = -1;
  for (let i = kept.length - 1; i >= 0; i--) {
    if (kept[i].role === 'assistant') {
      lastAssistant = i;
      break;
    }
  }
  const stepTools: TurnToolLog[] = [];
  const priorTools: string[] = [];
  const toolResults: unknown[] = [];
  for (let i = 0; i < kept.length; i++) {
    const m = kept[i];
    if (m.role !== 'tool') continue;
    if (i < lastUser) {
      const n = callNames.get(String(m.tool_call_id));
      if (n && !n.startsWith('ui_') && !priorTools.includes(n)) priorTools.push(n);
    }
    let parsed: InMsg | null = null;
    try {
      parsed = JSON.parse(String(m.content).replace(/…\{"truncated":true\}$/, ''));
    } catch { /* نص غير JSON */ }
    if (parsed) toolResults.push(parsed);
    if (i > lastAssistant && lastAssistant >= 0) {
      const rows = Array.isArray(parsed?.rows) ? (parsed!.rows as unknown[]).length : undefined;
      stepTools.push({
        name: callNames.get(String(m.tool_call_id)) ?? 'unknown',
        ok: parsed?.ok !== false,
        rows,
      });
    }
  }

  return { messages: kept, question, hasImage: hasImage && lastUser === kept.length - 1, stepTools, priorTools, toolResults };
}

export function parseArgs(s: string): Record<string, unknown> {
  try {
    const v = JSON.parse(s || '{}');
    return v && typeof v === 'object' ? v : {};
  } catch {
    return {};
  }
}

