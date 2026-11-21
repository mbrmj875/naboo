import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parseRatingReply } from './rating_parse.ts';
import { mapMetaStatus, parseMetaWebhook } from './meta_payload.ts';

Deno.test('رقم مجرد يُقرأ تقييماً بلا ملاحظة', () => {
  assertEquals(parseRatingReply('7'), { score: 7, note: null });
  assertEquals(parseRatingReply(' 10 '), { score: 10, note: null });
});

Deno.test('الأرقام العربية تُطبَّع', () => {
  assertEquals(parseRatingReply('٩'), { score: 9, note: null });
  assertEquals(parseRatingReply('۸'), { score: 8, note: null });
});

Deno.test('صيغة 7/10 تلتقط 7 وتحفظ النص', () => {
  const parsed = parseRatingReply('7/10');
  assertEquals(parsed.score, 7);
  assertEquals(parsed.note, '7/10');
});

Deno.test('رقم خارج المدى لا يُعد تقييماً', () => {
  assertEquals(parseRatingReply('0'), { score: null, note: '0' });
  assertEquals(parseRatingReply('15'), { score: null, note: '15' });
  assertEquals(parseRatingReply('2026'), { score: null, note: '2026' });
});

Deno.test('نص بلا رقم يُحفظ ملاحظة فقط', () => {
  assertEquals(parseRatingReply('خدمة ممتازة'), {
    score: null,
    note: 'خدمة ممتازة',
  });
});

Deno.test('رد فارغ يُهمل', () => {
  assertEquals(parseRatingReply('   '), { score: null, note: null });
});

Deno.test('رقم داخل جملة يُلتقط مع الملاحظة', () => {
  const parsed = parseRatingReply('اعطيكم 9 بس التنظيف ناقص');
  assertEquals(parsed.score, 9);
  assertEquals(parsed.note, 'اعطيكم 9 بس التنظيف ناقص');
});

Deno.test('تفكيك حمولة Meta للرسائل الواردة', () => {
  const payload = {
    object: 'whatsapp_business_account',
    entry: [{
      changes: [{
        field: 'messages',
        value: {
          metadata: { phone_number_id: '1206931799175422' },
          messages: [{
            id: 'wamid.IN1',
            from: '9647884289711',
            type: 'text',
            text: { body: '7' },
            context: { id: 'wamid.OUT1' },
          }],
        },
      }],
    }],
  };
  const parsed = parseMetaWebhook(payload);
  assertEquals(parsed.isMeta, true);
  assertEquals(parsed.messages.length, 1);
  assertEquals(parsed.messages[0].contextMessageId, 'wamid.OUT1');
  assertEquals(parsed.messages[0].body, '7');
  assertEquals(parsed.messages[0].phoneNumberId, '1206931799175422');
});

Deno.test('تفكيك تحديثات الحالة مع أخطاء Meta', () => {
  const parsed = parseMetaWebhook({
    object: 'whatsapp_business_account',
    entry: [{
      changes: [{
        value: {
          metadata: { phone_number_id: '123' },
          statuses: [{
            id: 'wamid.OUT1',
            status: 'failed',
            errors: [{
              code: 131026,
              title: 'Undeliverable',
              message: 'Message undeliverable',
            }],
          }],
        },
      }],
    }],
  });
  assertEquals(parsed.statuses.length, 1);
  assertEquals(mapMetaStatus(parsed.statuses[0].status), 'failed');
  assertEquals(parsed.statuses[0].error?.code, '131026');
  assertEquals(parsed.statuses[0].error?.title, 'Undeliverable');
  assertEquals(mapMetaStatus('read'), 'read');
  assertEquals(mapMetaStatus('delivered'), 'delivered');
  assertEquals(mapMetaStatus('sent'), 'sent');
  assertEquals(mapMetaStatus('failed'), 'failed');
});

Deno.test('أخطاء الحالة الغائبة أو التالفة لا تكسر التفكيك', () => {
  const noErrors = parseMetaWebhook({
    object: 'whatsapp_business_account',
    entry: [{
      changes: [{
        value: {
          metadata: { phone_number_id: '123' },
          statuses: [{ id: 'wamid.1', status: 'delivered' }],
        },
      }],
    }],
  });
  assertEquals(noErrors.statuses[0].error, null);

  const badErrors = parseMetaWebhook({
    object: 'whatsapp_business_account',
    entry: [{
      changes: [{
        value: {
          metadata: { phone_number_id: '123' },
          statuses: [{ id: 'wamid.2', status: 'failed', errors: 'x' }],
        },
      }],
    }],
  });
  assertEquals(badErrors.statuses[0].error, null);

  const emptyObj = parseMetaWebhook({
    object: 'whatsapp_business_account',
    entry: [{
      changes: [{
        value: {
          metadata: { phone_number_id: '123' },
          statuses: [{ id: 'wamid.3', status: 'failed', errors: [{}] }],
        },
      }],
    }],
  });
  assertEquals(emptyObj.statuses[0].error, null);
});

Deno.test('حمولة YCloud لا تُعد Meta', () => {
  const parsed = parseMetaWebhook({ type: 'whatsapp.message.updated', id: 'x' });
  assertEquals(parsed.isMeta, false);
});
