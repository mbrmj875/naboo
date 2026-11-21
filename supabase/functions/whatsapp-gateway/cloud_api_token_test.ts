import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { resolveGraphAccessToken } from './cloud_api.ts';
import { deleteProviderSecret } from './provider_secrets.ts';
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const TENANT = '11111111-2222-3333-4444-555555555555';
const ENV: Record<string, string> = {
  SHARED_SENDER_PHONE_NUMBER_ID: 'naboo-phone',
  SHARED_SENDER_WABA_ID: 'naboo-waba',
  SHARED_SENDER_TOKEN: 'naboo-token',
  [`WHATSAPP_CLOUD_TOKEN_${TENANT.replace(/-/g, '_')}`]: 'store-token',
};

async function withEnv(fn: () => Promise<void>) {
  const before = new Map<string, string | undefined>();
  for (const k of [...Object.keys(ENV), 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'WHATSAPP_CLOUD_TOKEN']) {
    before.set(k, Deno.env.get(k));
    Deno.env.delete(k);
  }
  for (const [k, v] of Object.entries(ENV)) Deno.env.set(k, v);
  try {
    await fn();
  } finally {
    for (const [k, v] of before) {
      if (v === undefined) Deno.env.delete(k);
      else Deno.env.set(k, v);
    }
  }
}

Deno.test('رقم نابو يستخدم توكن نابو حتى لو بقي توكن قديم للمحل', () =>
  withEnv(async () => {
    assertEquals(
      await resolveGraphAccessToken({ userId: TENANT, phoneNumberId: 'naboo-phone' }),
      'naboo-token',
    );
    assertEquals(
      await resolveGraphAccessToken({ userId: TENANT, wabaId: 'naboo-waba' }),
      'naboo-token',
    );
  }));

Deno.test('رقم المحل يستخدم توكن المحل', () =>
  withEnv(async () => {
    assertEquals(
      await resolveGraphAccessToken({ userId: TENANT, phoneNumberId: 'store-phone' }),
      'store-token',
    );
  }));

Deno.test('حذف السر يخص المستأجر والمزود والنوع فقط', () =>
  withEnv(async () => {
    const filters: Record<string, string> = {};
    let table = '';
    const query = {
      delete: () => query,
      eq: (k: string, v: string) => {
        filters[k] = v;
        return query;
      },
      then: (ok: (r: { error: null }) => unknown) => ok({ error: null }),
    };
    const fake = {
      from: (t: string) => {
        table = t;
        return query;
      },
    } as unknown as SupabaseClient;
    const r = await deleteProviderSecret(fake, {
      tenantUserId: TENANT,
      provider: 'cloud_api',
      secretKind: 'access_token',
    });
    assertEquals(r.ok, true);
    assertEquals(table, 'whatsapp_provider_secrets');
    assertEquals(filters, {
      tenant_user_id: TENANT,
      provider: 'cloud_api',
      secret_kind: 'access_token',
    });
  }));
