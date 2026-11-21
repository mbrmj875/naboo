/**
 * أجوبة فورية من بطاقة الغيار بلا انتظار DeepSeek أو لقطة الحساب.
 */

import {
  detectCatalogListRequest,
  hasNamedInventoryQuery,
  looksLikeInventoryQuestion,
} from './inventory_lookup.ts';

export function looksLikeEmployeeQuestion(message: string): boolean {
  const t = String(message ?? '').trim();
  if (!t) return false;
  return (
    /(من\s*هو|ماهو|ما\s*هو|منو|مين).{0,16}(اسم\s*)?(ال)?(فني|موظف)/i.test(t) ||
    /اسم\s*(ال)?(فني|موظف)/i.test(t) ||
    /(^|\s)(الفني|الموظف)(\s|$)/i.test(t)
  );
}

export function looksLikePriceQuestion(message: string): boolean {
  const t = String(message ?? '').trim();
  if (!t) return false;
  // سؤال سعر منتج/زيت يُجاب من المخزون لا من إجمالي البطاقة.
  if (detectCatalogListRequest(t)) return false;
  if (looksLikeInventoryQuestion(t) && hasNamedInventoryQuery(t)) {
    return false;
  }
  return /(سعر|الحساب|الإجمالي|الاجمالي|المبلغ|شكد\s*صار|شگد\s*صار|كم\s*صار|كلّف|كلف)/i
    .test(t);
}

export function looksLikeGreeting(message: string): boolean {
  const t = String(message ?? '').trim();
  if (!t || t.length > 40) return false;
  return /^(مرحبا|مرحباً|هلا|هلو|السلام\s*عليكم|سلام|hi|hello|مرحبا\s*بكم)[\s!.]*$/i
    .test(t);
}

const PAST_VISIT_RE =
  /(آخر\s*مرة|اخر\s*مرة|متى\s*(بدلت|غيّرت|غيرت)|آخر\s*غيار|اخر\s*غيار|اللي\s*بدلت|بدلته|غيّرته|غيرته|هالبطاقة|هذه\s*البطاقة|هالزيارة|هذه\s*الزيارة|نوع\s*الزيت\s*(اللي|الذي)|شنو\s*الزيت\s*(اللي|الذي|آخر|اخر)|القراءة|العداد|\bodo\b)/i;

const SHOP_STOCK_RE = /(عندكم|عدكم|لديكم|متوفر)/i;

/**
 * آخر غيار لهذه البطاقة فقط عند إشارة للزيارة السابقة.
 * «شنو الزيت عندكم» مخزون وليست آخر زيارة.
 */
export function looksLikeLastServiceQuestion(message: string): boolean {
  const t = String(message ?? '').trim();
  if (!t) return false;
  if (detectCatalogListRequest(t)) return false;
  if (looksLikeInventoryQuestion(t) && SHOP_STOCK_RE.test(t)) return false;
  return PAST_VISIT_RE.test(t);
}

export function buildGreetingReply(
  employeeName: string | null,
  customerName?: string | null,
): string {
  const who = String(customerName ?? '').trim();
  const name = who && who !== '-' && who !== '—' ? `${who}، ` : '';
  const tech = String(employeeName ?? '').trim();
  if (tech) {
    return `${name}هلا بيك، أني بالخدمة. الفني اللي خدمك ${tech} — شلون أگدر أساعدك؟`;
  }
  return `${name}هلا بيك، أني بالخدمة — شلون أگدر أساعدك؟`;
}

export function buildEmployeeReply(args: {
  employeeName: string | null;
  card?: Record<string, string> | null;
}): string | null {
  const who = String(
    args.employeeName ?? args.card?.employee ?? args.card?.technician ?? '',
  ).trim();
  if (!who || who === '-' || who === '—') {
    return 'اسم الفني ما محفوظ ببطاقتك هسه، راح أسأل بالمحل وأردلك 🙏';
  }
  return `الفني اللي خدمك هو ${who} 👍`;
}

export function buildPriceReply(
  card: Record<string, string> | null,
): string | null {
  if (!card) {
    return 'مبلغ الزيارة ما محفوظ عندي هسه، راح أسأل بالمحل وأردلك 🙏';
  }
  const total = String(card.total ?? '').trim();
  const paid = String(card.paid ?? '').trim();
  const remaining = String(card.remaining ?? '').trim();
  const useful = (v: string) => !!v && v !== '-' && v !== '—';

  if (!useful(total) && !useful(paid) && !useful(remaining)) {
    return 'مبلغ الزيارة ما محفوظ عندي هسه، راح أسأل بالمحل وأردلك 🙏';
  }

  const bits: string[] = [];
  if (useful(total)) bits.push(`الإجمالي ${total}`);
  if (useful(paid)) bits.push(`المدفوع ${paid}`);
  if (useful(remaining)) bits.push(`المتبقي ${remaining}`);
  return `حسب بطاقتك: ${bits.join('، ')} 👍`;
}

export function buildLastServiceReply(
  card: Record<string, string> | null,
): string | null {
  if (!card) {
    return 'ما عندي بطاقة غيار محفوظة لهالرقم هسه، راح أسأل بالمحل وأردلك 🙏';
  }
  const useful = (v: string | undefined) => {
    const t = String(v ?? '').trim();
    return !!t && t !== '-' && t !== '—';
  };

  const bits: string[] = [];
  const who = String(card.customer ?? '').trim();
  if (useful(who)) bits.push(`${who}،`);

  const car = [card.car, card.car_model].filter(useful).join(' ');
  if (car) bits.push(`سيارتك ${car}`);

  const oilParts = [card.oil_brand, card.oil_grade, card.oil_size]
    .filter(useful);
  if (oilParts.length) bits.push(`الزيت: ${oilParts.join(' / ')}`);

  if (useful(card.odo_current)) {
    bits.push(`القراءة وقت الخدمة ${card.odo_current}`);
  }
  if (useful(card.odo_next)) {
    bits.push(`موعد الغيار القادم عند ${card.odo_next}`);
  }

  const tech = String(card.employee ?? '').trim();
  if (useful(tech)) bits.push(`الفني ${tech}`);

  if (bits.length <= (useful(who) ? 1 : 0)) {
    return 'تفاصيل آخر غيار مو مكتملة بالبطاقة، راح أسأل بالمحل وأردلك 🙏';
  }

  return `حسب آخر بطاقة عندنا: ${bits.join(' — ')} 👍`;
}

export function buildWarrantyMissingReply(): string {
  return 'رقم الضمان بالكيلومتر مو محفوظ بهالبطاقة هسه، راح أسأل بالمحل وأردلك 🙏';
}

export function buildCardFaqReply(args: {
  message: string;
  employeeName: string | null;
  card: Record<string, string> | null;
  warrantyReply: string | null;
  isWarrantyQuestion: boolean;
}): string | null {
  const msg = args.message;
  if (args.isWarrantyQuestion) {
    return args.warrantyReply ?? buildWarrantyMissingReply();
  }
  if (looksLikeEmployeeQuestion(msg)) {
    return buildEmployeeReply({
      employeeName: args.employeeName,
      card: args.card,
    });
  }
  if (looksLikePriceQuestion(msg)) {
    return buildPriceReply(args.card);
  }
  if (looksLikeLastServiceQuestion(msg)) {
    return buildLastServiceReply(args.card);
  }
  if (looksLikeGreeting(msg)) {
    return buildGreetingReply(
      args.employeeName,
      args.card?.customer ?? null,
    );
  }
  return null;
}
