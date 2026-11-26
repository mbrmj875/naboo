/**
 * طبقة المزوّد المشتركة (خطة المساعد، م6-2، 4.13د).
 *
 * كل استدعاء لـ DeepSeek من المساعد ومن مجيب واتساب يمر من هنا:
 * أسماء النماذج، إعداد التفكير، قراءة البث، وجدول الأسعار لحساب الكلفة.
 * إن تغيّر المزوّد أو أسماؤه يتغير هذا الملف وحده.
 *
 * مقيس في ب0 (2026-11-23):
 * - `/models` يعيد `deepseek-flash` (نص وصور) و`deepseek-v4-pro` (نص فقط).
 * - `deepseek-chat` اسم قديم يوجَّه إلى flash بلا تفكير، فلا نعتمد عليه.
 * - التفكير لم يرفع الدقة على حالات المساعد وزاد الكلفة 55%، فهو مطفأ افتراضياً.
 */

export const DEEPSEEK_BASE = 'https://api.deepseek.com';
export const CHAT_ENDPOINT = `${DEEPSEEK_BASE}/chat/completions`;

export const MODELS = {
  /** النموذج الافتراضي للمساعد والمجيب، ويقرأ الصور. */
  fast: 'deepseek-flash',
  /** نص فقط. غير مستعمل حالياً. */
  pro: 'deepseek-v4-pro',
} as const;

export type Effort = 'off' | 'low' | 'high';

export type ChatMessage = Record<string, unknown>;

export type ChatOptions = {
  messages: ChatMessage[];
  model?: string;
  effort?: Effort;
  maxTokens?: number;
  temperature?: number;
  tools?: unknown[];
  toolChoice?: 'auto' | 'none';
  json?: boolean;
  stream?: boolean;
};

export function deepseekKey(): string | null {
  return Deno.env.get('DEEPSEEK_API_KEY')?.trim() || null;
}

/** يبني جسم الطلب. التفكير يُطفأ أو يُشغَّل صراحة، ولا يُترك للاسم. */
export function buildChatBody(o: ChatOptions): Record<string, unknown> {
  const effort = o.effort ?? 'off';
  const body: Record<string, unknown> = {
    model: o.model ?? MODELS.fast,
    messages: o.messages,
    max_tokens: o.maxTokens ?? 900,
    thinking: { type: effort === 'off' ? 'disabled' : 'enabled' },
  };
  if (effort !== 'off') body.reasoning_effort = effort;
  // درجة الحرارة لا تُقبل مع التفكير.
  if (effort === 'off' && o.temperature != null) body.temperature = o.temperature;
  if (o.tools && o.tools.length > 0) {
    body.tools = o.tools;
    if (o.toolChoice) body.tool_choice = o.toolChoice;
  }
  if (o.json) body.response_format = { type: 'json_object' };
  if (o.stream) {
    body.stream = true;
    body.stream_options = { include_usage: true };
  }
  return body;
}

// ------------------------------------------------------------------ الكلفة

export type Usage = {
  /** رموز الإدخال غير المخزَّنة. */
  miss: number;
  /** رموز الإدخال المخزَّنة. */
  hit: number;
  out: number;
};

export const ZERO_USAGE: Usage = { miss: 0, hit: 0, out: 0 };

export function addUsage(a: Usage, b: Usage): Usage {
  return { miss: a.miss + b.miss, hit: a.hit + b.hit, out: a.out + b.out };
}

/** يقرأ حقل `usage` كما يعيده DeepSeek. */
export function parseUsage(raw: unknown): Usage {
  const u = (raw ?? {}) as Record<string, unknown>;
  const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);
  const prompt = n(u.prompt_tokens);
  const hit = n(u.prompt_cache_hit_tokens);
  const missRaw = u.prompt_cache_miss_tokens;
  const miss = typeof missRaw === 'number' ? missRaw : Math.max(prompt - hit, 0);
  return { miss, hit, out: n(u.completion_tokens) };
}

/**
 * أسعار `deepseek-flash` المنشورة بجزء من مليون دولار لكل رمز
 * (أي دولار لكل مليون رمز). الذروة ضعف خارجها.
 */
export const PRICE_OFFPEAK = { hit: 0.003, miss: 0.15, out: 0.6 } as const;

/**
 * ساعات الذروة عند DeepSeek: 09:00–12:00 و14:00–18:00 بتوقيت بكين، من الاثنين إلى الجمعة.
 * تقابل 04:00–07:00 و09:00–13:00 بتوقيت بغداد.
 */
