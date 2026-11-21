/**
 * بحث منتجات/زيوت/غسيل من لقطة الحساب لنفس المستأجر فقط.
 * يظهر للزبون سعر البيع والتوفر فقط — بلا كمية ولا سعر شراء.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  loadSnapshotTables,
  type SnapshotTables,
} from './tenant_ai_context.ts';

export type OfferKind = 'product' | 'oil' | 'hydraulic' | 'filter' | 'wash';

export type InventoryOffer = {
  kind: OfferKind;
  name: string;
  searchName: string;
  /** ماركة الزيت/الهيدروليك إن وُجدت. */
  brand: string | null;
  /** اللزوجة أو الدرجة أو اسم الفلتر داخل مجموعته. */
  variant: string | null;
  /** تجميع الفلاتر: فلتر المحرك / الهواء / الكير. */
  groupLabel: string | null;
  /** سعر البيع المعروض بالدينار. 0 = غير محفوظ. */
  sellDinars: number;
  unit: string | null;
  inStock: boolean | null;
};

export const INVENTORY_UNKNOWN_REPLY =
  'ما أعرف هالمنتج بالقائمة هسه. اكتب الاسم مثل ما تعرفونه بالمحل وأدور عليه، وإذا ما طلع أجاوبك بصراحة 🙏';

export const INVENTORY_NEED_NAME_REPLY =
  'اكتب اسم المنتج أو الزيت (مثل ديفلون 0W16) وأردلك بالسعر وهل موجود بالمخزن 👍';

export const INVENTORY_SNAPSHOT_MISS_REPLY =
  'ما أگدر أشوف قائمة المحل هسه، راح أسأل بالمحل وأردلك على السعر والتوفر 🙏';

export const INVENTORY_EMPTY_LIST_REPLY =
  'هالقائمة مو محفوظة بالإعدادات هسه، راح أسأل بالمحل وأردلك عليها 🙏';

const CATALOG_INTENT_RE =
  /(اكو|يوجد|موجود|عندكم|عدكم|عندك|سعر|اسعار|يتوفر|توفر|متوفر|مخزون|نفذ|خلص|شكد|شگد|كم\s*سعر|هل|سمحت|اريد|أريد|ابي|أبي)/i;

const LIST_SIGNAL_RE =
  /(انواع|أنواع|جميع|كل\s*(ال)?|قائمه|قائمة|ماهي|ما\s*هي|لديكم|شنو\s*(ال)?(انواع|أنواع|زيوت|زيت|فلاتر|هيدروليك))/i;

const CATALOG_STOPWORDS = new Set([
  'هلا',
  'هلو',
  'مرحبا',
  'السلام',
  'عليكم',
  'شلون',
  'شنو',
  'ما',
  'هو',
  'هي',
  'ماهو',
  'شكد',
  'شگد',
  'كم',
  'سعر',
  'اسعار',
  'سعره',
  'سعرها',
  'اكو',
  'يوجد',
  'موجود',
  'عندكم',
  'عدكم',
  'عندك',
  'عندكو',
  'يتوفر',
  'توفر',
  'متوفر',
  'متوفره',
  'هل',
  'ممكن',
  'سمحت',
  'لوسمحت',
  'اريد',
  'أريد',
  'ابي',
  'أبي',
  'من',
  'ال',
  'في',
  'هذا',
  'هاي',
  'يا',
  'لو',
  'المحل',
  'المغسله',
  'المغسلة',
  'غيار',
  'صار',
  'صارت',
  'الحساب',
  'الاجمالي',
  'الإجمالي',
  'المبلغ',
  'الزياره',
  'الزيارة',
  'البطاقه',
  'البطاقة',
  'منتج',
  'منتجات',
  'صنف',
  'ارجوك',
  'رجاء',
  'لتر',
  'ليتر',
  'انواع',
  'أنواع',
  'جميع',
  'كل',
  'قائمه',
  'قائمة',
  'التي',
  'لديكم',
  'المتوفرة',
  'الموجودة',
  'زيت',
  'زيوت',
  'الزيت',
  'الزيوت',
  'هيدروليك',
  'الهيدروليك',
  'فلتر',
  'فلاتر',
  'الفلتر',
  'الفلاتر',
  'غسيل',
  'الغسيل',
]);

