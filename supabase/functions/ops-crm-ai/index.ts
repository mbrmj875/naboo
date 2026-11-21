/**
 * اقتراح رد AI لـ Ops CRM — يستخدم DEEPSEEK_API_KEY من أسرار Supabase.
 * المصادقة: NABOO_OPS_CONTEXT_SECRET (أو service_role JWT).
 */

const ENDPOINT = 'https://api.deepseek.com/chat/completions';
const MODEL = 'deepseek-chat';
const TIMEOUT_MS = 20000;

const PRODUCT_BRAIN_AR = `
أنت مساعد منصة نابو (NABOO) — تتكلم كمن بنى التطبيق ويهتم بالتاجر.
نابو: نظام إدارة محلات (مخزون، فواتير، غيار زيت، غسيل، مطعم حسب التخصص) مع اشتراك سحابي وترخيص أجهزة.
عند السؤال عن الاشتراك: اشرح التجربة، التجديد، عدد الأجهزة، ولا تخترع أسعاراً غير مذكورة.
وجّه المستخدم بخطوات عربية واضحة وقصيرة. إن لم تعرف قل ذلك واقترح تواصل فريق نابو.
`.trim();

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-ops-context-secret',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

function isAuthorized(req: Request): boolean {
  const expected = Deno.env.get('NABOO_OPS_CONTEXT_SECRET')?.trim() ?? '';
  const provided = (req.headers.get('x-ops-context-secret') ?? '').trim();
  // Require configured shared secret — do not trust unsigned JWT role claims.
  if (!expected || !provided || provided.length !== expected.length) {
    return false;
  }
  // Constant-time-ish compare for Deno (no node:crypto).
  let mismatch = 0;
  for (let i = 0; i < expected.length; i++) {
    mismatch |= expected.charCodeAt(i) ^ provided.charCodeAt(i);
  }
  return mismatch === 0;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== 'POST') {
    return json({ ok: false, error: 'method_not_allowed' }, 405);
  }

  if (!isAuthorized(req)) {
    return json({ ok: false, error: 'unauthorized' }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'invalid_json' }, 400);
  }

  const context = String(body.context ?? '').trim().slice(0, 4000);
  const historyText = String(body.history_text ?? '').trim().slice(0, 6000);
  const latest = String(body.latest_message ?? '').trim().slice(0, 2000);
  if (!latest) {
    return json({ ok: false, error: 'latest_message_required' }, 400);
  }

  const apiKey = Deno.env.get('DEEPSEEK_API_KEY')?.trim();
  if (!apiKey) {
    return json({
      ok: true,
      text:
        'مرحباً، فريق نابو هنا. أخبرنا بمشكلتك أو طلب الاشتراك وسنساعدك مباشرة.',
      confidence: 0.2,
      fallback: true,
    });
  }

  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      signal: AbortSignal.timeout(TIMEOUT_MS),
      body: JSON.stringify({
        model: Deno.env.get('DEEPSEEK_MODEL')?.trim() || MODEL,
        temperature: 0.4,
        max_tokens: 500,
        messages: [
          { role: 'system', content: PRODUCT_BRAIN_AR },
          {
            role: 'user',
            content: [
              'سياق التاجر/المهتم:',
              context || '(غير متوفر)',
              '',
              'سجل المحادثة الأخير:',
              historyText || '(فارغ)',
              '',
              'آخر رسالة من العميل:',
              latest,
              '',
              'اكتب ردّاً عربياً واحداً جاهزاً للإرسال (بدون عناوين داخلية).',
            ].join('\n'),
          },
        ],
      }),
    });

    if (!res.ok) {
      return json({
        ok: true,
        text:
          'عذراً، تعذر توليد رد الآن. سيراجع فريق نابو رسالتك قريباً.',
        confidence: 0.15,
        fallback: true,
      });
    }

    const data = await res.json() as {
      choices?: { message?: { content?: string } }[];
    };
    const text = (data.choices?.[0]?.message?.content ?? '').trim();
    if (!text) {
      return json({
        ok: true,
        text:
          'شكراً لتواصلك مع نابو. كيف نقدر نساعدك بالاشتراك أو استخدام التطبيق؟',
        confidence: 0.25,
        fallback: true,
      });
    }

    return json({
      ok: true,
      text: text.slice(0, 2000),
      confidence: 0.7,
    });
  } catch (e) {
    console.warn('ops-crm-ai failed', String(e).slice(0, 160));
    return json({
      ok: true,
      text: 'تعذر الاتصال بالمساعد مؤقتاً. سيراجع الفريق رسالتك.',
      confidence: 0.1,
      fallback: true,
    });
  }
});
