/** طلب الزبون إيقاف التذكيرات. مطابقة كاملة فقط، حتى لا تُفهم جملة عادية إيقافًا. */

const OPT_OUT_WORDS = new Set([
  'ايقاف',
  'توقف',
  'الغاء',
  'الغاء الاشتراك',
  'ايقاف الرسائل',
  'ايقاف التذكير',
  'ايقاف التذكيرات',
  'لا تراسلني',
  'stop',
  'unsubscribe',
]);

const OPT_IN_WORDS = new Set(['تفعيل', 'تفعيل التذكير', 'تفعيل التذكيرات', 'start']);

export const OPT_OUT_REPLY =
  'تم إيقاف رسائل التذكير من هذا المتجر. لإعادتها أرسل: تفعيل';

export const OPT_IN_REPLY =
  'تمت إعادة رسائل التذكير من هذا المتجر، وتبدأ مع زيارتك القادمة.';

function normalize(text: string | null | undefined): string {
  return String(text ?? '')
    .toLowerCase()
    .replace(/[أإآ]/g, 'ا')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function isOptOutRequest(text: string | null | undefined): boolean {
  return OPT_OUT_WORDS.has(normalize(text));
}

export function isOptInRequest(text: string | null | undefined): boolean {
  return OPT_IN_WORDS.has(normalize(text));
}
