import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { checkRecipientConsent, phoneKey } from './recipient_consent.ts';
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

function fakeDb(result: { data?: unknown; error?: unknown }): SupabaseClient {
  const chain = {
    select: () => chain,
    eq: () => chain,
    maybeSingle: () => Promise.resolve(result),
  };
  return { from: () => chain } as unknown as SupabaseClient;
}

Deno.test('الرقم المحلي والدولي مفتاح واحد', () => {
  assertEquals(phoneKey('07701234567'), phoneKey('+964 770 123 4567'));
  assertEquals(phoneKey('9647701234567'), '7701234567');
});

Deno.test('غياب صف الموافقة لا يمنع التذكير', async () => {
  assertEquals(await checkRecipientConsent(fakeDb({ data: null }), 't', '0770'), 'allowed');
});

Deno.test('الموافقة السابقة لا تمنع التذكير', async () => {
  assertEquals(
    await checkRecipientConsent(fakeDb({ data: { status: 'consented' } }), 't', '0770'),
    'allowed',
  );
});

Deno.test('طلب الإيقاف يمنع التذكير', async () => {
  assertEquals(
    await checkRecipientConsent(fakeDb({ data: { status: 'opted_out' } }), 't', '0770'),
    'opted_out',
  );
});

Deno.test('غياب الجدول قبل الهجرة لا يوقف التذكيرات', async () => {
  assertEquals(
    await checkRecipientConsent(fakeDb({ error: { code: '42P01', message: 'x' } }), 't', '0770'),
    'allowed',
  );
});

Deno.test('خطأ القراءة يؤجل ولا يرسل', async () => {
  assertEquals(
    await checkRecipientConsent(fakeDb({ error: { code: '500', message: 'x' } }), 't', '0770'),
    'unknown',
  );
});