const MAX_PRODUCT_ROWS = 1200;
const MAX_CATALOG_ROWS = 400;
const MAX_MATCHES = 3;
const MAX_LIST_ITEMS = 40;
const MAX_LIST_CHARS = 3500;

const FILTER_KIND_LABEL: Record<string, string> = {
  engine: 'فلتر المحرك',
  air: 'فلتر الهواء',
  gear: 'فلتر الكير',
};

const BRAND_ALIAS_PAIRS: Array<[RegExp, string]> = [
  [/\bdeflone?\b/g, 'ديفلون'],
  [/\bcastrol\b/g, 'كاسترول'],
  [/\bmobil\b/g, 'موبيل'],
  [/\bshell\b/g, 'شل'],
];

export function normalizeSearchText(raw: string): string {
  let s = String(raw ?? '')
    .toLowerCase()
    .replace(/[أإآٱ]/g, 'ا')
    .replace(/[ة]/g, 'ه')
    .replace(/[ى]/g, 'ي')
    .replace(/[گک]/g, 'ك')
    .replace(/[-_]/g, ' ');
  for (const [re, ar] of BRAND_ALIAS_PAIRS) {
    s = s.replace(re, ar);
  }
  return s
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function inventoryQueryTokens(message: string): string[] {
  return normalizeSearchText(message)
    .split(' ')
    .filter((t) => t.length >= 2 && !CATALOG_STOPWORDS.has(t));
}

export function looksLikeInventoryQuestion(message: string): boolean {
  const t = String(message ?? '').trim();
  if (!t) return false;
  // «اريد عنوان المحل» ليست منتجاً رغم كلمة «اريد».
  if (/(عنوان|وين\s*(ال)?محل|رقمكم|هاتفك|لوكيشن|رابط\s*الخريطة)/i.test(t)) {
    return false;
  }
  if (detectCatalogListRequest(t)) return true;
  if (/\d+\s*w\s*\d+/i.test(t) && inventoryQueryTokens(t).length > 0) {
    return true;
  }
  if (!CATALOG_INTENT_RE.test(t)) return false;
  return true;
}

export function hasNamedInventoryQuery(message: string): boolean {
  return inventoryQueryTokens(message).length > 0;
}

export type CatalogListRequest = {
  kind: Exclude<OfferKind, 'product'>;
  brand: string | null;
};

/** «ما هي أنواع الزيوت / الفلاتر / الهيدروليك» أو ماركة معيّنة. */
export function detectCatalogListRequest(
  message: string,
): CatalogListRequest | null {
  const t = String(message ?? '').trim();
  if (!t) return null;
  if (/\d+\s*w\s*\d+/i.test(t)) return null;
  if (
    /(آخر\s*مرة|اخر\s*مرة|اللي\s*بدلت|بدلته|غيّرته)/i.test(t) &&
    !/(عندكم|عدكم|لديكم)/i.test(t)
  ) {
    return null;
  }

  const isHyd = /هيدروليك/.test(t);
  const isFilter = /فلاتر|(^|\s)فلتر(\s|$)/.test(t) &&
    /(انواع|أنواع|جميع|كل|قائمه|قائمة|ماهي|ما\s*هي|لديكم|عندكم)/i.test(t);
  const isWash = /(انواع|أنواع|جميع).{0,12}(غسيل|غسل)/.test(t) ||
    /غسيلات|انواع\s*الغسيل/.test(t);
  const isOil = /(زيوت|زيت)/.test(t) && !isHyd && !isFilter;

  const wantsList = LIST_SIGNAL_RE.test(t) ||
    /(الزيت|الزيوت|الفلاتر|الهيدروليك).{0,16}(عندكم|لديكم|عدكم|الموجود)/i.test(t) ||
    /اسعار\s*(ال)?(زيوت|زيت|فلاتر|هيدروليك|غسيل)/i.test(t);

  if (!wantsList) return null;

  let kind: CatalogListRequest['kind'] | null = null;
  if (isHyd) kind = 'hydraulic';
  else if (isFilter || /فلاتر/.test(t)) kind = 'filter';
  else if (isWash) kind = 'wash';
  else if (isOil) kind = 'oil';

  if (!kind) return null;

  const brandTokens = inventoryQueryTokens(t);
  const brand = brandTokens.length > 0 ? brandTokens.join(' ') : null;
  return { kind, brand };
}

function useful(raw: unknown): string | null {
  const s = String(raw ?? '').trim();
  if (!s || s === '-' || s === '—') return null;
  return s;
}

function isDeleted(row: Record<string, unknown>): boolean {
  const d = String(row.deletedAt ?? row.deleted_at ?? '').trim();
  return d.length > 0;
}

function isActiveProduct(row: Record<string, unknown>): boolean {
  if (isDeleted(row)) return false;
  const active = row.isActive ?? row.is_active;
  if (active === 0 || active === '0' || active === false) return false;
  const status = String(row.status ?? '').toLowerCase();
  if (status === 'archived' || status === 'inactive') return false;
  return true;
}

function numberOrZero(raw: unknown): number {
  const n = typeof raw === 'number' ? raw : Number(raw);
  return Number.isFinite(n) ? n : 0;
}

/** كتالوج بالفلس (1 دينار = 1000 فلس) → دينار للعرض. */
export function dinarsFromFils(fils: number): number {
  if (!Number.isFinite(fils) || fils <= 0) return 0;
  return Math.round(fils / 1000);
}

export function formatIqdDinars(dinars: number): string {
  const n = Math.round(dinars);
  if (!Number.isFinite(n) || n <= 0) return '';
  return `${n.toLocaleString('en-US')} د.ع`;
}

function productInStock(row: Record<string, unknown>): boolean {
  const status = String(row.status ?? '').toLowerCase();
  if (status === 'outofstock' || status === 'out_of_stock') return false;
  const track = row.trackInventory ?? row.track_inventory;
  if (track === 0 || track === '0' || track === false) return true;
  return numberOrZero(row.qty) > 0;
}

function parseLiters(message: string): number | null {
  const m = String(message ?? '').match(
    /(\d+(?:[.,]\d+)?)\s*(لتر|ليتر|L)\b/i,
  );
  if (!m) return null;
  const n = Number(String(m[1]).replace(',', '.'));
  if (!Number.isFinite(n) || n <= 0 || n > 40) return null;
  return n;
}

function brandNameById(tables: SnapshotTables): Map<string, string> {
  const map = new Map<string, string>();
  for (const row of tables['brands'] ?? []) {
    const id = String(row.id ?? '').trim();
    const name = useful(row.name);
    if (!id || !name) continue;
    map.set(id, name);
  }
  return map;
}

export function extractInventoryOffers(
  tables: SnapshotTables | null | undefined,
): InventoryOffer[] {
  if (!tables) return [];
  const out: InventoryOffer[] = [];
  const brands = brandNameById(tables);

  const products = tables['products'] ?? [];
  for (const row of products.slice(0, MAX_PRODUCT_ROWS)) {
    if (!isActiveProduct(row)) continue;
    const name = useful(row.name);
    if (!name) continue;
    const brand = useful(row.brandName) ??
      useful(row.brand_name) ??
      brands.get(String(row.brandId ?? row.brand_id ?? '').trim()) ??
      null;
    const search = brand ? `${brand} ${name}` : name;
    out.push({
      kind: 'product',
      name,
      searchName: normalizeSearchText(search),
      brand,
      variant: null,
      groupLabel: null,
      sellDinars: Math.round(numberOrZero(row.sellPrice ?? row.sell_price)),
      unit: useful(row.saleUnit ?? row.sale_unit),
      inStock: productInStock(row),
    });
  }

  const oils = tables['oil_change_oil_catalog'] ?? [];
  for (const row of oils.slice(0, MAX_CATALOG_ROWS)) {
    if (isDeleted(row)) continue;
    const brand = useful(row.brandName) ?? useful(row.brand_name);
    const vis = useful(row.viscosity);
    if (!brand) continue;
    const name = vis ? `${brand} ${vis}` : brand;
    out.push({
      kind: 'oil',
      name,
      searchName: normalizeSearchText(name),
      brand,
      variant: vis,
      groupLabel: null,
      sellDinars: dinarsFromFils(
        numberOrZero(row.sellPerLiterFils ?? row.sell_per_liter_fils),
      ),
      unit: 'لتر',
      inStock: null,
    });
  }

  const hyd = tables['oil_change_hydraulic_catalog'] ?? [];
  for (const row of hyd.slice(0, MAX_CATALOG_ROWS)) {
    if (isDeleted(row)) continue;
    const brand = useful(row.brandName) ?? useful(row.brand_name);
    const grade = useful(row.grade);
    if (!brand) continue;
    const name = grade ? `${brand} ${grade}` : brand;
    out.push({
      kind: 'hydraulic',
      name,
      searchName: normalizeSearchText(`هيدروليك ${name}`),
      brand,
      variant: grade,
      groupLabel: null,
      sellDinars: dinarsFromFils(
        numberOrZero(row.sellPerLiterFils ?? row.sell_per_liter_fils),
      ),
      unit: 'لتر',
      inStock: null,
    });
  }

  const filters = tables['oil_change_filter_catalog'] ?? [];
  for (const row of filters.slice(0, MAX_CATALOG_ROWS)) {
    if (isDeleted(row)) continue;
    const name = useful(row.name);
    if (!name) continue;
    const kindCode = String(row.filterKind ?? row.filter_kind ?? '')
      .trim()
      .toLowerCase();
    const groupLabel = FILTER_KIND_LABEL[kindCode] ?? 'فلاتر أخرى';
    out.push({
      kind: 'filter',
      name,
      searchName: normalizeSearchText(`فلتر ${name}`),
      brand: null,
      variant: name,
      groupLabel,
      sellDinars: dinarsFromFils(numberOrZero(row.priceFils ?? row.price_fils)),
      unit: null,
      inStock: null,
    });
  }

  const wash = tables['car_wash_services'] ?? [];
  for (const row of wash.slice(0, MAX_CATALOG_ROWS)) {
    if (isDeleted(row)) continue;
    const name = useful(row.name);
    if (!name) continue;
    out.push({
      kind: 'wash',
      name,
      searchName: normalizeSearchText(`غسيل ${name}`),
      brand: null,
      variant: name,
      groupLabel: 'غسيل',
      sellDinars: dinarsFromFils(numberOrZero(row.priceFils ?? row.price_fils)),
      unit: null,
      inStock: true,
    });
  }

  return out;
}

function tokenScore(name: string, query: string, tokens: string[]): number {
  if (!query || !name) return 0;
  if (name === query) return 1000;
  let score = 0;
  if (name.startsWith(query)) score += 400;
  else if (name.includes(query)) score += 150;

  const nameTokens = name.split(' ').filter(Boolean);
  let matched = 0;
  for (const token of tokens) {
    let best = 0;
    for (const part of nameTokens) {
      if (part === token) {
        best = 120;
        break;
      }
      if (part.startsWith(token)) best = Math.max(best, 90);
      else if (part.includes(token) || token.includes(part)) {
        best = Math.max(best, 40);
      }
    }
    if (best === 0) continue;
    matched += 1;
    score += best;
  }
  if (matched === 0) return 0;
  // لا تسقط النتيجة لأن حرف استفهام بقي بعد التطبيع — يكفينا تطابق الاسم.
  if (matched < tokens.length && score < 80) return 0;
  return Math.max(1, score - Math.floor(name.length / 8));
}

export function searchInventoryOffers(
  offers: InventoryOffer[],
  message: string,
): InventoryOffer[] {
  const tokens = inventoryQueryTokens(message);
  if (!tokens.length) return [];
  const query = tokens.join(' ');
  const ranked = offers
    .map((o) => ({ o, score: tokenScore(o.searchName, query, tokens) }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score);

  const seen = new Set<string>();
  const out: InventoryOffer[] = [];
  for (const { o } of ranked) {
    const key = o.searchName;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(o);
    if (out.length >= MAX_MATCHES) break;
  }
  return out;
}

function priceForList(offer: InventoryOffer): string {
  if (offer.sellDinars <= 0) return 'السعر غير محفوظ';
  if (offer.unit === 'لتر') return `${formatIqdDinars(offer.sellDinars)} / لتر`;
  return formatIqdDinars(offer.sellDinars);
}

function stockTag(offer: InventoryOffer): string {
  return offer.inStock === false ? ' — نفذ، يتوفر قريباً' : '';
}

export function filterOffersForCatalogList(
  offers: InventoryOffer[],
  req: CatalogListRequest,
): InventoryOffer[] {
  let rows = offers.filter((o) => o.kind === req.kind);
  if (req.brand) {
    const q = normalizeSearchText(req.brand);
    rows = rows.filter((o) => {
      const brand = normalizeSearchText(o.brand ?? '');
      return brand === q || brand.includes(q) || o.searchName.includes(q);
    });
  }
  return rows;
}

function groupKey(offer: InventoryOffer): string {
  if (offer.kind === 'filter') return offer.groupLabel || 'فلاتر';
  if (offer.kind === 'wash') return 'غسيل';
  return offer.brand?.trim() || offer.name;
}

function itemLabel(offer: InventoryOffer): string {
  if (offer.kind === 'oil' || offer.kind === 'hydraulic') {
    return offer.variant?.trim() || offer.name;
  }
  return offer.name;
}

export function formatCatalogListReply(
  offers: InventoryOffer[],
  req: CatalogListRequest,
): string {
  const rows = filterOffersForCatalogList(offers, req);
  if (!rows.length) {
    if (req.brand) {
      return `ماركة ${req.brand} مو بالقائمة هسه. اكتب الاسم الأقرب وأدور عليه، وإذا ما طلع أجاوبك بصراحة 🙏`;
    }
    return INVENTORY_EMPTY_LIST_REPLY;
  }

  const titles: Record<CatalogListRequest['kind'], string> = {
    oil: req.brand ? `زيوت ${req.brand} عندنا:` : 'أنواع الزيوت عندنا:',
    hydraulic: req.brand
      ? `هيدروليك ${req.brand} عندنا:`
      : 'أنواع الهيدروليك عندنا:',
    filter: 'أنواع الفلاتر عندنا:',
    wash: 'أنواع الغسيل عندنا:',
  };

  const grouped = new Map<string, InventoryOffer[]>();
  for (const row of rows) {
    const key = groupKey(row);
    const list = grouped.get(key) ?? [];
    list.push(row);
    grouped.set(key, list);
  }

  const lines: string[] = [titles[req.kind], ''];
  let shown = 0;
  let truncated = false;
  for (const [heading, items] of grouped) {
    if (shown >= MAX_LIST_ITEMS) {
      truncated = true;
      break;
    }
    if (req.kind === 'oil' || req.kind === 'hydraulic' || req.kind === 'filter') {
      lines.push(`*${heading}*`);
    }
    for (const item of items) {
      if (shown >= MAX_LIST_ITEMS) {
        truncated = true;
        break;
      }
      lines.push(`• ${itemLabel(item)} — ${priceForList(item)}${stockTag(item)}`);
      shown += 1;
    }
    lines.push('');
  }

  if (truncated) {
    lines.push('وفي أصناف بعد، اسأل عن ماركة أو اسم معيّن وأرتبها لك.');
  } else {
    lines.push('إذا تريد صنف معيّن أدق — اكتب اسمه 👍');
  }

  let text = lines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
  if (text.length > MAX_LIST_CHARS) {
    text = `${text.slice(0, MAX_LIST_CHARS)}\n…\nاسأل عن ماركة معيّنة لأعرضها مرتبة.`;
  }
  return text;
}

function formatOfferLine(
  offer: InventoryOffer,
  liters: number | null,
): string {
  const priceBits: string[] = [];
  if (offer.sellDinars > 0) {
    if (offer.unit === 'لتر' && liters != null) {
      priceBits.push(
        `${formatIqdDinars(offer.sellDinars * liters)} لـ ${liters} لتر`,
      );
    } else if (offer.unit === 'لتر') {
      priceBits.push(`${formatIqdDinars(offer.sellDinars)} للتر`);
    } else {
      priceBits.push(formatIqdDinars(offer.sellDinars));
    }
  }

  if (offer.inStock === false) {
    const price = priceBits.length
      ? ` سعره بالمحل ${priceBits[0]} إذا تحب تحجز.`
      : '';
    return `${offer.name} هسه نفذ من المخزن، راح يتوفر قريب إن شاء الله.${price}`;
  }

  if (!priceBits.length) {
    if (offer.inStock === true) {
      return `${offer.name} موجود، بس السعر مو محفوظ بالإعدادات هسه — راح أسأل بالمحل وأردلك 🙏`;
    }
    return `سعر ${offer.name} مو محفوظ بالإعدادات هسه، راح أسأل بالمحل وأردلك 🙏`;
  }

  if (offer.kind === 'wash') {
    return `غسيل ${offer.name}: ${priceBits[0]} 👍`;
  }
  if (offer.inStock === true) {
    return `${offer.name} موجود، السعر ${priceBits[0]} 👍`;
  }
  return `${offer.name} سعره ${priceBits[0]} 👍`;
}

export function buildInventoryReply(
  offers: InventoryOffer[],
  message: string,
): string | null {
  const listReq = detectCatalogListRequest(message);
  if (listReq) return formatCatalogListReply(offers, listReq);

  if (!looksLikeInventoryQuestion(message)) return null;
  if (!hasNamedInventoryQuery(message)) return INVENTORY_NEED_NAME_REPLY;

  const hits = searchInventoryOffers(offers, message);
  if (!hits.length) return INVENTORY_UNKNOWN_REPLY;

  const brandOnly = !/\d+\s*w\s*\d+/i.test(message);
  const catalogHit = hits.find((h) =>
    h.kind === 'oil' || h.kind === 'hydraulic'
  );
  if (brandOnly && catalogHit && catalogHit.brand) {
    const brandKey = normalizeSearchText(catalogHit.brand);
    const sameBrand = hits.every((h) =>
      (h.kind === 'oil' || h.kind === 'hydraulic') &&
      h.kind === catalogHit.kind &&
      normalizeSearchText(h.brand ?? '') === brandKey
    );
    if (sameBrand) {
      return formatCatalogListReply(offers, {
        kind: catalogHit.kind === 'hydraulic' ? 'hydraulic' : 'oil',
        brand: catalogHit.brand,
      });
    }
  }

  const liters = parseLiters(message);
  if (hits.length === 1) return formatOfferLine(hits[0], liters);

  return `لقينا أكثر من صنف:\n${
    hits.map((h) => `• ${formatOfferLine(h, liters)}`).join('\n')
  }`;
}

export async function lookupInventoryReply(
  db: SupabaseClient,
  args: { tenantUserId: string; message: string },
): Promise<string | null> {
  if (!looksLikeInventoryQuestion(args.message)) return null;
  const tenantUserId = String(args.tenantUserId ?? '').trim();
  if (!tenantUserId) return INVENTORY_SNAPSHOT_MISS_REPLY;

  try {
    const tables = await loadSnapshotTables(db, tenantUserId, {
      timeoutMs: 8000,
    });
    if (!tables) return INVENTORY_SNAPSHOT_MISS_REPLY;
    const offers = extractInventoryOffers(tables);
    return buildInventoryReply(offers, args.message);
  } catch (e) {
    console.warn('inventory lookup failed', String(e).slice(0, 160));
    return INVENTORY_SNAPSHOT_MISS_REPLY;
  }
}
