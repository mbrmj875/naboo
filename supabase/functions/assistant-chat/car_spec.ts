/**
 * خبير السيارات (4.9، م1-13، م1-14): الدليل المشترك أولاً، والبحث عند الغياب.
 *
 * - الطلب الفرعي معزول: لا يحمل إلا الصنع والموديل والسنة والمحرك.
 * - الثقة تُحسب من المصادر بعد وصولها، لأن أداة البحث لا تقبل حصر النطاقات.
 * - verified وsingle_source تُحفظان. unverified لا تُحفظ ولا تُعرض أرقامها.
 */
import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { chat, type ChatResult, type Usage, type WebSource, ZERO_USAGE } from '../_shared/llm.ts';

export type CarQuery = { make: string; model: string; year?: number; engine?: string; fuel?: string };

export type CarFacts = {
  capacity_l?: number;
  viscosity_primary?: string;
  viscosity_alt?: string;
  oil_spec?: string;
  filter_refs?: string[];
  interval_km?: number;
  year_from?: number;
  year_to?: number;
  per_source?: { url: string; capacity_l?: number; viscosity?: string; official?: boolean }[];
};

export type Confidence = 'verified' | 'single_source' | 'unverified';

/** الصانع → كلمات نطاقه الرسمي (دليل المالك على موقع الشركة يكفي وحده). */
const MAKER_DOMAINS: Record<string, string[]> = {
  toyota: ['toyota'], lexus: ['lexus', 'toyota'], hyundai: ['hyundai'], kia: ['kia'], nissan: ['nissan', 'infiniti'],
  honda: ['honda'], mitsubishi: ['mitsubishi'], chevrolet: ['chevrolet', 'gm.com'], gmc: ['gmc', 'gm.com'],
  ford: ['ford'], mazda: ['mazda'], suzuki: ['suzuki'], volkswagen: ['volkswagen', 'vw.com'], bmw: ['bmw'],
  mercedes: ['mercedes'], chery: ['chery'], geely: ['geely'], changan: ['changan'], peugeot: ['peugeot'],
  renault: ['renault'], dodge: ['dodge', 'mopar'], jeep: ['jeep', 'mopar'], isuzu: ['isuzu'], subaru: ['subaru'],
};

/** أسماء عربية شائعة للصانع. الأسماء الدارجة للموديلات في جدول assistant_car_aliases. */
const MAKE_AR: Record<string, string> = {
  'تويوتا': 'toyota', 'لكزس': 'lexus', 'هيونداي': 'hyundai', 'هونداي': 'hyundai', 'كيا': 'kia', 'نيسان': 'nissan',
  'هوندا': 'honda', 'متسوبيشي': 'mitsubishi', 'ميتسوبيشي': 'mitsubishi', 'شفرليت': 'chevrolet', 'شيفروليه': 'chevrolet',
  'شوفرليت': 'chevrolet', 'جمس': 'gmc', 'فورد': 'ford', 'مازدا': 'mazda', 'سوزوكي': 'suzuki', 'فولكس': 'volkswagen',
  'بي ام': 'bmw', 'مرسيدس': 'mercedes', 'شيري': 'chery', 'جيلي': 'geely', 'شانجان': 'changan', 'بيجو': 'peugeot',
  'رينو': 'renault', 'دوج': 'dodge', 'جيب': 'jeep', 'ايسوزو': 'isuzu', 'سوبارو': 'subaru',
};

export function norm(s: string): string {
  return s.trim().toLowerCase()
    .replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي')
    .replace(/[^a-z0-9ء-ي]+/g, ' ').trim();
}

export function normMake(make: string): string {
  const n = norm(make);
  return MAKE_AR[n] ?? n;
}

export function domainOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return '';
  }
}

/** الجذر المسجَّل للنطاق (toyota.com و parts.toyota.com نطاق واحد). */
function rootOf(host: string): string {
  const p = host.split('.');
  return p.length <= 2 ? host : p.slice(-2).join('.');
}

export function isOfficial(url: string, make: string): boolean {
  const host = domainOf(url);
  return (MAKER_DOMAINS[normMake(make)] ?? [normMake(make)]).some((k) => k.length >= 2 && host.includes(k));
}

