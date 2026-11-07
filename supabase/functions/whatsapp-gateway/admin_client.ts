/**
 * عميل service_role لكتابات البنية الجديدة (قوالب / سجلات / أسرار).
 */

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

export function adminClient(): SupabaseClient | null {
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return null;
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** يفضّل admin للكتابة؛ يسقط لعميل المستخدم إن تعذّر (تطوير محلي). */
export function writeClient(
  userClient: SupabaseClient,
): SupabaseClient {
  return adminClient() ?? userClient;
}
