import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { applySendBlock, checkSendBlock, readSendBlock } from './send_block.ts';
import { debitWalletForSend } from './wallet.ts';

type Rows = { gateway?: Record<string, unknown>; platform?: Record<string, unknown> };

/** عميل وهمي يكفي لمسارات القراءة وحجز التجربة. */
function fakeClient(rows: Rows, opts: { probeWon?: boolean; rpc?: () => unknown } = {}) {
  let debits = 0;
  const client = {
    from(table: string) {
      const row = table === 'tenant_whatsapp_gateways' ? rows.gateway : rows.platform;
      const chain: Record<string, unknown> = {};
      let updating = false;
      for (const m of ['select', 'eq', 'limit', 'is', 'not']) {
        chain[m] = () => chain;
      }
      chain.update = () => {
        updating = true;
        return chain;
      };
      chain.maybeSingle = () =>
        Promise.resolve({
          data: updating ? (opts.probeWon ? { id: 1 } : null) : row ?? null,
          error: null,
        });
      return chain;
    },
    rpc() {
      debits++;
      return Promise.resolve({ data: { ok: true }, error: null });
    },
  };
  return { client: client as unknown as SupabaseClient, debits: () => debits };
}

const longAgo = new Date(Date.now() - 2 * 60 * 60_000).toISOString();
const justNow = new Date().toISOString();
const debit = { tenantUserId: 't', idempotencyKey: 'k' };

Deno.test('no block lets the send through', async () => {
  const { client } = fakeClient({ gateway: { whatsapp_provider: 'cloud_api' } });
  assertEquals((await readSendBlock(client, 't')).blocked, false);
});

Deno.test('a store block stops only that store', async () => {
  const { client } = fakeClient({
    gateway: { send_block_reason: 'account_locked', send_block_since: justNow },
  });
  const state = await readSendBlock(client, 't');
  assertEquals(state.scope, 'tenant');
  assertEquals(state.reason, 'account_locked');
});

Deno.test('a platform block stops stores on the Naboo number', async () => {
  const { client } = fakeClient({
    gateway: { whatsapp_provider: 'dualhook' },
    platform: { send_block_reason: 'platform_issue', send_block_since: justNow },
  });
  assertEquals((await readSendBlock(client, 't')).scope, 'platform');
});

Deno.test('a platform block does not touch a store on its own number', async () => {
  const { client } = fakeClient({
    gateway: { whatsapp_provider: 'cloud_api' },
    platform: { send_block_reason: 'platform_issue', send_block_since: justNow },
  });
  assertEquals((await readSendBlock(client, 't')).blocked, false);
});

Deno.test('a block debits nothing', async () => {
  const { client, debits } = fakeClient({
    gateway: { send_block_reason: 'reconnect_needed', send_block_since: justNow },
  });
  const result = await debitWalletForSend(client, debit);
  assertEquals(result.ok, false);
  assertEquals(result.error, 'send_blocked:reconnect_needed');
  assertEquals(debits(), 0);
});

Deno.test('a fresh block allows no probe', async () => {
  const { client } = fakeClient(
    { gateway: { send_block_reason: 'x', send_block_since: justNow } },
    { probeWon: true },
  );
  assertEquals((await checkSendBlock(client, 't')).blocked, true);
});

Deno.test('an old block lets the one probe winner through', async () => {
  const { client } = fakeClient(
    { gateway: { send_block_reason: 'x', send_block_since: longAgo } },
    { probeWon: true },
  );
  assertEquals((await checkSendBlock(client, 't')).blocked, false);
});

Deno.test('an old block stops whoever loses the probe', async () => {
  const { client } = fakeClient(
    { gateway: { send_block_reason: 'x', send_block_since: longAgo } },
    { probeWon: false },
  );
  assertEquals((await checkSendBlock(client, 't')).blocked, true);
});

Deno.test('a read failure does not stop sending', async () => {
  const broken = {} as unknown as SupabaseClient;
  assertEquals((await readSendBlock(broken, 't')).blocked, false);
});

Deno.test('إيقاف القالب يخص المتجر، وعلى رقم نابو يشمل كل المتاجر', async () => {
  const seen: Array<[string, unknown]> = [];
  const chain = {
    update: () => chain,
    eq: (col: string, val: unknown) => {
      seen.push([col, val]);
      return chain;
    },
    then: (r: (v: unknown) => void) => r({}),
  };
  const db = { from: () => chain } as never;

  await applySendBlock(db, 't1', {
    scope: 'template',
    autoRetry: false,
    block: 'template',
    reasonCode: 'template_paused',
  }, { provider: 'cloud_api', templateKey: 'oil_change_followup' });
  assertEquals(seen.some(([c]) => c === 'tenant_user_id'), true);

  seen.length = 0;
  await applySendBlock(db, 't1', {
    scope: 'template',
    autoRetry: false,
    block: 'template',
    reasonCode: 'template_paused',
  }, { provider: 'dualhook', templateKey: 'oil_change_followup' });
  assertEquals(seen.some(([c]) => c === 'tenant_user_id'), false);
});
