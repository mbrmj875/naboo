import {
  adminClient,
  assertTenantOwnedByUser,
  corsHeaders,
  json,
  requireMerchantUser,
  validateThemeJson,
} from '../_shared/restaurant.ts';

/** Save draft only — no Realtime broadcast (§13.5.9). */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const auth = await requireMerchantUser(req);
  if (auth instanceof Response) return auth;

  let body: { tenant_uuid?: string; draft_json?: unknown; updated_by?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }

  const tenantUuid = (body.tenant_uuid ?? '').trim();
  if (!tenantUuid || body.draft_json == null) {
    return json({ error: 'invalid_body' }, 400);
  }
  const forbidden = assertTenantOwnedByUser(tenantUuid, auth.userId);
  if (forbidden) return forbidden;

  const err = validateThemeJson(body.draft_json);
  if (err) return json({ error: 'theme_invalid', message: err }, 400);

  const sb = adminClient();
  const { data: existing } = await sb
    .from('restaurant_menu_theme')
    .select('id, draft_version')
    .eq('tenant_uuid', tenantUuid)
    .is('deleted_at', null)
    .maybeSingle();

  if (existing) {
    const { data, error } = await sb
      .from('restaurant_menu_theme')
      .update({
        draft_json: body.draft_json,
        draft_version: (existing.draft_version ?? 0) + 1,
        updated_at: new Date().toISOString(),
        updated_by: body.updated_by ?? auth.userId,
      })
      .eq('id', existing.id)
      .eq('tenant_uuid', tenantUuid)
      .select('draft_version, published_version')
      .single();
    if (error) return json({ error: error.message }, 500);
    return json({ ok: true, ...data });
  }

  const { data, error } = await sb
    .from('restaurant_menu_theme')
    .insert({
      tenant_uuid: tenantUuid,
      draft_json: body.draft_json,
      draft_version: 1,
      published_version: 0,
      menu_content_version: 0,
      updated_by: body.updated_by ?? auth.userId,
    })
    .select('draft_version, published_version')
    .single();
  if (error) return json({ error: error.message }, 500);
  return json({ ok: true, ...data });
});
