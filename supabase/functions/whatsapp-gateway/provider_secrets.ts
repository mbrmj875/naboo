/**
 * أسرار مزود واتساب لكل مستأجر — service_role فقط.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { adminClient, writeClient } from './admin_client.ts';

export async function upsertProviderSecret(
  supabase: SupabaseClient,
  args: {
    tenantUserId: string;
    provider: string;
    secretKind: string;
    secretValue: string;
  },
): Promise<{ ok: boolean; detail?: string }> {
  const value = args.secretValue.trim();
  if (!value) return { ok: false, detail: 'empty_secret' };
  const db = writeClient(supabase);
  const now = new Date().toISOString();
  const { error } = await db.from('whatsapp_provider_secrets').upsert(
    {
      tenant_user_id: args.tenantUserId,
      provider: args.provider,
      secret_kind: args.secretKind,
      secret_value: value,
      updated_at: now,
    },
    { onConflict: 'tenant_user_id,provider,secret_kind' },
  );
  if (error) return { ok: false, detail: error.message.slice(0, 200) };
  return { ok: true };
}

export async function readProviderSecret(
  tenantUserId: string,
  provider: string,
  secretKind: string,
): Promise<string | null> {
  const db = adminClient();
  if (!db) return null;
  const { data } = await db
    .from('whatsapp_provider_secrets')
    .select('secret_value')
    .eq('tenant_user_id', tenantUserId)
    .eq('provider', provider)
    .eq('secret_kind', secretKind)
    .maybeSingle();
  const v = String(data?.secret_value ?? '').trim();
  return v || null;
}

/** يحذف سراً واحداً للمستأجر. عدم وجود الصف ليس خطأ. */
export async function deleteProviderSecret(
  supabase: SupabaseClient,
  args: {
    tenantUserId: string;
    provider: string;
    secretKind: string;
  },
): Promise<{ ok: boolean; detail?: string }> {
  const db = writeClient(supabase);
  const { error } = await db
    .from('whatsapp_provider_secrets')
    .delete()
    .eq('tenant_user_id', args.tenantUserId)
    .eq('provider', args.provider)
    .eq('secret_kind', args.secretKind);
  if (error) return { ok: false, detail: error.message.slice(0, 200) };
  return { ok: true };
}
