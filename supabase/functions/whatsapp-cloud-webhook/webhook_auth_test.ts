import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { parseMetaWebhook } from './meta_payload.ts';
import {
  authenticateWebhook,
  canBindFromWebhook,
  isAuthorizedBackfill,
  rejectionLogFields,
  signatureRequired,
} from './webhook_auth.ts';

const metaSecret = 'test_meta_secret';
const ycloudSecret = 'test_ycloud_secret';
const secrets = { ycloudSecret, metaAppSecret: metaSecret };
const body = '{"object":"whatsapp_business_account","entry":[]}';

async function hmacHex(secret: string, payload: string): Promise<string> {
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
    new TextEncoder().encode(payload),
  );
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

Deno.test('a valid Meta signature is accepted', async () => {
  const sig = `sha256=${await hmacHex(metaSecret, body)}`;
  const auth = await authenticateWebhook(
    body,
    { ycloudSignature: null, metaSignature: sig },
    secrets,
  );
  assertEquals(auth, { source: 'meta', reason: 'ok' });
});

Deno.test('a wrong Meta signature is rejected', async () => {
  const sig = `sha256=${await hmacHex('other_secret', body)}`;
  const auth = await authenticateWebhook(
    body,
    { ycloudSignature: null, metaSignature: sig },
    secrets,
  );
  assertEquals(auth, { source: 'none', reason: 'invalid_meta_signature' });
});

Deno.test('a Meta signature over a changed body is rejected', async () => {
  const sig = `sha256=${await hmacHex(metaSecret, body)}`;
  const auth = await authenticateWebhook(
    `${body} `,
    { ycloudSignature: null, metaSignature: sig },
    secrets,
  );
  assertEquals(auth.source, 'none');
});

Deno.test('a request with no signature has no source', async () => {
  const auth = await authenticateWebhook(
    '{"entry":[{"id":"x"}]}',
    { ycloudSignature: null, metaSignature: '' },
    secrets,
  );
  assertEquals(auth, { source: 'none', reason: 'missing_signature' });
});

Deno.test('a Meta signature is rejected when the secret is not set', async () => {
  const sig = `sha256=${await hmacHex(metaSecret, body)}`;
  const auth = await authenticateWebhook(
    body,
    { ycloudSignature: null, metaSignature: sig },
    { ycloudSecret, metaAppSecret: '' },
  );
  assertEquals(auth.source, 'none');
});

Deno.test('a valid YCloud signature is accepted', async () => {
  const t = '1700000000';
  const s = await hmacHex(ycloudSecret, `${t}.${body}`);
  const auth = await authenticateWebhook(
    body,
    { ycloudSignature: `t=${t},s=${s}`, metaSignature: '' },
    secrets,
  );
  assertEquals(auth, { source: 'ycloud', reason: 'ok' });
});

Deno.test('a wrong YCloud signature cannot fall through to Meta', async () => {
  const metaSig = `sha256=${await hmacHex(metaSecret, body)}`;
  const auth = await authenticateWebhook(
    body,
    { ycloudSignature: 't=1,s=00', metaSignature: metaSig },
    secrets,
  );
  assertEquals(auth, { source: 'none', reason: 'invalid_signature' });
});

Deno.test('entry without object is no longer read as Meta', () => {
  const entry = [{
    id: 'waba',
    changes: [{
      field: 'messages',
      value: { statuses: [{ id: 'wamid.1', status: 'delivered' }] },
    }],
  }];
  assertEquals(parseMetaWebhook({ entry }).isMeta, false);
  assertEquals(
    parseMetaWebhook({ object: 'whatsapp_business_account', entry }).isMeta,
    true,
  );
});

Deno.test('a store id in the body can bind only for verified YCloud', () => {
  assertEquals(canBindFromWebhook('ycloud'), true);
  assertEquals(canBindFromWebhook('meta'), false);
  assertEquals(canBindFromWebhook('none'), false);
});

Deno.test('signature is required unless the switch says false', () => {
  assertEquals(signatureRequired(undefined), true);
  assertEquals(signatureRequired(''), true);
  assertEquals(signatureRequired('true'), true);
  assertEquals(signatureRequired('anything'), true);
  assertEquals(signatureRequired(' FALSE '), false);
});

Deno.test('backfill needs the token and the exact operation', () => {
  const ops = '{"ops":"backfill_unanswered"}';
  assertEquals(isAuthorizedBackfill(ops, 'tok', 'tok'), true);
  assertEquals(isAuthorizedBackfill(ops, 'bad', 'tok'), false);
  assertEquals(isAuthorizedBackfill(ops, null, 'tok'), false);
  assertEquals(isAuthorizedBackfill(ops, '', ''), false);
  assertEquals(isAuthorizedBackfill(ops, 'tok', undefined), false);
  assertEquals(isAuthorizedBackfill('{"ops":"other"}', 'tok', 'tok'), false);
  assertEquals(isAuthorizedBackfill('not json', 'tok', 'tok'), false);
});

Deno.test('the rejection line carries no request content', () => {
  const secretText = 'customer phone 0770';
  const fields = rejectionLogFields('missing_signature', secretText, 'ua');
  assertEquals(JSON.stringify(fields).includes(secretText), false);
  assertEquals(fields.body_bytes, new TextEncoder().encode(secretText).length);
});
