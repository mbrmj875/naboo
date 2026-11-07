import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { debitWalletForSend, isWalletSchemaMissing } from './wallet.ts';

function clientReturning(result: { data: unknown; error: unknown }) {
  return { rpc: () => Promise.resolve(result) } as unknown as SupabaseClient;
}

const debitOpts = { tenantUserId: 't1', idempotencyKey: 'k1' };

Deno.test('schema is missing only for the two Postgres codes', () => {
  assertEquals(isWalletSchemaMissing({ code: '42883' }), true);
  assertEquals(isWalletSchemaMissing({ code: '42P01' }), true);
  assertEquals(isWalletSchemaMissing({ code: '42501' }), false);
  assertEquals(isWalletSchemaMissing({ code: 'PGRST301' }), false);
  assertEquals(isWalletSchemaMissing(null), false);
});

Deno.test('permission denied naming the function blocks the send', async () => {
  const result = await debitWalletForSend(
    clientReturning({
      data: null,
      error: {
        code: '42501',
        message: 'permission denied for function wa_wallet_debit_one',
      },
    }),
    debitOpts,
  );
  assertEquals(result.ok, false);
  assertEquals(result.error, 'wallet_error');
});

Deno.test('other error text saying does not exist blocks the send', async () => {
  const result = await debitWalletForSend(
    clientReturning({
      data: null,
      error: { code: '23503', message: 'tenant does not exist' },
    }),
    debitOpts,
  );
  assertEquals(result.ok, false);
});

Deno.test('a truly missing function still skips the debit', async () => {
  const result = await debitWalletForSend(
    clientReturning({
      data: null,
      error: { code: '42883', message: 'function does not exist' },
    }),
    debitOpts,
  );
  assertEquals(result, { ok: true, exempt: true });
});

Deno.test('a successful debit passes through', async () => {
  const result = await debitWalletForSend(
    clientReturning({ data: { ok: true }, error: null }),
    debitOpts,
  );
  assertEquals(result.ok, true);
  assertEquals(result.exempt, false);
});
