import {
  adminClient,
  assertTenantOwnedByUser,
  corsHeaders,
  json,
  requireMerchantUser,
} from '../_shared/restaurant.ts';

/**
 * Image pipeline stub (§3.13.1):
 * Accepts already-uploaded storage path + metadata; writes variants_json placeholders.
 * Full WebP generation can be added with ImageMagick/wasm later without API change.
 */
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders() });
  }
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const auth = await requireMerchantUser(req);
  if (auth instanceof Response) return auth;

  let body: {
    tenant_uuid?: string;
    menu_item_id?: number;
    image_id?: number;
    original_path?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid_json' }, 400);
  }

  const path = (body.original_path ?? '').trim();
  const tenantUuid = (body.tenant_uuid ?? '').trim();
  if (!path || !tenantUuid || !body.menu_item_id) {
    return json({ error: 'invalid_body' }, 400);
  }

  const forbidden = assertTenantOwnedByUser(tenantUuid, auth.userId);
  if (forbidden) return forbidden;

  // Path must stay under the caller's tenant prefix (storage layout).
  if (!path.startsWith(`${tenantUuid}/`) && !path.includes(`/${tenantUuid}/`)) {
    return json({ error: 'forbidden_path' }, 403);
  }

  const variants = {
    thumb: { webp: path, jpg: path },
    medium: { webp: path, jpg: path },
    large: { webp: path, jpg: path },
  };

  const sb = adminClient();
  if (body.image_id) {
    const { error } = await sb
      .from('restaurant_menu_item_images')
      .update({
        variants_json: variants,
        image_url: path,
        mime: 'image/jpeg',
      })
      .eq('id', body.image_id)
      .eq('tenant_uuid', tenantUuid);
    if (error) return json({ error: error.message }, 500);
  }

  const { data: theme } = await sb
    .from('restaurant_menu_theme')
    .select('id, menu_content_version')
    .eq('tenant_uuid', tenantUuid)
    .maybeSingle();
  if (theme) {
    await sb
      .from('restaurant_menu_theme')
      .update({
        menu_content_version: (theme.menu_content_version ?? 0) + 1,
        updated_at: new Date().toISOString(),
      })
      .eq('id', theme.id)
      .eq('tenant_uuid', tenantUuid);
  }

  return json({
    ok: true,
    variants,
    note: 'webp_generation_deferred_placeholder_paths',
  });
});
