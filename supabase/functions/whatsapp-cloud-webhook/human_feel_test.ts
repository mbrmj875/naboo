import {
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { humanTypingDelayMs } from '../whatsapp-gateway/cloud_api.ts';

Deno.test('تأخير الكتابة بشري بين 0.7 و 2.8 ثانية', () => {
  assertEquals(humanTypingDelayMs('هلا', { fast: true }), 700);
  const mid = humanTypingDelayMs('أ'.repeat(40));
  assertEquals(mid >= 900 && mid <= 2800, true);
  assertEquals(humanTypingDelayMs('أ'.repeat(500)), 2800);
});
