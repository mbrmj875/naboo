/**
 * قياسات المرحلة ب0 لمساعد نابو (م0-1، م0-8، م0-9، م0-10، م0-16، م0-17).
 *
 * دالة مؤقتة: تمرّر طلباً واحداً إلى DeepSeek بالمفتاح المحفوظ في أسرار الخادم،
 * وتعيد الرد الخام مع الزمن، حتى نقيس الأسماء والبث والأدوات والصور والكلفة.
 *
 * الحماية: رمز لمرة واحدة لا يُحفظ في المستودع، يُقارن ببصمته SHA-256 فقط.
 * لا تقرأ قاعدة البيانات ولا تكتب فيها. تُعاد نشرها كدالة معطَّلة (410) بعد القياس.
 */

const TOKEN_SHA256 = 'b9767a77cf55927b2312e806a820c258127884f35ecdb2caef3e0338512a1a0a';
const ALLOWED_PATHS = new Set(['/models', '/chat/completions', '/user/balance']);
const MAX_BODY = 600_000;

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method' }, 405);
  const token = req.headers.get('x-probe-token') ?? '';
  if (!token || (await sha256Hex(token)) !== TOKEN_SHA256) {
    return json({ error: 'unauthorized' }, 401);
  }
  const key = Deno.env.get('DEEPSEEK_API_KEY')?.trim();
  if (!key) return json({ error: 'no_key' }, 500);

  const raw = await req.text();
  if (raw.length > MAX_BODY) return json({ error: 'too_large' }, 413);
  let input: { path?: string; method?: string; body?: unknown };
  try {
    input = JSON.parse(raw);
  } catch {
    return json({ error: 'bad_json' }, 400);
  }
  const path = String(input.path ?? '');
  if (!ALLOWED_PATHS.has(path)) return json({ error: 'path_not_allowed' }, 400);
  const method = input.method === 'GET' ? 'GET' : 'POST';

  const t0 = performance.now();
  const res = await fetch(`https://api.deepseek.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: method === 'POST' ? JSON.stringify(input.body ?? {}) : undefined,
  });

  // البث: نجمع الأحداث كما وصلت مع زمن أول حدث، لنعرف شكلها.
  const isStream = (res.headers.get('content-type') ?? '').includes('text/event-stream');
  if (isStream && res.body) {
    const reader = res.body.getReader();
    const dec = new TextDecoder();
    let firstMs: number | null = null;
    let text = '';
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (firstMs === null) firstMs = Math.round(performance.now() - t0);
      text += dec.decode(value, { stream: true });
      if (text.length > 400_000) break;
    }
    return json({
      status: res.status,
      stream: true,
      first_event_ms: firstMs,
      total_ms: Math.round(performance.now() - t0),
      events: text.split('\n').filter((l) => l.startsWith('data:')).map((l) => l.slice(5).trim()),
    });
  }

  const text = await res.text();
  let parsed: unknown = text;
  try {
    parsed = JSON.parse(text);
  } catch { /* نص خام */ }
  return json({
    status: res.status,
    stream: false,
    total_ms: Math.round(performance.now() - t0),
    response: parsed,
  });
});
