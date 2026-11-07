import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildFallbackOilCardPdf,
  formatInvoiceStamp,
  lineGlyphNames,
  loadTajawalBold,
  pdfLineRuns,
} from './build_pdf.ts';

Deno.test('السطر العربي يُبقي الرقم والتاريخ بلا قلب الخانات', () => {
  const phone = pdfLineRuns('رقم التواصل: 07884289711');
  assertEquals(phone.some((run) => run.ltr && run.text === '07884289711'), true);
  const stamp = pdfLineRuns('تاريخ الفاتورة: 24/10/2026 12:48');
  const ltr = stamp.filter((run) => run.ltr).map((run) => run.text);
  assertEquals(ltr.includes('24/10/2026'), true);
  assertEquals(ltr.includes('12:48'), true);
  assertEquals(ltr.includes('6202/01/42'), false);
});

Deno.test('الرابط اللاتيني لا يُعكس', () => {
  const url = 'https://www.google.com/maps/search/?api=1&query=30.5,47.8';
  const runs = pdfLineRuns(url);
  assertEquals(runs.length, 1);
  assertEquals(runs[0].text, url);
  assertEquals(runs[0].ltr, true);
});

Deno.test('تاريخ بغداد يُعرض يوماً ثم شهراً', () => {
  const stamp = formatInvoiceStamp('2026-10-24T00:04:00.000Z');
  assertEquals(stamp, '24/10/2026 03:04');
});

Deno.test('ملف البطاقة صفحة قصيرة وفيها التفاصيل بلا صف فارغ', async () => {
  const fontBytes = await Deno.readFile(
    new URL('./fonts/Tajawal-Regular.ttf', import.meta.url),
  );
  const boldFontBytes = await loadTajawalBold();
  const mapsUrl = 'https://www.google.com/maps/search/?api=1&query=30.5,47.8';
  const pdf = await buildFallbackOilCardPdf({
    fontBytes,
    boldFontBytes,
    shopName: 'بابل',
    address: 'بايل',
    phones: ['07884289711'],
    mapsUrl,
    issuedAt: '24/10/2026 13:02',
    card: {
      customer: 'محمد',
      car: 'رام',
      car_model: '2016',
      oil_grade: '5W20',
      odo_current: '180000 كم',
      total: '106,400 د.ع',
      shop: '-',
      plate: '-',
    },
  });
  assert(pdf.byteLength > 2000);
  assertEquals(pdf[0], 0x25);
  assertEquals(pdf[1], 0x50);
  assertEquals(pdf[2], 0x44);
  assertEquals(pdf[3], 0x46);
  const latin = new TextDecoder('latin1').decode(pdf);
  assertEquals(latin.includes('google.com'), false);
  assertEquals(latin.includes('https://'), false);
  assertEquals(latin.includes(mapsUrl), false);
});

Deno.test('الحروف المتصلة تبقى من اليمين والرقم لا ينقلب', async () => {
  const fontBytes = await Deno.readFile(
    new URL('./fonts/Tajawal-Regular.ttf', import.meta.url),
  );
  assertEquals(await lineGlyphNames(fontBytes, 'بابل'), [
    'uniFEDE',
    'uniFE91',
    'uniFE8E',
    'uniFE91',
  ]);
  const phone = await lineGlyphNames(fontBytes, 'رقم التواصل: 07884289711');
  assertEquals(phone.slice(0, 11), [
    'zero',
    'seven',
    'eight',
    'eight',
    'four',
    'two',
    'eight',
    'nine',
    'seven',
    'one',
    'one',
  ]);
  const stamp = await lineGlyphNames(fontBytes, 'تاريخ الفاتورة: 24/10/2026 13:02');
  assertEquals(stamp.slice(0, 5), ['one', 'three', 'colon', 'zero', 'two']);
  assertEquals(stamp.includes('four'), true);
  assertEquals(stamp.slice(0, 5).join(','), 'one,three,colon,zero,two');
});
