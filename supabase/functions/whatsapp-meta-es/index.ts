/**
 * لم يعد يخدم HTML — Supabase يحوّل text/html إلى text/plain فيظهر المصدر كنص.
 * نُحوّل إلى صفحة ثابتة على Vercel (admin-web/public/whatsapp-meta-es.html).
 *
 * supabase functions deploy whatsapp-meta-es --no-verify-jwt
 */

const FALLBACK =
  Deno.env.get('META_ES_PAGE_URL')?.trim() ||
  'https://naboo-admin.vercel.app/whatsapp-meta-es';

Deno.serve((req) => {
  const incoming = new URL(req.url);
  const target = new URL(FALLBACK);
  for (const [k, v] of incoming.searchParams.entries()) {
    target.searchParams.set(k, v);
  }
  if (!target.searchParams.get('app_id')) {
    const appId = Deno.env.get('META_APP_ID')?.trim();
    if (appId) target.searchParams.set('app_id', appId);
  }
  if (!target.searchParams.get('config_id')) {
    const configId =
      Deno.env.get('META_ES_CONFIG_ID')?.trim() ||
      Deno.env.get('META_EMBEDDED_SIGNUP_CONFIG_ID')?.trim();
    if (configId) target.searchParams.set('config_id', configId);
  }
  return Response.redirect(target.toString(), 302);
});