export function isPeak(at: Date): boolean {
  const bj = new Date(at.getTime() + 8 * 3600_000);
  const day = bj.getUTCDay();
  if (day === 0 || day === 6) return false;
  const h = bj.getUTCHours() + bj.getUTCMinutes() / 60;
  return (h >= 9 && h < 12) || (h >= 14 && h < 18);
}

/** الكلفة بجزء من مليون دولار، مقرَّبة للأعلى حتى لا يُحسب طلب بصفر. */
export function costMicroUsd(u: Usage, at: Date = new Date()): number {
  const f = isPeak(at) ? 2 : 1;
  const c = (u.hit * PRICE_OFFPEAK.hit + u.miss * PRICE_OFFPEAK.miss + u.out * PRICE_OFFPEAK.out) * f;
  return Math.ceil(c);
}

// ------------------------------------------------------------------ الطلب

export type ToolCall = { id: string; name: string; arguments: string };

/** مصدر من أداة بحث الخادم (`message.server_tool_calls[].calls[].sources`). */
export type WebSource = { url: string; title: string };

export type ChatResult = {
  text: string;
  toolCalls: ToolCall[];
  finish: string;
  usage: Usage;
  model: string;
  /** مصادر البحث إن استُعمل `deepseek_web_search`. */
  sources?: WebSource[];
};

export class LlmError extends Error {
  /** بداية رد غير متوقع، للتشخيص فقط. */
  detail?: string;
  constructor(public code: 'no_key' | 'upstream' | 'timeout' | 'bad_response', public status = 0) {
    super(code);
  }
}

/**
 * جسم رد بلا بث. DeepSeek يرسل أسطر انتظار («: keep-alive» أو فارغة) قبل
 * الجسم في الطلبات الطويلة كالبحث، فتُحذف قبل القراءة.
 */
