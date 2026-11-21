/**
 * تحليل مبالغ ملاحظات بطاقة غيار الزيت — DeepSeek JSON فقط.
 * لا يُطبَّق مبلغ تلقائياً؛ التطبيق يعرض البنود للتأكيد اليدوي.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const ENDPOINT = 'https://api.deepseek.com/chat/completions';
const MODEL = 'deepseek-chat';
const TIMEOUT_MS = 18000;
const MAX_NOTES = 1200;

const rateMap = new Map<string, { count: number; windowStart: number }>();
const RATE_LIMIT = 20;
const RATE_WINDOW_MS = 60_000;

function corsHeaders(req: Request): HeadersInit {
  const origin = req.headers.get('Origin') ?? '*';
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}

function apiKey(): string | null {
  return Deno.env.get('DEEPSEEK_API_KEY')?.trim() || null;
}

function allowRate(userId: string): boolean {
  const now = Date.now();
  const cur = rateMap.get(userId);
  if (!cur || now - cur.windowStart > RATE_WINDOW_MS) {
    rateMap.set(userId, { count: 1, windowStart: now });
    return true;
  }
  if (cur.count >= RATE_LIMIT) return false;
  cur.count += 1;
  return true;
}

const SYSTEM = `
أنت محلّل مبالغ لملاحظات فني غيار زيت في العراق (دينار عراقي، أرقام صحيحة بدون كسور).
المهمّة: فهم النص الصوتي/المكتوب واستخراج بنود مبالغ جاهزة للإضافة على فاتورة الغيار.

قواعد صارمة:
1) أرجع JSON فقط بالشكل:
{
  "summary": "جملة عربية قصيرة تشرح المنطق",
  "confidence": 0.0إلى1.0,
  "items": [
    {
      "dinars": 20000,
      "type": "lineTotal" | "unit" | "unknown",
      "label": "وصف عربي قصير للبند",
      "selected": true
    }
  ]
}
2) type:
   - unit = سعر القطعة الواحدة (لا تجمعه مع مجموعه إن وُجد حاصل)
   - lineTotal = مجموع بند / حاصل كمية×سعر / مبلغ مدفوع لخدمة
   - unknown = مبلغ واضح بلا تصنيف أدق
3) تجنّب الجمع المزدوج: إذا ذُكر سعر وحدة ثم مجموع لنفس البنود، اختر المجموع (selected=true) واترك الوحدة selected=false أو احذف الوحدة.
4) يجوز حساب كمية×سعر ذهنياً وإرجاع بند lineTotal واحد (مثال: فلتران بسعر 10000 → dinars:20000).
5) لا تُدخل أرقام هواتف/موديل/عداد/سنة.
6) حد أقصى 8 بنود. dinars بين 250 و 50000000.
7) العملة دينار عراقي فقط — لا فلوس/دولار.
`.trim();

type AiItem = {
  dinars: number;
  type: 'unit' | 'lineTotal' | 'unknown';
  label: string;
  selected: boolean;
};

function sanitizeItems(raw: unknown): AiItem[] {
  if (!Array.isArray(raw)) return [];
  const out: AiItem[] = [];
  for (const row of raw.slice(0, 8)) {
    if (!row || typeof row !== 'object') continue;
    const o = row as Record<string, unknown>;
    let dinars = 0;
    const d = o.dinars ?? o.amount ?? o.iqd;
    if (typeof d === 'number') dinars = Math.round(d);
    else if (typeof d === 'string') {
      dinars = parseInt(d.replace(/[^\d]/g, ''), 10) || 0;
    }
    if (dinars < 250 || dinars > 50_000_000) continue;

    const tRaw = String(o.type ?? 'unknown').toLowerCase();
    let type: AiItem['type'] = 'unknown';
    if (tRaw.includes('unit') || tRaw.includes('سعر')) type = 'unit';
    else if (
      tRaw.includes('line') ||
      tRaw.includes('total') ||
      tRaw.includes('مجموع')
    ) {
      type = 'lineTotal';
    }

    const label = String(o.label ?? o.context ?? '').trim().slice(0, 80);
    let selected = o.selected === true || o.selected === 1;
    if (o.selected == null) selected = type !== 'unit';

    out.push({
      dinars,
      type,
      label: label || (type === 'unit' ? 'سعر وحدة' : type === 'lineTotal' ? 'مجموع بند' : 'مبلغ'),
      selected,
    });
  }

  const hasLine = out.some((i) => i.type === 'lineTotal');
  if (hasLine) {
    for (const i of out) {
      if (i.type === 'unit') i.selected = false;
    }
  }
  return out;
}

function parseModelJson(content: string): {
  items: AiItem[];
  summary: string;
  confidence: number;
} | null {
  const trimmed = content.trim();
  let text = trimmed;
  const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence?.[1]) text = fence[1].trim();
  try {
    const obj = JSON.parse(text) as Record<string, unknown>;
    const items = sanitizeItems(obj.items);
    if (items.length === 0) return null;
    const summary = String(obj.summary ?? '').trim().slice(0, 240);
    const confidence = typeof obj.confidence === 'number'
      ? Math.min(1, Math.max(0, obj.confidence))
      : 0.7;
    return { items, summary, confidence };
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }
  if (req.method === 'GET') {
    return json(req, { ok: true, service: 'oil-notes-money' });
  }
  if (req.method !== 'POST') {
    return json(req, { ok: false, error: 'method_not_allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
  const supabaseAnon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  if (!supabaseUrl || !supabaseAnon) {
    return json(req, { ok: false, error: 'server_misconfigured' }, 500);
  }

  const supabase = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) {
    return json(req, { ok: false, error: 'unauthorized' }, 401);
  }
  if (!allowRate(userData.user.id)) {
    return json(req, { ok: false, error: 'rate_limited' }, 429);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json() as Record<string, unknown>;
  } catch {
    return json(req, { ok: false, error: 'invalid_json' }, 400);
  }

  const notes = String(body.notes ?? body.text ?? '').trim().slice(0, MAX_NOTES);
  if (notes.length < 3) {
    return json(req, { ok: false, error: 'notes_required' }, 400);
  }

  const localHint = body.local_hint;
  let localHintText = '';
  if (localHint && typeof localHint === 'object') {
    try {
      localHintText = JSON.stringify(localHint).slice(0, 800);
    } catch {
      localHintText = '';
    }
  }

  const key = apiKey();
  if (!key) {
    return json(req, { ok: false, error: 'ai_disabled' }, 503);
  }

  const userContent = [
    'حلّل ملاحظات الفني التالية واستخرج بنود المبالغ:',
    notes,
    localHintText
      ? `تلميح من المحلل المحلي (قد يكون ناقصاً — صحّح إن لزم):\n${localHintText}`
      : '',
  ].filter(Boolean).join('\n\n');

  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: MODEL,
        temperature: 0.15,
        max_tokens: 700,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: SYSTEM },
          { role: 'user', content: userContent },
        ],
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    if (!res.ok) {
      console.warn('oil-notes-money deepseek http', res.status);
      return json(req, { ok: false, error: 'ai_http' }, 502);
    }

    const data = await res.json() as {
      choices?: Array<{ message?: { content?: string } }>;
    };
    const parsed = parseModelJson(data.choices?.[0]?.message?.content ?? '');
    if (!parsed) {
      return json(req, { ok: false, error: 'ai_parse' }, 502);
    }

    return json(req, {
      ok: true,
      source: 'ai',
      summary: parsed.summary,
      confidence: parsed.confidence,
      items: parsed.items,
    });
  } catch (e) {
    console.warn('oil-notes-money failed', String(e).slice(0, 200));
    return json(req, { ok: false, error: 'ai_failed' }, 502);
  }
});
