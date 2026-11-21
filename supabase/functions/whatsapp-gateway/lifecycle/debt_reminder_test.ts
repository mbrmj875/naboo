import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  debtReminderIdempotencyKey,
  debtReminderRetryLater,
  normalizeDebtTemplateStatus,
} from './debt_reminder.ts';
import {
  debtReminderTemplate,
  oilChangeDefaultTemplates,
  resolveTemplateSpecs,
} from './default_template_registry.ts';
import { TemplateKey } from '../notifications/notification_request.ts';

Deno.test('قالب الدين: أربعة متغيرات مرقمة بالترتيب ولا يبدأ أو ينتهي بمتغير', () => {
  const t = debtReminderTemplate;
  assertEquals(t.paramKeys.length, 4);
  assertEquals(t.exampleBodyParams.length, 4);
  for (let i = 1; i <= 4; i++) {
    assertEquals(t.bodyText.includes(`{{${i}}}`), true, `{{${i}}}`);
  }
  assertEquals(/^\{\{/.test(t.bodyText.trim()), false);
  assertEquals(/\}\}$/.test(t.bodyText.trim()), false);
  assertEquals(t.category, 'utility');
});

Deno.test('قالب الدين لا يدخل قوالب الربط ولا يؤخر جاهزية البطاقة', () => {
  assertEquals(
    oilChangeDefaultTemplates.some((t) => t.key === TemplateKey.debtReminder),
    false,
  );
  assertEquals(resolveTemplateSpecs(TemplateKey.debtReminder), [debtReminderTemplate]);
});

Deno.test('المفتاح مقيَّد بالمحل، والإعادة فقط للأسباب المؤقتة', () => {
  assertEquals(
    debtReminderIdempotencyKey('t1', ' c9|2026-11-22 '),
    'debt_reminder:t1:c9|2026-11-22',
  );
  assertEquals(debtReminderRetryLater('sent'), false);
  assertEquals(debtReminderRetryLater('opted_out'), false);
  assertEquals(debtReminderRetryLater('already_sent'), false);
  assertEquals(debtReminderRetryLater('template_not_approved'), true);
  assertEquals(debtReminderRetryLater('insufficient_balance'), true);
  assertEquals(normalizeDebtTemplateStatus('paused'), 'rejected');
  assertEquals(normalizeDebtTemplateStatus(null), 'none');
});
