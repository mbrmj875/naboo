/**
 * اختبارات خفيفة لتوقيع Meta hub — شغّل:
 * deno test --allow-env supabase/functions/whatsapp-cloud-webhook/meta_hub_signature_test.ts
 */

import {
  normalizeMetaSignatureHeader,
  verifyMetaHubSignature,
} from './meta_hub_signature.ts';

Deno.test('normalizeMetaSignatureHeader strips sha256=', () => {
  const h = normalizeMetaSignatureHeader('sha256=AbCdEf');
  if (h !== 'abcdef') throw new Error(`got ${h}`);
});

Deno.test('verifyMetaHubSignature accepts valid hmac', async () => {
  const secret = 'test_meta_app_secret';
  const body = '{"object":"whatsapp_business_account"}';
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const sig = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(body),
  );
  const hex = [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  const ok = await verifyMetaHubSignature(body, `sha256=${hex}`, secret);
  if (!ok) throw new Error('expected valid signature');
});

Deno.test('verifyMetaHubSignature rejects tampered body', async () => {
  const secret = 'test_meta_app_secret';
  const ok = await verifyMetaHubSignature(
    '{"object":"whatsapp_business_account"}',
    'sha256=0000000000000000000000000000000000000000000000000000000000000000',
    secret,
  );
  if (ok) throw new Error('expected rejection');
});
