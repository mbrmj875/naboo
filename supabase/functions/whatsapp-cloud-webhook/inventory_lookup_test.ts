import {
  assertEquals,
  assertStringIncludes,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { looksLikePriceQuestion } from './card_faq.ts';
import {
  buildInventoryReply,
  dinarsFromFils,
  extractInventoryOffers,
  hasNamedInventoryQuery,
  INVENTORY_NEED_NAME_REPLY,
  INVENTORY_UNKNOWN_REPLY,
  looksLikeInventoryQuestion,
  searchInventoryOffers,
} from './inventory_lookup.ts';

const sampleTables = {
  products: [{
    name: 'فلتر هواء كوستر',
    sellPrice: 15000,
    qty: 4,
    isActive: 1,
    status: 'instock',
  }, {
    name: 'شامبو غسيل',
    sellPrice: 8000,
    qty: 0,
    isActive: 1,
    status: 'instock',
    trackInventory: 1,
  }],
  oil_change_oil_catalog: [{
    brandName: 'ديفلون',
    viscosity: '0W16',
    sellPerLiterFils: 8_000_000,
  }, {
    brandName: 'ديفلون',
    viscosity: '5W30',
    sellPerLiterFils: 9_000_000,
  }, {
    brandName: 'كاسترول',
    viscosity: '5W30',
    sellPerLiterFils: 12_000_000,
  }],
  oil_change_hydraulic_catalog: [{
    brandName: 'شل',
    grade: 'ATF',
    sellPerLiterFils: 11_000_000,
  }],
  oil_change_filter_catalog: [{
    name: 'تويوتا أصلي',
    filterKind: 'engine',
    priceFils: 15_000_000,
  }, {
    name: 'كيا هواء',
    filterKind: 'air',
    priceFils: 9_000_000,
  }],
  car_wash_services: [{
    name: 'خارجي',
    priceFils: 10_000_000,
  }],
};

Deno.test('سعر زيارة البطاقة يبقى لـ شكد صار سعر', () => {
  assertEquals(looksLikePriceQuestion('شكد صار سعر'), true);
  assertEquals(looksLikeInventoryQuestion('شكد صار سعر'), true);
  assertEquals(hasNamedInventoryQuery('شكد صار سعر'), false);
});

Deno.test('سعر منتج لا يُخلط مع إجمالي البطاقة', () => {
  assertEquals(looksLikePriceQuestion('شكد سعر ديفلون'), false);
  assertEquals(looksLikeInventoryQuestion('شكد سعر ديفلون'), true);
  assertEquals(hasNamedInventoryQuery('شكد سعر ديفلون'), true);
});

Deno.test('استخراج العروض بلا سعر شراء', () => {
  const offers = extractInventoryOffers(sampleTables);
  assertEquals(offers.some((o) => o.name === 'ديفلون 0W16'), true);
  assertEquals(offers.find((o) => o.name === 'شامبو غسيل')?.inStock, false);
  assertEquals(offers.find((o) => o.name === 'فلتر هواء كوستر')?.inStock, true);
  assertEquals(JSON.stringify(offers).includes('buyPrice'), false);
});

Deno.test('فلس الكتالوج يتحول لدينار', () => {
  assertEquals(dinarsFromFils(8_000_000), 8000);
});

Deno.test('زيت موجود بالسعر للتر', () => {
  const offers = extractInventoryOffers(sampleTables);
  const reply = buildInventoryReply(offers, 'شكد سعر ديفلون');
  assertStringIncludes(reply ?? '', 'ديفلون');
  assertStringIncludes(reply ?? '', '8,000 د.ع');
  assertEquals(
    (reply ?? '').includes('/ لتر') || (reply ?? '').includes('للتر'),
    true,
  );
});

Deno.test('نفاد المخزن بدون ذكر الكمية', () => {
  const offers = extractInventoryOffers(sampleTables);
  const reply = buildInventoryReply(offers, 'اكو شامبو غسيل');
  assertStringIncludes(reply ?? '', 'نفذ');
  assertEquals(/(qty|كمية|قطعة)/i.test(reply ?? ''), false);
});

Deno.test('منتج غير معروف لا يُخترع', () => {
  const offers = extractInventoryOffers(sampleTables);
  const reply = buildInventoryReply(offers, 'اكو موبيل 1');
  assertEquals(reply, INVENTORY_UNKNOWN_REPLY);
});

Deno.test('سؤال بلا اسم يطلب التوضيح', () => {
  const offers = extractInventoryOffers(sampleTables);
  assertEquals(buildInventoryReply(offers, 'اكو'), INVENTORY_NEED_NAME_REPLY);
});

Deno.test('سعر غسيل من كتالوج المغسلة', () => {
  const offers = extractInventoryOffers(sampleTables);
  const hits = searchInventoryOffers(offers, 'سعر غسيل خارجي');
  assertEquals(hits[0]?.kind, 'wash');
  const reply = buildInventoryReply(offers, 'سعر غسيل خارجي');
  assertStringIncludes(reply ?? '', 'خارجي');
  assertStringIncludes(reply ?? '', '10,000 د.ع');
});

Deno.test('قائمة الزيوت مرتبة بالماركة والسعر', () => {
  const offers = extractInventoryOffers(sampleTables);
  const reply = buildInventoryReply(offers, 'ما هي أنواع الزيوت التي لديكم');
  assertStringIncludes(reply ?? '', 'أنواع الزيوت');
  assertStringIncludes(reply ?? '', '*ديفلون*');
  assertStringIncludes(reply ?? '', '0W16');
  assertStringIncludes(reply ?? '', '5W30');
  assertStringIncludes(reply ?? '', '*كاسترول*');
  assertStringIncludes(reply ?? '', '8,000');
});

Deno.test('زيوت ماركة معيّنة فقط', () => {
  const offers = extractInventoryOffers(sampleTables);
  const reply = buildInventoryReply(offers, 'ما هي أنواع زيوت ديفلون');
  assertStringIncludes(reply ?? '', 'ديفلون');
  assertStringIncludes(reply ?? '', '0W16');
  assertEquals((reply ?? '').includes('كاسترول'), false);
});

Deno.test('قائمة الهيدروليك', () => {
  const offers = extractInventoryOffers(sampleTables);
  const reply = buildInventoryReply(offers, 'ما هي أنواع الهيدروليك');
  assertStringIncludes(reply ?? '', 'هيدروليك');
  assertStringIncludes(reply ?? '', 'شل');
  assertStringIncludes(reply ?? '', 'ATF');
});

Deno.test('قائمة الفلاتر مجمّعة بالفئة', () => {
  const offers = extractInventoryOffers(sampleTables);
  const reply = buildInventoryReply(offers, 'ما هي أنواع الفلاتر');
  assertStringIncludes(reply ?? '', 'فلتر المحرك');
  assertStringIncludes(reply ?? '', 'تويوتا أصلي');
  assertStringIncludes(reply ?? '', 'فلتر الهواء');
  assertStringIncludes(reply ?? '', '15,000');
});

Deno.test('هل يوجد عدكم زيت ديفلون يجد الماركة', () => {
  const offers = extractInventoryOffers(sampleTables);
  const reply = buildInventoryReply(offers, 'هل يوجد عدكم زيت ديفلون؟');
  assertStringIncludes(reply ?? '', 'ديفلون');
  assertStringIncludes(reply ?? '', '0W16');
  assertEquals((reply ?? '').includes('كاسترول'), false);
});

Deno.test('ديفلون متوفر وdeflon يطويان للاسم العربي', () => {
  const offers = extractInventoryOffers(sampleTables);
  const a = buildInventoryReply(offers, 'ديفلون متوفر');
  const b = buildInventoryReply(offers, 'deflon موجود');
  assertStringIncludes(a ?? '', 'ديفلون');
  assertStringIncludes(b ?? '', 'ديفلون');
});

Deno.test('شنو الزيت عندكم يعرض القائمة لا التخمين', () => {
  const offers = extractInventoryOffers(sampleTables);
  const reply = buildInventoryReply(offers, 'شنو الزيت عندكم');
  assertStringIncludes(reply ?? '', 'أنواع الزيوت');
  assertStringIncludes(reply ?? '', 'ديفلون');
  assertStringIncludes(reply ?? '', 'كاسترول');
});

Deno.test('منتج عبر brands.name', () => {
  const offers = extractInventoryOffers({
    ...sampleTables,
    products: [{
      name: '0W16 كامل',
      brandId: 7,
      sellPrice: 22000,
      qty: 2,
      isActive: 1,
      status: 'instock',
    }],
    brands: [{ id: 7, name: 'ديفلون' }],
  });
  const hits = offers.filter((o) => o.kind === 'product');
  assertEquals(hits[0]?.brand, 'ديفلون');
  const reply = buildInventoryReply(offers, 'اكو ديفلون كامل');
  assertStringIncludes(reply ?? '', '0W16');
});
