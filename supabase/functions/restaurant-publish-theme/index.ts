import {
  adminClient,
  assertTenantOwnedByUser,
  corsHeaders,
  json,
  requireMerchantUser,
  validateThemeJson,
} from '../_shared/restaurant.ts';

/**
 * Publish: draft_json → published_json, bump published_version + menu_content_version.
 * Broadcast Realtime on channel restaurant_theme_{tenant_id} with {published_version} only.
 */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const auth = await requireMerchantUser(req);
  if (auth instanceof Response) return auth;

  let body: { tenant_uuid?: string; published_by?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }
  const tenantUuid = (body.tenant_uuid ?? '').trim();
  if (!tenantUuid) return json({ error: 'invalid_body' }, 400);

  const forbidden = assertTenantOwnedByUser(tenantUuid, auth.userId);
  if (forbidden) return forbidden;

  const sb = adminClient();
  const { data: row, error: fetchErr } = await sb
    .from('restaurant_menu_theme')
    .select('*')
    .eq('tenant_uuid', tenantUuid)
    .is('deleted_at', null)
    .maybeSingle();
  if (fetchErr || !row) {
    return json({ error: 'theme_not_found' }, 404);
  }

  const err = validateThemeJson(row.draft_json);
  if (err) return json({ error: 'theme_invalid', message: err }, 400);

  const publishedVersion = (row.published_version ?? 0) + 1;
  const menuContentVersion = (row.menu_content_version ?? 0) + 1;

  const { error: updErr } = await sb
    .from('restaurant_menu_theme')
    .update({
      published_json: row.draft_json,
      published_version: publishedVersion,
      menu_content_version: menuContentVersion,
      published_at: new Date().toISOString(),
      published_by: body.published_by ?? auth.userId,
      updated_at: new Date().toISOString(),
    })
    .eq('id', row.id)
    .eq('tenant_uuid', tenantUuid);
  if (updErr) return json({ error: updErr.message }, 500);

  try {
    const channel = sb.channel(`restaurant_theme_${tenantUuid}`);
    await channel.subscribe();
    await channel.send({
      type: 'broadcast',
      event: 'theme_published',
      payload: { published_version: publishedVersion },
    });
    await sb.removeChannel(channel);
  } catch (e) {
    console.error('realtime broadcast failed', e);
  }

  return json({
    ok: true,
    published_version: publishedVersion,
    menu_content_version: menuContentVersion,
  });
});