export function parseChatJson(raw: string): Record<string, unknown> | null {
  const body = raw.split('\n').filter((l) => !l.startsWith(':')).join('\n').trim();
  if (!body) return null;
  try {
    const o = JSON.parse(body);
    return o && typeof o === 'object' ? o as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

/** طلب كامل بلا بث. */
export async function chat(o: ChatOptions, timeoutMs = 20_000): Promise<ChatResult> {
  const key = deepseekKey();
  if (!key) throw new LlmError('no_key');
  let res: Response;
  try {
    res = await fetch(CHAT_ENDPOINT, {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(buildChatBody({ ...o, stream: false })),
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (e) {
    throw new LlmError(String(e).includes('Timeout') ? 'timeout' : 'upstream');
  }
  if (!res.ok) throw new LlmError('upstream', res.status);
  const raw = await res.text().catch(() => '');
  const data = parseChatJson(raw);
  const choice = (data?.choices as Record<string, unknown>[] | undefined)?.[0];
  if (!choice) {
    const e = new LlmError('bad_response');
    // للتشخيص فقط: بداية الرد بلا مفاتيح. لا يُسجَّل إلا في عملية البذرة.
    e.detail = raw.slice(0, 400);
    throw e;
  }
  const msg = (choice.message ?? {}) as Record<string, unknown>;
  const calls = (msg.tool_calls as Record<string, unknown>[] | undefined) ?? [];
  return {
    text: String(msg.content ?? ''),
    toolCalls: calls.map((c) => {
      const fn = (c.function ?? {}) as Record<string, unknown>;
      return { id: String(c.id ?? ''), name: String(fn.name ?? ''), arguments: String(fn.arguments ?? '{}') };
    }),
    finish: String(choice.finish_reason ?? 'stop'),
    usage: parseUsage(data?.usage),
    model: String(data?.model ?? o.model ?? MODELS.fast),
    sources: parseWebSources(msg.server_tool_calls),
  };
}

/** يقرأ المصادر بحذر: الشكل غير موثّق بالكامل، فيُقبل url/link وtitle/name. */
export function parseWebSources(raw: unknown): WebSource[] {
  const out: WebSource[] = [];
  const seen = new Set<string>();
  const visit = (v: unknown) => {
    if (Array.isArray(v)) return v.forEach(visit);
    if (!v || typeof v !== 'object') return;
    const o = v as Record<string, unknown>;
    const url = String(o.url ?? o.link ?? '');
    if (/^https?:\/\//.test(url) && !seen.has(url)) {
      seen.add(url);
      out.push({ url, title: String(o.title ?? o.name ?? '').slice(0, 160) });
    }
    for (const k of ['calls', 'sources', 'results']) if (k in o) visit(o[k]);
  };
  visit(raw);
  return out.slice(0, 12);
}

export type StreamEvent =
  | { type: 'text'; delta: string }
  | { type: 'done'; result: ChatResult };

/**
 * يجمّع أحداث البث (بصيغة OpenAI) إلى نص ونداءات أدوات كاملة.
 * منفصل عن الشبكة حتى يُختبر بأسطر جاهزة.
 */
export class StreamAssembler {
  text = '';
  finish = 'stop';
  usage: Usage = ZERO_USAGE;
  model = '';
  private calls = new Map<number, ToolCall>();

  /** يعالج سطر `data:` واحداً، ويعيد النص الجديد إن وُجد. */
  feed(line: string): string {
    const t = line.trim();
    if (!t.startsWith('data:')) return '';
    const payload = t.slice(5).trim();
    if (!payload || payload === '[DONE]') return '';
    let j: Record<string, unknown>;
    try {
      j = JSON.parse(payload);
    } catch {
      return '';
    }
    if (j.model) this.model = String(j.model);
    if (j.usage) this.usage = parseUsage(j.usage);
    const choice = (j.choices as Record<string, unknown>[] | undefined)?.[0];
    if (!choice) return '';
    if (choice.finish_reason) this.finish = String(choice.finish_reason);
    const delta = (choice.delta ?? {}) as Record<string, unknown>;
    for (const tc of (delta.tool_calls as Record<string, unknown>[] | undefined) ?? []) {
      const idx = Number(tc.index ?? 0);
      const fn = (tc.function ?? {}) as Record<string, unknown>;
      const cur = this.calls.get(idx) ?? { id: '', name: '', arguments: '' };
      if (tc.id) cur.id = String(tc.id);
      if (fn.name) cur.name += String(fn.name);
      if (fn.arguments) cur.arguments += String(fn.arguments);
      this.calls.set(idx, cur);
    }
    const piece = typeof delta.content === 'string' ? delta.content : '';
    this.text += piece;
    return piece;
  }

  result(fallbackModel: string): ChatResult {
    const toolCalls = [...this.calls.entries()].sort((a, b) => a[0] - b[0]).map((e) => e[1])
      .filter((c) => c.name);
    return {
      text: this.text,
      toolCalls,
      finish: this.finish,
      usage: this.usage,
      model: this.model || fallbackModel,
    };
  }
}

/** طلب بالبث. يستدعي `onText` لكل قطعة نص ويعيد النتيجة الكاملة في النهاية. */
export async function chatStream(
  o: ChatOptions,
  onText: (delta: string) => void | Promise<void>,
  opts: { firstTokenMs?: number; totalMs?: number } = {},
): Promise<ChatResult> {
  const key = deepseekKey();
  if (!key) throw new LlmError('no_key');
  const ctrl = new AbortController();
  const total = setTimeout(() => ctrl.abort('total'), opts.totalMs ?? 45_000);
  let first: ReturnType<typeof setTimeout> | undefined = setTimeout(() => ctrl.abort('first'), opts.firstTokenMs ?? 15_000);
  try {
    let res: Response;
    try {
      res = await fetch(CHAT_ENDPOINT, {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(buildChatBody({ ...o, stream: true })),
        signal: ctrl.signal,
      });
    } catch (_) {
      throw new LlmError(ctrl.signal.aborted ? 'timeout' : 'upstream');
    }
    if (!res.ok || !res.body) throw new LlmError('upstream', res.status);
    const asm = new StreamAssembler();
    const reader = res.body.getReader();
    const dec = new TextDecoder();
    let buf = '';
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (first !== undefined) {
          clearTimeout(first);
          first = undefined;
        }
        buf += dec.decode(value, { stream: true });
        let nl: number;
        while ((nl = buf.indexOf('\n')) >= 0) {
          const line = buf.slice(0, nl);
          buf = buf.slice(nl + 1);
          const piece = asm.feed(line);
          if (piece) await onText(piece);
        }
      }
      if (buf) {
        const piece = asm.feed(buf);
        if (piece) await onText(piece);
      }
    } catch (_) {
      throw new LlmError(ctrl.signal.aborted ? 'timeout' : 'upstream');
    }
    return asm.result(o.model ?? MODELS.fast);
  } finally {
    clearTimeout(total);
    if (first !== undefined) clearTimeout(first);
  }
}
