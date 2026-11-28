import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { appKind, buildInvoiceRead, categorize, lastImage, normalizeName, perPack, toNumber, viscosity } from './invoice_read.ts';

Deno.test('ح3: القاموس المحلي يحوّل المصطلحات إلى أسماء قياسية', () => {
  assertEquals(normalizeName('فلتر شوتة (هواء) كورولا كوري'), 'فلتر هواء كورولا كوري');
  assertEquals(normalizeName('فلتر شوتة إلنترا'), 'فلتر هواء إلنترا');
  assertEquals(normalizeName('دهن بككس 80W90 (2 لتر)'), 'زيت دفرنس 80W-90 (2 لتر)');
  assertEquals(normalizeName('دهن ستيرن باور (PSF-4) لتر واحد'), 'زيت باور ستيرنك (PSF-4) لتر واحد');
  assertEquals(normalizeName('سطل كرس أزرق عادي 15 كيلو'), 'سطل شحم أزرق عادي 15 كيلو');
  assertEquals(normalizeName('دهن بريك DOT 4 علبة صغيرة'), 'زيت فرامل DOT 4 علبة صغيرة');
  // «شوتة» مع منظف لا تصير فلتر هواء.
  assert(normalizeName('منظف شوتة وكاربريتر بخاخ').includes('شوتة'));
});

Deno.test('ح3: التصنيف يفرّق الزيوت والهيدروليك والفلاتر والخدمات', () => {
  const c = (s: string) => categorize(normalizeName(s));
  assertEquals(c('دهن محرك كاسترول ماجناتيك (4 لتر) 5W30'), 'engine_oil');
  assertEquals(c('دهن موتور كرافت (Motorcraft) 5W20 - علب 6 مفرد'), 'engine_oil');
  assertEquals(c('برميل زيت هيدروليك 68 (Hydraulic Oil) - توتال 200L'), 'hydraulic');
  assertEquals(c('زيت هيدروليك مقاوم للحريق (HFD-U 46) برميل 208 لتر'), 'hydraulic');
  assertEquals(c('دهن كير بوكس 85W140 جركن 20 لتر'), 'gear_oil');
  assertEquals(c('دهن كير أوتوماتيك نيسان (CVT NS-3) - 4 لتر'), 'atf');
  assertEquals(c('دهن بككس 80W90 (2 لتر)'), 'differential');
  assertEquals(c('دهن ستيرن باور (PSF-4) لتر واحد'), 'power_steering');
  assertEquals(c('دهن ضواغط الهواء (Compressor Oil) 100 جركن 20 لتر'), 'compressor_oil');
  assertEquals(c('فلتر دهن تويوتا أصلي رقم 90915'), 'oil_filter');
  assertEquals(c('فلتر دهن ديزل كبير (Fleetguard)'), 'oil_filter');
  assertEquals(c('فلتر شوتة (هواء) كورولا كوري'), 'air_filter');
  assertEquals(c('فلتر تبريد (مكيف) كربوني'), 'cabin_filter');
  assertEquals(c('فلتر كاز كتربلر (CAT Fuel Filter) أصلي'), 'fuel_filter');
  assertEquals(c('فلتر بانزين خارجي متنوع'), 'fuel_filter');
  assertEquals(c('فلتر هيدروليك حفارة كوماتسو'), 'hydraulic_filter');
  assertEquals(c('فلتر كير داخلي + كازكيت كارتير'), 'transmission_filter');
  assertEquals(c('سطل كريس حراري عالي التحمل 15 كغم (Lithium Grease)'), 'grease');
  assertEquals(c('شحم موليبدينوم للآليات الثقيلة 18 كغم'), 'grease');
  assertEquals(c('ماء راديتر موبار أحمر مخفف 4 لتر'), 'coolant');
  assertEquals(c('دهن بريك DOT 4 علبة صغيرة'), 'brake_fluid');
  assertEquals(c('منظف منظومة البنزين (Injector Cleaner)'), 'additive');
  assertEquals(c('فلاش محرك (Engine Flush) قبل التبديل'), 'additive');
  assertEquals(c('أجور تبديل دهن وفحص سوائل'), 'service');
  assertEquals(c('غسل محرك بالبخار + تشحيم'), 'service');
  assertEquals(c('تشحيم كاردن وصلايب (تكريس كامل)'), 'service');
  assertEquals(appKind('hydraulic'), 'hydraulic');
  assertEquals(appKind('air_filter'), 'filter');
  assertEquals(appKind('service'), null);
});

