export type ExistingSendLogState = 'done' | 'in_flight' | 'retry';

/**
 * سجل مرفوض/فاشل أو «أُرسل» بلا رقم ميتا لا يمنع بطاقة جديدة بنفس المفتاح.
 * أرقام الطلب المحلية تُعاد من 1 بعد مسح الجهاز، وإسقاط رسالة قديمة
 * كان يُعامل كـ in_flight فيحبس الإرسال التلقائي لكل المستأجرين.
 */
export function classifyExistingSendLog(
  status: string | null | undefined,
  providerMessageId?: string | null,
): ExistingSendLogState {
  const st = String(status ?? '').toLowerCase();
  const wamid = String(providerMessageId ?? '').trim();
  if (st === 'sent' || st === 'delivered' || st === 'read') {
    return wamid ? 'done' : 'retry';
  }
  if (st === 'failed' || st === 'rejected') return 'retry';
  if (st === 'sending' || st === 'accepted' || st === 'queued') {
    return 'in_flight';
  }
  return 'in_flight';
}
