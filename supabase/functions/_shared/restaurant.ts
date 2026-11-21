import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

export function adminClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function corsHeaders(): HeadersInit {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type, x-cron-secret',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders(), 'Content-Type': 'application/json; charset=utf-8' },
  });
}

export function clientIp(req: Request): string {
  return (
    req.headers.get('cf-connecting-ip') ||
    req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
    'unknown'
  );
}

const THEME_ROOT = new Set([
  'version',
  'preset_key',
  'menu_language',
  'font_family',
  'colors',
  'identity',
  'toggles',
]);
const PRESETS = new Set([
  'classic',
  'modern',
  'dark',
  'cafe',
  'elegant',
  'minimal',
]);
const FONTS = new Set([
  'tajawal',
  'cairo',
  'ibmplex_arabic',
  'amiri',
  'almarai',
  'rubik',
]);
const LANGS = new Set(['ar', 'en', 'bilingual']);
const HEX = /^#[0-9A-Fa-f]{6}$/;

/** Matches Flutter ThemeSchemaValidator — unknown keys rejected. */
export function validateThemeJson(raw: unknown): string | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return 'الثيم يجب أن يكون كائناً JSON';
  }
  const json = raw as Record<string, unknown>;
  for (const k of Object.keys(json)) {
    if (!THEME_ROOT.has(k)) return `مفتاح غير مسموح في الثيم: ${k}`;
  }
  for (const k of THEME_ROOT) {
    if (!(k in json)) return `حقل مطلوب ناقص: ${k}`;
  }
  if (json.version !== 1) return 'إصدار الثيم غير مدعوم';
  if (!PRESETS.has(String(json.preset_key))) return 'preset غير معروف';
  if (!LANGS.has(String(json.menu_language))) return 'لغة المنيو غير صالحة';
  if (!FONTS.has(String(json.font_family))) return 'خط غير مسموح';
  if ('layout_direction' in json) {
    return 'اتجاه التخطيط مشتق من اللغة ولا يُخزَّن';
  }
  const colors = json.colors as Record<string, unknown>;
  if (!colors || typeof colors !== 'object') return 'ألوان الثيم غير صالحة';
  for (const ck of ['primary', 'accent', 'bg', 'text']) {
    const v = String(colors[ck] ?? '');
    if (!HEX.test(v)) return `لون ${ck} يجب أن يكون بصيغة #RRGGBB`;
  }
  return null;
}

export async function resolveTenantUuid(
  sb: SupabaseClient,
  tenantSlug: string,
): Promise<string | null> {
  const { data } = await sb
    .from('restaurant_tenant_slugs')
    .select('tenant_uuid')
    .eq('tenant_slug', tenantSlug.trim())
    .maybeSingle();
  return data?.tenant_uuid ?? null;
}

/**
 * Require a real authenticated user JWT (not merely "Bearer …" present).
 * Rejects missing/invalid tokens. Merchant tenant_uuid must equal auth.uid().
 */
export async function requireMerchantUser(
  req: Request,
): Promise<{ userId: string } | Response> {
  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) {
    return json({ error: 'unauthorized' }, 401);
  }
  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user?.id) {
    return json({ error: 'unauthorized' }, 401);
  }
  // Reject obviously malformed / empty roles that are not logged-in users.
  const role = (data.user.role ?? '').toString();
  if (role === 'anon') {
    return json({ error: 'unauthorized' }, 401);
  }
  return { userId: data.user.id };
}

export function assertTenantOwnedByUser(
  tenantUuid: string,
  userId: string,
): Response | null {
  if (tenantUuid.trim() !== userId) {
    return json({ error: 'forbidden_tenant' }, 403);
  }
  return null;
}
