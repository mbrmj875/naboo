/**
 * إكمال Embedded Signup من صفحة ES العامة (بدون JWT).
 * التحقق عبر state موقّع بـ META_APP_SECRET.
 *
 * supabase functions deploy whatsapp-meta-es-complete --no-verify-jwt
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { verifyEsState } from '../whatsapp-gateway/es_state.ts';
import { completeOfficialConnect } from '../whatsapp-gateway/lifecycle/connect_service.ts';
import { adminClient } from '../whatsapp-gateway/admin_client.ts';

const ALLOWED_ORIGINS = new Set([
  'https://naboo-admin.vercel.app',
  'https://admin.naboo.fun',
]);

function corsHeaders(req: Request): HeadersInit {
  const origin = req.headers.get('Origin') ?? '';
  const allowed = ALLOWED_ORIGINS.has(origin);
  return {
    ...(allowed ? { 'Access-Control-Allow-Origin': origin } : {}),
    'Access-Control-Allow-Headers':
      'content-type, x-client-info, apikey',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }
  if (req.method !== 'POST') {
    return Response.json(
      { ok: false, error: 'method_not_allowed' },
      { status: 405, headers: corsHeaders(req) },
    );
  }

  let body: Record<string, unknown> = {};
  try {
    body = await req.json() as Record<string, unknown>;
  } catch {
    return Response.json(
      { ok: false, error: 'invalid_json', message_ar: 'طلب غير صالح.' },
      { status: 400, headers: corsHeaders(req) },
    );
  }

  const state = String(body.state ?? '').trim();
  const code = String(body.code ?? body.oauth_code ?? '').trim();
  const session = (body.session && typeof body.session === 'object')
    ? body.session as Record<string, unknown>
    : {};
  // تلميحات فقط. completeOfficialConnect يتجاهلها إن لم يؤكدها التوكن.
  const wabaId = String(
    body.waba_id ?? body.wabaId ?? session.waba_id ?? '',
  ).trim();
  const phoneNumberId = String(
    body.phone_number_id ?? body.phoneNumberId ?? session.phone_number_id ?? '',
  ).trim();
  const fromPhone = String(
    body.from_phone ?? body.phone_number ?? body.display_phone_number ?? '',
  ).trim();
  const signupEvent = String(session.event ?? body.signup_event ?? '').trim();
  const oauthRedirectUri = String(
    body.redirect_uri ?? body.oauth_redirect_uri ?? '',
  ).trim();

  const verified = await verifyEsState(state);
  if (!verified.ok) {
    const ar = verified.detail === 'state_expired'
      ? 'انتهت جلسة الربط. ارجع للتطبيق وابدأ من جديد.'
      : verified.detail === 'meta_app_secret_missing'
      ? 'إعداد الخادم غير مكتمل. تواصل مع دعم نابو.'
      : 'جلسة الربط غير صالحة. ابدأ الربط من تطبيق نابو.';
    return Response.json(
      { ok: false, error: verified.detail, message_ar: ar },
      { status: 400, headers: corsHeaders(req) },
    );
  }

  if (!code || code.length > 2048) {
    return Response.json(
      {
        ok: false,
        error: 'oauth_code_missing',
        message_ar: 'لم يكتمل التفويض من Meta. أعد المحاولة.',
      },
      { status: 400, headers: corsHeaders(req) },
    );
  }

  const db = adminClient() ?? createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  if (verified.nonce) {
    const { error: nonceError } = await db.from('whatsapp_es_nonces').insert({
      nonce: verified.nonce,
      tenant_user_id: verified.tenantUserId,
    });
    if (nonceError) {
      const reused = nonceError.code === '23505';
      return Response.json(
        {
          ok: false,
          error: reused ? 'state_reused' : 'state_consume_failed',
          message_ar: reused
            ? 'استُخدمت جلسة الربط من قبل. ابدأ من التطبيق مرة أخرى.'
            : 'تعذّر تثبيت جلسة الربط. أعد المحاولة من التطبيق.',
        },
        { status: 400, headers: corsHeaders(req) },
      );
    }
  }

  // تأكد أن المزود cloud_api قبل الإكمال
  await db.from('tenant_whatsapp_gateways').upsert(
    {
      user_id: verified.tenantUserId,
      evolution_instance_name:
        `shop_${verified.tenantUserId.replace(/-/g, '_')}`,
      whatsapp_provider: 'cloud_api',
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'user_id' },
  );

  const result = await completeOfficialConnect(db, {
    tenantUserId: verified.tenantUserId,
    wabaId: wabaId || undefined,
    phoneNumberId: phoneNumberId || undefined,
    fromPhoneE164: fromPhone || undefined,
    oauthCode: code,
    oauthRedirectUri: oauthRedirectUri || undefined,
    signupEvent: signupEvent || undefined,
  });

  // إن نجح بدون waba في الطلب لكن التوكن حلّها داخلياً — الصف يُحدَّث في completeOfficialConnect
  return Response.json(
    {
      ok: result.ok,
      detail: result.detail,
      message_ar: result.message_ar ??
        (result.ok
          ? 'تم الربط بنجاح. جاري تجهيز قالب الرسائل — ارجع لتطبيق نابو.'
          : 'تعذّر إكمال الربط.'),
    },
    {
      status: result.ok ? 200 : 400,
      headers: corsHeaders(req),
    },
  );
});
