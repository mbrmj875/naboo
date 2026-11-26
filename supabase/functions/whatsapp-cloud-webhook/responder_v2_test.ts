import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { InventoryOffer } from './inventory_lookup.ts';
import {
  ASK_SHOP_REPLY,
  asksPriceOrOffer,
  buildFactLines,
  buildResponderSystem,
  type CarAlias,
  type CarSpecRow,
  effectiveTone,
  isMediaMessage,
  matchCar,
  matchingOils,
  offerActive,
  parseProfile,
  parseResponder,
  type ResponderFacts,
  silenceEndsAt,
} from './responder_v2.ts';

const NOW = new Date('2026-11-24T09:00:00Z'); // 12 ظهراً ببغداد

const profile = parseProfile({
  enabled: true,
  hours: 'كل يوم من 9 الصبح إلى 9 بالليل، الجمعة عطلة',
  services: ['تبديل زيت', 'غسيل'],
  service_duration: 'الغيار ربع ساعة',
  offer_text: 'غسيل مجاني مع كل غيار',
  offer_until: '2026-12-31',
  notes: [{ text: 'نقبل الدفع زين كاش', source: 'owner' }],
  tone: 'playful',
})!;

const oil = (name: string, variant: string, dinars: number, inStock: boolean | null): InventoryOffer => ({
  kind: 'oil',
  name,
  searchName: name.toLowerCase(),
  brand: name.split(' ')[0],
  variant,
  groupLabel: null,
  sellDinars: dinars,
  unit: 'لتر',
  inStock,
});

const camry: CarSpecRow = {
  make: 'toyota',
  model: 'camry',
  year_from: 2012,
  year_to: 2017,
  oil_capacity_l: 4.4,
  viscosity_primary: '0W-20',
  viscosity_alt: null,
  oil_spec: 'API SN',
  confidence: 'verified',
  locked: false,
};
const malibu: CarSpecRow = { ...camry, make: 'chevrolet', model: 'malibu', viscosity_primary: '5W-20', confidence: 'single_source' };
const aliases: CarAlias[] = [
  { alias_norm: 'كامري', make: 'toyota', model: 'camry' },
  { alias_norm: 'ماليبو', make: 'chevrolet', model: 'malibu' },
];

function facts(over: Partial<ResponderFacts> = {}): ResponderFacts {
  return {
    shop: {
      card: null,
      storeName: 'محل النموذج',
      storePhone: '07700000000',
      storePhones: ['07700000000'],
      storeAddress: 'البصرة، الجزائر',
      mapsUrl: null,
      employeeName: null,
    },
    card: { customer: 'أبو علي', car: 'تويوتا كامري', odo_current: '120000', odo_next: '125000', remaining: '0' },
    profile,
    stock: [oil('توتال 0W-20', '0W-20', 12000, true)],
    snapshotAgeHours: 3,
    car: { status: 'none' },
    carOils: [],
    articles: [],
    lessons: [],
    stranger: false,
    score: null,
    ...over,
  };
}

Deno.test('م6-6 مفتاح الأسعار مطفأ: لا سعر في الحقائق، والحارس يرد أي مبلغ', () => {
  const off = { ...profile, mention_prices: false };
  const f = facts({ profile: off });
  const text = buildFactLines(f, 'شكد سعر توتال؟', NOW).join('\n');
  assert(!text.includes('12,000') && !text.includes('السعر'), text);
  const d = parseResponder('{"reply":"سعر توتال 12 ألف دينار 👍","is_feedback":false,"handoff":null}', f, text);
  assertEquals(d?.reply, ASK_SHOP_REPLY);
  assertEquals(d?.handoff, 'no_answer');
  // مفتاح التوفر مطفأ: لا «متوفر» في الحقائق.
  const noStock = buildFactLines(facts({ profile: { ...profile, mention_stock: false } }), 'عدكم توتال؟', NOW).join('\n');
  assert(!noStock.includes('متوفر'));
});

Deno.test('م6-6 الأسلوب: التقييم 3 أو أقل يفرض الهادئ ويسلّم لإنسان', () => {
  assertEquals(effectiveTone('playful', 2), 'calm');
  assertEquals(effectiveTone('formal', 9), 'formal');
  assert(!buildResponderSystem('calm').includes('خفة دم'));
  const f = facts({ score: 2 });
  const d = parseResponder('{"reply":"نعتذر منك على التجربة، وراح نتواصل وياك.","is_feedback":true,"handoff":null}', f, '');
  assertEquals(d?.handoff, 'low_rating');
});

Deno.test('م6-7 نصيحة الزيت: المؤكد بمواصفته وصنفه، وغير المؤكد يُسلَّم', () => {
  const m = matchCar('عندي كامري 2015 شنو الزيت المناسب؟', [camry, malibu], aliases);
  assertEquals(m.status, 'verified');
  const oils = matchingOils(camry, [oil('توتال 0W-20', '0W-20', 12000, true), oil('شل 5W-30', '5W-30', 9000, true)]);
  assertEquals(oils.map((o) => o.name), ['توتال 0W-20']);
  const text = buildFactLines(facts({ car: m, carOils: oils }), 'شنو الزيت؟', NOW).join('\n');
  assert(text.includes('0W-20') && text.includes('4.4 لتر') && text.includes('توتال'));

  const u = matchCar('ماليبو 2016', [camry, malibu], aliases);
  assertEquals(u.status, 'unverified', 'مصدر واحد ليس مؤكداً');
  assert(buildFactLines(facts({ car: u }), 'ماليبو', NOW).join('\n').includes('غير مؤكدة'));
  assertEquals(matchCar('كامري 2005', [camry], aliases).status, 'unverified', 'سنة خارج المدى');
  assertEquals(matchCar('شكد سعر الغسيل', [camry], aliases).status, 'none');
});

