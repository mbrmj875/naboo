import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  classifyFailure,
  graphErrorCodes,
  nextRetryDelayMs,
} from './failure_policy.ts';

const store = (errorCode: string | number) =>
  classifyFailure({ errorCode, isSharedSender: false });
const naboo = (errorCode: string | number) =>
  classifyFailure({ errorCode, isSharedSender: true });

Deno.test('131026 touches the customer only', () => {
  assertEquals(store(131026), {
    scope: 'recipient',
    autoRetry: false,
    block: 'none',
    reasonCode: 'recipient_unreachable',
  });
});

Deno.test('131031 stops the store queue', () => {
  assertEquals(store(131031).block, 'tenant');
  assertEquals(store(131031).reasonCode, 'account_locked');
});

Deno.test('131042 on a store number stops that store', () => {
  assertEquals(store(131042).block, 'tenant');
  assertEquals(store(131042).reasonCode, 'payment_issue_store');
});

Deno.test('131042 on the Naboo number stops the platform', () => {
  assertEquals(naboo(131042).block, 'platform');
  assertEquals(naboo(131042).reasonCode, 'platform_issue');
});

Deno.test('131047 touches the message only', () => {
  assertEquals(store(131047).block, 'none');
  assertEquals(store(131047).reasonCode, 'window_closed');
});

Deno.test('132015 and 132016 touch the template only', () => {
  assertEquals(store(132015).block, 'template');
  assertEquals(store(132016).reasonCode, 'template_paused');
});

Deno.test('token errors ask the store to reconnect', () => {
  for (const code of [190, 10, 200]) {
    assertEquals(store(code).block, 'tenant');
    assertEquals(store(code).reasonCode, 'reconnect_needed');
  }
  assertEquals(
    classifyFailure({ detail: 'cloud_token_missing', isSharedSender: false })
      .reasonCode,
    'reconnect_needed',
  );
});

Deno.test('token errors on the Naboo number stop the platform', () => {
  assertEquals(naboo(190).block, 'platform');
  assertEquals(naboo(190).reasonCode, 'platform_issue');
});

Deno.test('130429, network and 5xx are temporary and never stop the queue', () => {
  for (
    const d of [
      classifyFailure({ errorCode: 130429, isSharedSender: true }),
      classifyFailure({ detail: 'TypeError: fetch failed', isSharedSender: false }),
      classifyFailure({ httpStatus: 503, isSharedSender: false }),
    ]
  ) {
    assertEquals(d.autoRetry, true);
    assertEquals(d.block, 'none');
    assertEquals(d.reasonCode, 'temporary');
  }
});

Deno.test('an unknown code does nothing automatic', () => {
  assertEquals(store(999999), {
    scope: 'unknown',
    autoRetry: false,
    block: 'none',
    reasonCode: 'unknown',
  });
});

Deno.test('retries wait 5 minutes, 30 minutes, 2 hours, then stop', () => {
  assertEquals(nextRetryDelayMs(0), 300_000);
  assertEquals(nextRetryDelayMs(1), 1_800_000);
  assertEquals(nextRetryDelayMs(2), 7_200_000);
  assertEquals(nextRetryDelayMs(3), null);
});

Deno.test('Graph error codes stay numeric', () => {
  assertEquals(graphErrorCodes({ code: 131042, error_subcode: 2494010 }), {
    errorCode: 131042,
    errorSubcode: 2494010,
  });
  assertEquals(graphErrorCodes(undefined), {});
  assertEquals(graphErrorCodes({ message: 'x' }), {});
});
