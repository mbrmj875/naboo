/**
 * قيد الإرسال: دائماً @c.us — لا @lid من check-exists.
 * تشغيل: deno test supabase/functions/whatsapp-gateway/waha_chatid_test.ts
 */
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  assertPhoneChatId,
  normalizeIraqWhatsappDigits,
  toCUsChatId,
} from './waha.ts';

Deno.test('toCUsChatId always ends with @c.us from digits', () => {
  assertEquals(toCUsChatId('9647808271811'), '9647808271811@c.us');
  assertEquals(toCUsChatId('07808271811'), '9647808271811@c.us');
  assertEquals(toCUsChatId('7808271811'), '9647808271811@c.us');
});

Deno.test('toCUsChatId never returns @lid (strips any jid suffix)', () => {
  // الإرسال الحقيقي يستخدم رقم الزبون من الطلب، لا أرقام @lid من check-exists.
  assertEquals(toCUsChatId('9647808271811@lid').endsWith('@lid'), false);
  assertEquals(toCUsChatId('9647808271811@lid'), '9647808271811@c.us');
  assertEquals(
    toCUsChatId('9647808271811@s.whatsapp.net'),
    '9647808271811@c.us',
  );
  assertEquals(toCUsChatId('9647808271811@c.us'), '9647808271811@c.us');
  assertEquals(toCUsChatId('9140462211222@lid').includes('@lid'), false);
});

Deno.test('assertPhoneChatId rejects @lid', () => {
  assertEquals(assertPhoneChatId('9647808271811@c.us'), true);
  assertEquals(assertPhoneChatId('9647808271811@lid'), false);
  assertEquals(assertPhoneChatId('9140462211222@lid'), false);
  assertEquals(assertPhoneChatId('9647808271811@s.whatsapp.net'), false);
  assertEquals(assertPhoneChatId(''), false);
});

Deno.test('normalize never invents lid suffix', () => {
  const d = normalizeIraqWhatsappDigits('9647808271811@lid');
  assertEquals(d, '9647808271811');
  assertEquals(d.includes('lid'), false);
});
