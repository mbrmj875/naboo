/**
 * تصنيف نية رسالة الزبون قبل أي رد — نية واحدة فقط حسب الأولوية.
 */

import {
  looksLikeEmployeeQuestion,
  looksLikeGreeting,
  looksLikeLastServiceQuestion,
  looksLikePriceQuestion,
} from './card_faq.ts';
import { looksLikeFeedback } from './conversation.ts';
import { looksLikeWarrantyQuestion } from './ai_reply.ts';
import {
  detectCatalogListRequest,
  looksLikeInventoryQuestion,
} from './inventory_lookup.ts';
import {
  looksLikeContactQuestion,
  looksLikeSensitiveTopic,
} from './sensitive_topics.ts';

export type InboundIntent =
  | 'rating'
  | 'pdf_file'
  | 'thanks'
  | 'inventory'
  | 'last_service'
  | 'warranty'
  | 'contact'
  | 'sensitive'
  | 'employee'
  | 'visit_price'
  | 'greeting'
  | 'other';

export const THANKS_CLOSE_REPLY =
  'العفو، خدمة حاضرة. يومك سعيد 🙏';

const THANKS_ONLY_RE =
  /^(شكراً?|تسلم(?:ون)?|مشكور(?:ين)?|يسلمو(?:ن|و)?|عفواً?|الله يبارك|الله يسلمك|هواي\s*شكراً?|شكراً?\s*هواي)([\s!.،,-]*|[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}])*$/u;

function foldAr(raw: string): string {
  return String(raw ?? '')
    .replace(/[أإآ]/g, 'ا')
    .replace(/ة/g, 'ه')
    .replace(/ى/g, 'ي')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

/** طلب ملف البطاقة بأي صياغة: pdf، بدف، أرسل الملف، نسخة الغيار… */
export function looksLikePdfFileRequest(message: string): boolean {
  const t = foldAr(message);
  if (!t || t.length > 180) return false;
  if (/ما\s*(اريد|ابي|ابغى|احتاج)\s*(ال)?(ملف|pdf|بدف)/.test(t)) return false;
  if (/\bpdf\b/.test(t) || t.includes('pdf')) return true;
  if (/بدف|ب\s*د\s*ف|بدي\s*اف|بي\s*دي\s*اف/.test(t)) return true;
  if (/(ملف|نسخه).{0,30}(غيار|بطاق|زيار|خدم)/.test(t)) return true;
  if (
    /(ارسل|ابعث|ابعت|اريد|ابي|ابغى|ممكن|لو سمحت|عطني|انطيني|ريد|انزل).{0,40}(ملف|نسخه)/
      .test(t)
  ) {
    return true;
  }
  if (/(ملف|نسخه).{0,24}(ارسل|ابعث|ابعت|ممكن|لو سمحت)/.test(t)) return true;
  return false;
}

export function looksLikeThanksClose(message: string): boolean {
  const t = String(message ?? '').replace(/\s+/g, ' ').trim();
  if (!t || t.length > 56) return false;
  if (/[؟?]/.test(t)) return false;
  if (looksLikeInventoryQuestion(t) || detectCatalogListRequest(t)) {
    return false;
  }
  return THANKS_ONLY_RE.test(t);
}

/** تقييم رقمي صريح أو ملاحظة خدمة — ليس رقم لزوجة داخل اسم زيت. */
export function looksLikeExplicitRating(
  message: string,
  score: number | null,
): boolean {
  if (score == null) return false;
  const compact = String(message ?? '').replace(/\s+/g, ' ').trim();
  if (/^(10|[1-9])(\s*\/\s*10)?[!.,\s]*$/.test(compact)) return true;
  if (/تقييم|نجوم|من\s*10/.test(compact)) return true;
  if (/\d+\s*w\s*\d+/i.test(compact)) return false;
  if (looksLikeInventoryQuestion(compact) || detectCatalogListRequest(compact)) {
    return false;
  }
  if (/[؟?]/.test(compact)) return false;
  return looksLikeFeedback(compact);
}

export function classifyInboundIntent(
  message: string,
  score: number | null = null,
): InboundIntent {
  const t = String(message ?? '').trim();
  if (looksLikeExplicitRating(t, score)) return 'rating';
  if (looksLikePdfFileRequest(t)) return 'pdf_file';
  if (looksLikeThanksClose(t)) return 'thanks';
  // «اريد عنوان» فيها «اريد» فتُشبه طلب منتج. العنوان يسبق المخزون.
  if (looksLikeContactQuestion(t)) return 'contact';
  if (detectCatalogListRequest(t)) return 'inventory';
  if (looksLikePriceQuestion(t)) return 'visit_price';
  if (looksLikeInventoryQuestion(t)) return 'inventory';
  if (looksLikeLastServiceQuestion(t)) return 'last_service';
  if (looksLikeWarrantyQuestion(t)) return 'warranty';
  if (looksLikeSensitiveTopic(t)) return 'sensitive';
  if (looksLikeEmployeeQuestion(t)) return 'employee';
  if (looksLikeGreeting(t)) return 'greeting';
  return 'other';
}
