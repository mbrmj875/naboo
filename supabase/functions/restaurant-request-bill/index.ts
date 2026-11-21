import {
  adminClient,
  corsHeaders,
  json,
  resolveTenantUuid,
} from '../_shared/restaurant.ts';

/** Request bill: session open → awaiting_payment (§4 / §5). */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  let body: { session_id?: number; tenant_slug?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }
  const sessionId = body.session_id;
  const tenantSlug = (body.tenant_slug ?? '').trim();
  if (!sessionId || !tenantSlug) {
    return json({ error: 'invalid_body' }, 400);
  }

  const sb = adminClient();
  const tenantUuid = await resolveTenantUuid(sb, tenantSlug);
  if (!tenantUuid) {
    return json({ error: 'tenant_not_found' }, 404);
  }

  const { data: session, error } = await sb
    .from('restaurant_sessions')
    .select('id, state, tenant_uuid')
    .eq('id', sessionId)
    .eq('tenant_uuid', tenantUuid)
    .is('deleted_at', null)
    .maybeSingle();
  if (error || !session) return json({ error: 'session_not_found' }, 404);
  if (session.state !== 'open') {
    return json({ error: 'session_not_open', state: session.state }, 409);
  }

  const { error: updErr } = await sb
    .from('restaurant_sessions')
    .update({ state: 'awaiting_payment' })
    .eq('id', sessionId)
    .eq('tenant_uuid', tenantUuid)
    .eq('state', 'open');
  if (updErr) return json({ error: updErr.message }, 500);

  return json({ ok: true, session_id: sessionId, state: 'awaiting_payment' });
});