const VISC = /(\d{1,2})\s*w\s*-?\s*(\d{2})/i;
export function normViscosity(v?: string): string | undefined {
  const m = v ? VISC.exec(v) : null;
  return m ? `${Number(m[1])}W-${Number(m[2])}` : undefined;
}

/**
 * درجة الثقة (4.9): مصدر رسمي واحد، أو نطاقان مختلفان يتفقان على السعة
 * (بفارق 0.2 لتر) واللزوجة = verified. مصدر واحد غير رسمي = single_source.
 * تعارض أو لا مصدر = unverified.
 */
export function grade(f: CarFacts, sources: WebSource[], make: string): Confidence {
  if (f.capacity_l == null || !normViscosity(f.viscosity_primary)) return 'unverified';
  const per = (f.per_source ?? []).filter((p) => /^https?:\/\//.test(p.url));
  const v = normViscosity(f.viscosity_primary);
  const agree = per.filter((p) =>
    p.capacity_l != null && Math.abs(p.capacity_l - f.capacity_l!) <= 0.2 &&
    (!p.viscosity || normViscosity(p.viscosity) === v)
  );
  const conflict = per.some((p) =>
    (p.capacity_l != null && Math.abs(p.capacity_l - f.capacity_l!) > 0.2) ||
    (p.viscosity && normViscosity(p.viscosity) && normViscosity(p.viscosity) !== v)
  );
  if (agree.some((p) => isOfficial(p.url, make))) return 'verified';
  const roots = new Set(agree.map((p) => rootOf(domainOf(p.url))).filter(Boolean));
  if (conflict) {
    // أغلبية واضحة من مواقع مختلفة رغم مخالف (مثلاً محرك أوروبي بنفس الاسم):
    // تُعرض بتنبيه وتذهب لمراجعة صاحب المشروع، ولا تُوثَّق تلقائياً.
    const against = new Set(
      per.filter((p) => !agree.includes(p) && (p.capacity_l != null || p.viscosity))
        .map((p) => rootOf(domainOf(p.url))).filter(Boolean),
    );
    return roots.size >= 2 && roots.size > against.size ? 'single_source' : 'unverified';
  }
  if (roots.size >= 2) return 'verified';
  if (agree.length >= 1 || sources.length >= 1) return 'single_source';
  return 'unverified';
}

/** يقرأ أول كائن JSON من النص. */
export function parseFacts(text: string): CarFacts | null {
  const a = text.indexOf('{');
  const b = text.lastIndexOf('}');
  if (a < 0 || b <= a) return null;
  try {
    const o = JSON.parse(text.slice(a, b + 1)) as Record<string, unknown>;
    const num = (x: unknown) => (typeof x === 'number' && isFinite(x) ? x : typeof x === 'string' && x.trim() !== '' && isFinite(Number(x)) ? Number(x) : undefined);
    const str = (x: unknown, max = 40) => (typeof x === 'string' && x.trim() ? x.trim().slice(0, max) : undefined);
    const per = Array.isArray(o.per_source) ? o.per_source : [];
    return {
      capacity_l: num(o.capacity_l),
      viscosity_primary: normViscosity(str(o.viscosity_primary)),
      viscosity_alt: normViscosity(str(o.viscosity_alt)),
      oil_spec: str(o.oil_spec, 80),
      filter_refs: Array.isArray(o.filter_refs) ? o.filter_refs.map(String).map((s) => s.trim().slice(0, 30)).filter(Boolean).slice(0, 6) : [],
      interval_km: num(o.interval_km),
      year_from: num(o.year_from),
      year_to: num(o.year_to),
      per_source: per.filter((p): p is Record<string, unknown> => !!p && typeof p === 'object').map((p) => ({
        url: String(p.url ?? ''),
        capacity_l: num(p.capacity_l),
        viscosity: str(p.viscosity),
        official: p.official === true,
      })).slice(0, 8),
    };
  } catch {
    return null;
  }
}

const SEARCH_PROMPT = `ابحث في الإنترنت عن مواصفات زيت المحرك لهذه السيارة، وأجب بكائن JSON واحد فقط بلا شرح:
{"capacity_l": سعة الزيت مع الفلتر باللتر, "viscosity_primary": "اللزوجة الموصى بها", "viscosity_alt": "بديل مقبول أو null",
 "oil_spec": "المواصفة API/ACEA/ILSAC", "filter_refs": ["رقم فلتر الزيت الأصلي"], "interval_km": فترة الغيار بالكيلومتر,
 "year_from": أول سنة تنطبق عليها, "year_to": آخر سنة,
 "per_source": [{"url": "رابط المصدر", "capacity_l": السعة فيه, "viscosity": "اللزوجة فيه", "official": true إن كان موقع الشركة أو دليل المالك}]}
اكتب في per_source كل مصدر قرأته بما قاله هو، حتى لو اختلف. لا تخمّن: الحقل المجهول null.`;

/** آخر بحث، لعملية البذرة فقط (المحل النموذجي) لتشخيص الفشل. */
export let lastSearchDebug: Record<string, unknown> | null = null;

export type LookupDeps = {
  admin: SupabaseClient;
  search?: (q: CarQuery) => Promise<ChatResult>;
  /** مهلة البحث؛ البذرة تعطي وقتاً أطول. */
  timeoutMs?: number;
};

/**
 * طلب البحث الفرعي. مقيس 2026-11-24: التفكير وخطوات البحث تستهلك 900 رمز
 * قبل الجواب فيرجع فارغاً («length»)، فالحد 4000. المهلة 25 ثانية في المحادثة،
 * وأطول في البذرة.
 */
async function webSearch(q: CarQuery, timeoutMs = 25_000): Promise<ChatResult> {
  const car = [q.make, q.model, q.year, q.engine, q.fuel].filter(Boolean).join(' ');
  return chat({
    messages: [{ role: 'system', content: SEARCH_PROMPT }, { role: 'user', content: car }],
    tools: [{ type: 'deepseek_web_search' }],
    effort: 'low',
    maxTokens: 4000,
  }, timeoutMs);
}

type SpecRow = Record<string, unknown>;

function toRow(r: SpecRow, make: string, model: string): Record<string, unknown> {
  const years = r.year_from === r.year_to ? `${r.year_from}` : `${r.year_from}–${r.year_to}`;
  return {
    model: `${make} ${model} ${years}`.trim(),
    capacity_l: r.oil_capacity_l == null ? undefined : Number(r.oil_capacity_l),
    oil: r.viscosity_primary ?? undefined,
    oil_alt: r.viscosity_alt ?? undefined,
    spec: r.oil_spec ?? undefined,
    filter: Array.isArray(r.oil_filter_refs) && r.oil_filter_refs.length ? (r.oil_filter_refs as string[]).join('، ') : undefined,
    interval_km: r.interval_km ?? undefined,
    confidence: r.confidence,
    sources: r.sources ?? [],
  };
}

/** نتيجة بصيغة الهاتف (AssistantToolResult.fromStore) + الكلفة. */
export async function carSpec(q: CarQuery, deps: LookupDeps): Promise<{ result: Record<string, unknown>; usage: Usage; usedWeb: boolean }> {
  const make = normMake(q.make ?? '');
  let model = norm(q.model ?? '');
  if (!make || !model) return { result: { ok: false, tool: 'car_spec', error: 'bad_args:missing_model' }, usage: ZERO_USAGE, usedWeb: false };

  // الاسم الدارج («كامري الكبيرة»، «النترا الشبح») من جدول صاحب المشروع.
  let mk = make;
  for (const key of [norm(`${q.make} ${q.model}`), model]) {
    const alias = await deps.admin.from('assistant_car_aliases').select('make, model').eq('alias_norm', key).maybeSingle();
    if (alias.data) {
      mk = String(alias.data.make);
      model = String(alias.data.model);
      break;
    }
  }
  const year = q.year && q.year > 1970 && q.year < 2100 ? Math.round(q.year) : null;

  let sel = deps.admin.from('assistant_car_specs').select('*').eq('make', mk).eq('model', model);
  if (year) sel = sel.lte('year_from', year).gte('year_to', year);
  const found = await sel.order('confidence', { ascending: false }).limit(1);
  const hit = found.data?.[0] as SpecRow | undefined;
  if (hit && (hit.confidence === 'verified' || hit.locked)) {
    await deps.admin.from('assistant_car_specs').update({ hits: Number(hit.hits ?? 0) + 1 }).eq('id', hit.id);
    return { result: ok([toRow(hit, mk, model)], { from: 'guide' }), usage: ZERO_USAGE, usedWeb: false };
  }

  // غائب، أو بمصدر واحد فيُعاد فحصه وقد يرتقي.
  let r: ChatResult;
  try {
    r = deps.search ? await deps.search({ ...q, make: mk, model }) : await webSearch({ ...q, make: mk, model }, deps.timeoutMs);
    lastSearchDebug = { text: r.text.slice(0, 1500), sources: (r.sources ?? []).length, finish: r.finish };
  } catch (e) {
    lastSearchDebug = {
      error: e instanceof Error ? e.message.slice(0, 300) : String(e).slice(0, 300),
      detail: (e as { detail?: string; status?: number }).detail ?? null,
      status: (e as { status?: number }).status ?? null,
    };
    if (hit) return { result: ok([toRow(hit, mk, model)], { from: 'guide' }), usage: ZERO_USAGE, usedWeb: false };
    return { result: { ok: false, tool: 'car_spec', error: 'search_failed' }, usage: ZERO_USAGE, usedWeb: true };
  }
  const facts = parseFacts(r.text);
  const sources = r.sources ?? [];
  const conf = facts ? grade(facts, sources, mk) : 'unverified';
  if (!facts || conf === 'unverified') {
    if (hit) return { result: ok([toRow(hit, mk, model)], { from: 'guide' }), usage: r.usage, usedWeb: true };
    return {
      result: ok([], { confidence: 'unverified', note: 'المصادر متعارضة أو غير كافية' }),
      usage: r.usage,
      usedWeb: true,
    };
  }

  const fetched = new Date().toISOString();
  const srcUrls = new Set((facts.per_source ?? []).map((p) => p.url));
  const srcList = [...sources.filter((s) => srcUrls.size === 0 || srcUrls.has(s.url)), ...[...srcUrls].filter((u) => !sources.some((s) => s.url === u)).map((url) => ({ url, title: domainOf(url) }))]
    .slice(0, 5).map((s) => ({ url: s.url, title: s.title || domainOf(s.url), fetched_at: fetched }));
  const y = year ?? new Date().getFullYear();
  const row: SpecRow = {
    make: mk,
    model,
    year_from: Math.min(facts.year_from ?? y, y),
    year_to: Math.max(facts.year_to ?? y, y),
    engine: q.engine?.slice(0, 40) ?? null,
    fuel: ['petrol', 'diesel', 'hybrid'].includes(q.fuel ?? '') ? q.fuel : null,
    oil_capacity_l: facts.capacity_l,
    viscosity_primary: facts.viscosity_primary,
    viscosity_alt: facts.viscosity_alt ?? null,
    oil_spec: facts.oil_spec ?? null,
    oil_filter_refs: facts.filter_refs ?? [],
    interval_km: facts.interval_km && facts.interval_km >= 1000 && facts.interval_km <= 50000 ? Math.round(facts.interval_km) : null,
    sources: srcList,
    confidence: conf,
    hits: Number(hit?.hits ?? 0) + 1,
    updated_at: fetched,
  };
  if (hit) {
    await deps.admin.from('assistant_car_specs').update(row).eq('id', hit.id);
  } else {
    await deps.admin.from('assistant_car_specs').insert(row);
  }
  return { result: ok([toRow(row, mk, model)], { from: 'web' }), usage: r.usage, usedWeb: true };
}

function ok(rows: Record<string, unknown>[], extra: Record<string, unknown>): Record<string, unknown> {
  return {
    ok: true,
    tool: 'car_spec',
    rows,
    total: rows.length,
    source: 'من دليل نابو للسيارات',
    as_of: new Date().toISOString(),
    extra,
  };
}