Deno.test('م6-8 لقطة قديمة: «غالباً متوفر، يتأكد من المحل» بدل الجزم', () => {
  const fresh = buildFactLines(facts({ snapshotAgeHours: 2 }), 'عدكم توتال؟', NOW).join('\n');
  const stale = buildFactLines(facts({ snapshotAgeHours: 40 }), 'عدكم توتال؟', NOW).join('\n');
  assert(fresh.includes('، متوفر'));
  assert(stale.includes('غالباً متوفر، يتأكد من المحل'));
});

Deno.test('م6-16 بطاقته الأخيرة فقط، والغريب بلا بطاقة', () => {
  const text = buildFactLines(facts(), 'شنو آخر غيار؟', NOW).join('\n');
  assertEquals(text.split('بطاقة آخر زيارة').length - 1, 1);
  assert(text.includes('أبو علي'));
  const stranger = buildFactLines(facts({ card: null, stranger: true }), 'شنو آخر غيار؟', NOW).join('\n');
  assert(!stranger.includes('أبو علي') && stranger.includes('رقم جديد'));
  assert(buildResponderSystem('playful').includes('بيانات أي زبون آخر'));
});

Deno.test('م6-17 العرض عند السؤال عن السعر فقط، وبعد تاريخه لا يُذكر', () => {
  assert(buildFactLines(facts(), 'شكد سعر الغيار؟', NOW).join('\n').includes('غسيل مجاني'));
  assert(!buildFactLines(facts(), 'متى تفتحون؟', NOW).join('\n').includes('غسيل مجاني'));
  assert(asksPriceOrOffer('عدكم عروض؟'));
  assert(!offerActive({ ...profile, offer_until: '2026-11-01' }, NOW));
});

Deno.test('الحراس: الدوام بلا صفحة، والوعد بخصم بلا عرض، ومبلغ مخترع', () => {
  const noHours = facts({ profile: { ...profile, hours: '' } });
  assertEquals(parseResponder('{"reply":"نفتح الساعة 8 الصبح يومياً 👍","handoff":null}', noHours, '')?.guarded, 'hours');
  const withHours = facts();
  const t = buildFactLines(withHours, 'متى تفتحون؟', NOW).join('\n');
  assertEquals(parseResponder('{"reply":"نفتح كل يوم من 9 الصبح إلى 9 بالليل.","handoff":null}', withHours, t)?.guarded, null);
  const noOffer = facts({ profile: { ...profile, offer_text: '' } });
  assertEquals(parseResponder('{"reply":"تعال وراح نسويلك خصم حلو 😉","handoff":null}', noOffer, '')?.guarded, 'promise');
  const t2 = buildFactLines(withHours, 'شكد سعر توتال؟', NOW).join('\n');
  assertEquals(parseResponder('{"reply":"توتال سعره 12 ألف دينار للتر.","handoff":null}', withHours, t2)?.guarded, null);
  assertEquals(parseResponder('{"reply":"توتال سعره 15 ألف دينار للتر.","handoff":null}', withHours, t2)?.guarded, 'unknown_amount');
  assertEquals(parseResponder('{"reply":"أرباحنا اليوم ممتازة","handoff":null}', withHours, '')?.handoff, 'no_answer');
});

Deno.test('القرار: التسليم وطلب الزيارة من json، والتالف يُرفض', () => {
  const d = parseResponder(
    '{"reply":"أهلاً بيك، ننتظرك بأوقات الدوام.","is_feedback":false,"handoff":null,"visit":{"car":"كامري","request":"غيار باچر"}}',
    facts(),
    '',
  );
  assertEquals(d?.visit, { car: 'كامري', request: 'غيار باچر' });
  assertEquals(parseResponder('{"reply":"المحل راح يتواصل وياك بخصوص العطل.","handoff":"fault"}', facts(), '')?.handoff, 'fault');
  assertEquals(parseResponder('ليس json', facts(), ''), null);
});

Deno.test('الصمت بعد التسليم، والصور والصوت', () => {
  assertEquals(silenceEndsAt('30m', NOW).toISOString(), '2026-11-24T09:30:00.000Z');
  assertEquals(silenceEndsAt('2h', NOW).toISOString(), '2026-11-24T11:00:00.000Z');
  assertEquals(silenceEndsAt('eod', NOW).toISOString(), '2026-11-24T21:00:00.000Z', 'منتصف ليل بغداد');
  assert(isMediaMessage('image', null));
  assert(isMediaMessage('audio', ''));
  assert(!isMediaMessage('text', 'هلا'));
});
