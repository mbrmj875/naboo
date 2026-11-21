import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { adminClient, requireAdmin } from './admin_client.ts';

const source = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
const writePattern =
  /(\w+)\s*\.from\('tenant_whatsapp_gateways'\)\s*\.(update|upsert|insert|delete)\(/g;

Deno.test('every row write in the handler uses the admin client', () => {
  const helperStart = source.indexOf('async function markHardReset(');
  const writes = [...source.matchAll(writePattern)];
  assertEquals(writes.length > 20, true);
  for (const write of writes) {
    const insideHelper = write.index >= helperStart;
    assertEquals(write[1], insideHelper ? 'supabase' : 'gatewayWriter');
  }
});

Deno.test('the one helper that writes receives the admin client', () => {
  const calls = [...source.matchAll(/markHardReset\(\s*(\w+),/g)];
  assertEquals(calls.length, 3);
  for (const call of calls) assertEquals(call[1], 'gatewayWriter');
});

Deno.test('every row write is scoped to the signed-in user', () => {
  for (const write of source.matchAll(writePattern)) {
    const after = source.slice(write.index, write.index + 900);
    const scoped = /user_id: user\.id/.test(after) ||
      /\.eq\('user_id', (user\.id|userId)\)/.test(after);
    const before = source.slice(Math.max(0, write.index - 1200), write.index);
    const namedRow = /(upsertRow|patch)\b/.test(after.slice(0, 120)) &&
      /user_id: user\.id/.test(before);
    assertEquals(scoped || namedRow, true);
  }
});

Deno.test('a missing admin key is an explicit error', () => {
  if (adminClient()) return;
  assertThrows(() => requireAdmin(), Error, 'admin_client_unavailable');
});
