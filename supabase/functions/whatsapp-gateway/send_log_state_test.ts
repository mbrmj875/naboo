import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { classifyExistingSendLog } from './send_log_state.ts';

Deno.test('rejected لا يُحبس — يُعاد إرساله كبطاقة جديدة', () => {
  assertEquals(classifyExistingSendLog('rejected', null), 'retry');
});

Deno.test('failed يبقى قابلاً للإعادة', () => {
  assertEquals(classifyExistingSendLog('failed', null), 'retry');
});

Deno.test('sent بلا رقم ميتا يُعاد — التسليم غير مؤكد', () => {
  assertEquals(classifyExistingSendLog('sent', null), 'retry');
  assertEquals(classifyExistingSendLog('sent', ''), 'retry');
});

Deno.test('delivered/read/sent مع wamid لا يُرسل مرتين', () => {
  assertEquals(
    classifyExistingSendLog('delivered', 'wamid.ABC'),
    'done',
  );
  assertEquals(classifyExistingSendLog('read', 'wamid.ABC'), 'done');
  assertEquals(classifyExistingSendLog('sent', 'wamid.ABC'), 'done');
});

Deno.test('queued/accepted/sending تبقى قيد المعالجة', () => {
  assertEquals(classifyExistingSendLog('queued', null), 'in_flight');
  assertEquals(classifyExistingSendLog('accepted', null), 'in_flight');
  assertEquals(classifyExistingSendLog('sending', 'wamid.ABC'), 'in_flight');
});
