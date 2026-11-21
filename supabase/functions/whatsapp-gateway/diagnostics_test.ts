/**
 * اختبارات خفيفة لمنطق التشخيص (Deno).
 * تشغيل: deno test supabase/functions/whatsapp-gateway/diagnostics_test.ts
 */
import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  jidTypeFromRemote,
  suggestedActionFor,
} from './diagnostics.ts';

Deno.test('jidTypeFromRemote detects lid vs phone', () => {
  assertEquals(jidTypeFromRemote('180569283530844@lid'), 'lid');
  assertEquals(jidTypeFromRemote('9647884289711@s.whatsapp.net'), 'phone');
  assertEquals(jidTypeFromRemote(''), 'unknown');
});

Deno.test('suggestedActionFor same_as_shop', () => {
  const s = suggestedActionFor('same_as_shop_phone');
  assertStringIncludes(s, 'زبون');
});

Deno.test('suggestedActionFor none_timeout / lid', () => {
  const s = suggestedActionFor('none_timeout_likely_lid');
  assertStringIncludes(s, 'lid');
});

Deno.test('suggestedActionFor removed', () => {
  const s = suggestedActionFor('instance_removed');
  assertStringIncludes(s, 'QR');
});