Deno.test('ح3: الأرقام والعبوات', () => {
  assertEquals(toNumber('48,000'), 48000);
  assertEquals(toNumber('٤٨٠٠٠'), 48000);
  assertEquals(toNumber('1.115.000'), 1115000);
  assertEquals(viscosity('85W140'), '85W-140');
  assertEquals(perPack('كارتون دهن محرك 20W50 (4 × 4 لتر)'), 4);
  assertEquals(perPack('كارتون فلتر دهن تويوتا تجاري (50 قطعة)'), 50);
  assertEquals(perPack('دهن محرك 4 لتر'), null);
});

Deno.test('ح3: التحقق الحسابي يعلّم ولا يصحح', () => {
  const r = buildInvoiceRead(JSON.stringify({
    supplier: 'مخازن الحدباء',
    invoice_no: '6620',
    date: '2026/11/20',
    lines: [
      { raw: 'كارتون دهن محرك 20W50 (4 × 4 لتر)', qty: 5, unit_price: '68,000', total: '340,000' },
      { raw: 'فلتر بانزين خارجي', qty: 20, unit_price: 3500, total: 75000 },
      { raw: 'أجور تبديل', qty: 1, unit_price: null, total: 5000 },
    ],
    grand_total: 420000,
    paid: 400000,
    remaining: 20000,
  }));
  assertEquals(r.date, '2026-11-20');
  assertEquals(r.lines[0].stock_qty, 20);
  assertEquals(r.lines[0].stock_unit_price, 17000);
  assert(r.lines[0].flags.includes('pack'));
  assert(r.lines[1].flags.includes('math'));
  assertEquals(r.lines[2].unit_price, 5000);
  assert(r.lines[2].service);
  assertEquals(r.goods, 2);
  assertEquals(r.services, 1);
  assertEquals(r.total_ok, true);
});

Deno.test('ح3: الأسعار المكتوبة بالآلاف باليد تُضرب بألف وتُعلَّم', () => {
  const r = buildInvoiceRead(JSON.stringify({
    lines: [{ raw: 'دهن توتال 4 لتر', qty: 2, unit_price: 24, total: 48 }],
    grand_total: 48,
    handwritten: true,
  }));
  assert(r.scaled_thousands);
  assertEquals(r.lines[0].unit_price, 24000);
  assertEquals(r.grand_total, 48000);
  assertEquals(r.total_ok, true);
});

Deno.test('ح3: آخر صورة في المحادثة', () => {
  assertEquals(lastImage([
    { role: 'user', content: [{ type: 'text', text: 'x' }, { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,AA' } }] },
    { role: 'assistant', content: 'ok' },
  ]), 'data:image/jpeg;base64,AA');
  assertEquals(lastImage([{ role: 'user', content: 'بلا صورة' }]), null);
});

Deno.test('ح3: القراءات الخاطئة الشائعة للصور المائلة تُردّ لأصلها', () => {
  assertEquals(normalizeName('كاربون ديه مترك 20W50 (4 × 4 لتر)'), 'كارتون زيت محرك 20W-50 (4 × 4 لتر)');
  assertEquals(categorize(normalizeName('فلتر شنوة (هوا) كورولا')), 'air_filter');
  assertEquals(categorize(normalizeName('زيت سبرن باور (PSF-4)')), 'power_steering');
  // «فلتر تبريد كربوني» لا يتغيّر: التصحيح في أول السطر فقط.
  assert(normalizeName('فلتر تبريد (مكيف) كربوني').includes('كربوني'));
});

Deno.test('ح3: كارتون بعدد غير معقول أو غير واضح لا يُحوَّل ويُعلَّم', () => {
  const r = buildInvoiceRead(JSON.stringify({
    lines: [
      { raw: 'كارتون دهن محرك 20W50 (50 × 4 لتر)', qty: 5, unit_price: 68000, total: 340000 },
      { raw: 'منظف شوتة بخاخ (كارتون)', qty: 2, unit_price: 24000, total: 48000 },
    ],
    grand_total: 388000,
  }));
  assertEquals(r.lines[0].stock_qty, 5);
  assert(r.lines[0].flags.includes('pack_unknown'));
  assert(r.lines[1].flags.includes('pack_unknown'));
});
