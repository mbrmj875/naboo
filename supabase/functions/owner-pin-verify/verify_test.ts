import { assert, assertEquals } from 'jsr:@std/assert@1';
import { type PinStore, verifyOwnerPin, verifyPinHash } from './verify.ts';

// نفس المتجه في test/services/pin_hash_vector_test.dart (حساب التطبيق).
const SALT = 'c2FsdC12ZWN0b3ItMDE=';
const HASH = 'pbkdf2$150000$bz_eWSywbVuYyU2WaqtfzBYJL0YM457hjjgZilXMPQ8=';

/** نسخة في الذاكرة من owner_pin_attempt_begin/success بنفس القواعد. */
function memoryStore(secret: { phone: string; pin_hash: string; pin_salt: string } | null) {
  const s = { failed: 0, lockouts: 0, lockedUntil: null as number | null, now: 0, successes: 0 };
  const store: PinStore = {
    secret: () => Promise.resolve(secret),
    begin() {
      if (s.lockedUntil !== null && s.lockedUntil > s.now) {
        return Promise.resolve({ allowed: false, locked_until: String(s.lockedUntil), remaining: 0 });
      }
      if (s.lockedUntil !== null) {
        s.failed = 0;
        s.lockedUntil = null;
      }
      s.failed += 1;
      if (s.failed >= 5) {
        s.lockedUntil = s.now + Math.min(15 * 2 ** s.lockouts, 720);
        s.lockouts += 1;
      }
      return Promise.resolve({
        allowed: true,
        locked_until: s.lockedUntil === null ? null : String(s.lockedUntil),
        remaining: Math.max(5 - s.failed, 0),
      });
    },
    success() {
      s.failed = 0;
      s.lockouts = 0;
      s.lockedUntil = null;
      s.successes += 1;
      return Promise.resolve();
    },
  };
  return { store, s };
}

Deno.test('the app hash format verifies', async () => {
  assert(await verifyPinHash('1234', SALT, HASH));
  assert(await verifyPinHash(' 1234 ', SALT, HASH));
  assert(!(await verifyPinHash('1235', SALT, HASH)));
  assert(!(await verifyPinHash('1234', 'other', HASH)));
  assert(!(await verifyPinHash('1234', SALT, 'pbkdf2$abc$x')));
  assert(!(await verifyPinHash('1234', SALT, 'pbkdf2$999999999$x')));
});

Deno.test('the old SHA-256 format verifies', async () => {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('salt1:4321'));
  const hex = [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, '0')).join('');
  assert(await verifyPinHash('4321', 'salt1', hex));
  assert(!(await verifyPinHash('4322', 'salt1', hex)));
});

Deno.test('correct PIN returns the phone without the hash', async () => {
  const { store, s } = memoryStore({ phone: '07701234567', pin_hash: HASH, pin_salt: SALT });
  const r = await verifyOwnerPin(store, 'u1', '1234');
  assertEquals(r.status, 200);
  assertEquals(r.body, { ok: true, phone: '07701234567' });
  assert(!JSON.stringify(r.body).includes('pbkdf2'));
  assertEquals(s.successes, 1);
});

Deno.test('five wrong tries lock, a correct fifth unlocks', async () => {
  const { store, s } = memoryStore({ phone: 'p', pin_hash: HASH, pin_salt: SALT });
  for (let i = 4; i >= 1; i--) {
    const r = await verifyOwnerPin(store, 'u1', '0000');
    assertEquals(r.body, { ok: false, reason: 'wrong_pin', remaining: i, locked_until: null });
  }
  const fifth = await verifyOwnerPin(store, 'u1', '1234');
  assertEquals(fifth.body.ok, true);
  assertEquals(s.lockedUntil, null);
});

Deno.test('lock blocks even the correct PIN, then escalates', async () => {
  const { store, s } = memoryStore({ phone: 'p', pin_hash: HASH, pin_salt: SALT });
  for (let i = 0; i < 5; i++) await verifyOwnerPin(store, 'u1', '0000');
  const locked = await verifyOwnerPin(store, 'u1', '1234');
  assertEquals(locked.status, 429);
  assertEquals(s.lockedUntil, 15);

  s.now = 16; // انتهى القفل الأول.
  for (let i = 0; i < 5; i++) await verifyOwnerPin(store, 'u1', '0000');
  assertEquals(s.lockedUntil, 16 + 30);
});

Deno.test('bad input and missing secret do not spend attempts', async () => {
  const { store, s } = memoryStore({ phone: 'p', pin_hash: HASH, pin_salt: SALT });
  for (const bad of [undefined, 1234, '', '12', 'abcd', '1'.repeat(9)]) {
    assertEquals((await verifyOwnerPin(store, 'u1', bad)).status, 400);
  }
  assertEquals(s.failed, 0);
  const none = memoryStore(null);
  assertEquals((await verifyOwnerPin(none.store, 'u1', '1234')).body, { ok: false, reason: 'no_secret' });
  assertEquals(none.s.failed, 0);
});
