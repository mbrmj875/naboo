import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildInvoiceRead } from '../assistant-chat/invoice_read.ts';
import { INVOICE_KEYS, INVOICE_PARTS, INVOICE_TRUTH, scoreInvoice } from './invoice_eval.ts';
import { INVOICE_IMAGES } from './invoice_fixtures.ts';

// الأسماء حرفياً كما في الفواتير العشر. لو قرأها النموذج كاملة يجب أن تنجح القواعد في كل سطر.
const RAW: Record<number, { supplier: string; no: string; date: string; raw: string[]; paid?: number; remaining?: number }> = {
  1: { supplier: 'مركز البصرة الدولي لتبديل الزيوت', no: '10452', date: '2026/11/10', raw: ['دهن محرك كاسترول ماجناتيك (4 لتر) 5W30', 'فلتر دهن تويوتا أصلي رقم 90915', 'فلتر شوتة (هواء) كورولا كوري', 'أجور تبديل دهن وفحص سوائل'] },
  2: { supplier: 'شركة الرافدين لتجارة الزيوت والشحوم والمعدات', no: 'INV-2026-89', date: '2026/11/12', raw: ['برميل زيت هيدروليك 68 (Hydraulic Oil) - توتال 200L', 'سطل كريس حراري عالي التحمل 15 كغم (Lithium Grease)', 'فلتر كاز كتربلر (CAT Fuel Filter) أصلي', 'فلتر هيدروليك حفارة كوماتسو'] },
  3: { supplier: 'بنشر ومغسلة النهرين الحديثة', no: '5519', date: '2026/11/14', raw: ['زيت محرك ليكوي مولي (Liqui Moly) 5W30 - 5 لتر', 'فلتر دهن هونداي/كيا أصلي', 'فلتر تبريد (مكيف) كربوني', 'منظف منظومة البنزين (Injector Cleaner)', 'غسل محرك بالبخار + تشحيم'] },
  4: { supplier: 'مكتب السندباد للزيوت الصناعية والبحرية', no: '9021', date: '2026/11/15', raw: ['دهن محرك ديزل شيل ريميولا (Shell Rimula R4) 15W40 - 20L', 'زيت هايدروليك 46 جركن 20 لتر', 'دهن كير بوكس 85W140 جركن 20 لتر', 'فلتر دهن ديزل كبير (Fleetguard)'] },
  5: { supplier: 'ورشة الأمانة لصيانة الكير الأوتوماتيك', no: '3104', date: '2026/11/17', raw: ['دهن كير أوتوماتيك نيسان (CVT NS-3) - 4 لتر', 'فلتر كير داخلي + كازكيت كارتير', 'فلتر كير خارجي صغير', 'أجور فتح وتنظيف وتبديل دهن كير بالجهاز'] },
  6: { supplier: 'محطة الكوت لزيوت السيارات الأمريكية', no: '774', date: '2026/11/18', raw: ['دهن موتور كرافت (Motorcraft) 5W20 - علب 6 مفرد', 'فلتر دهن موبار (Mopar) أصلي', 'ماء راديتر موبار أحمر مخفف 4 لتر', 'دهن بريك DOT 4 علبة صغيرة'] },
  7: { supplier: 'مخازن الحدباء لتجارة الفلاتر والزيوت', no: '6620', date: '2026/11/20', paid: 500000, remaining: 138000, raw: ['كارتون فلتر دهن تويوتا تجاري (50 قطعة)', 'كارتون دهن محرك 20W50 (4 × 4 لتر)', 'سطل كرس أزرق عادي 15 كيلو', 'منظف شوتة وكاربريتر بخاخ (كارتون 12 علبة)', 'فلتر بانزين خارجي متنوع'] },
  8: { supplier: 'مركز الفرات لصيانة السيارات الكورية', no: '1290', date: '2026/11/22', raw: ['زيت محرك أيسين (AISIN) 5W30 تخليقي بالكامل 4L', 'فلتر دهن موبيس (MOBIS) أصلي', 'فلتر شوتة إلنترا', 'فلاش محرك (Engine Flush) قبل التبديل', 'دهن ستيرن باور (PSF-4) لتر واحد'] },
  9: { supplier: 'شركة الخليج للزيوت الهيدروليكية والمعدات', no: '4401', date: '2026/11/25', raw: ['زيت هيدروليك مقاوم للحريق (HFD-U 46) برميل 208 لتر', 'دهن ضواغط الهواء (Compressor Oil) 100 جركن 20 لتر', 'فلتر هيدروليك ضغط عالي (Parker)', 'شحم موليبدينوم للآليات الثقيلة 18 كغم'] },
  10: { supplier: 'بنشر السريع لتبديل الدهن والتشحيم', no: '883', date: '2026/11/27', raw: ['دهن محرك توتال 10W40 جركن 5 لتر', 'فلتر دهن نيسان', 'دهن بككس 80W90 (2 لتر)', 'تشحيم كاردن وصلايب (تكريس كامل)'] },
};

Deno.test('ح3: القراءة الكاملة للفواتير العشر تنجح في كل حقل بالقواعد', () => {
  for (const t of INVOICE_TRUTH) {
    const r = RAW[t.id];
    const text = JSON.stringify({
      supplier: r.supplier,
      invoice_no: r.no,
      date: r.date,
      lines: t.lines.map((l, i) => ({ raw: r.raw[i], qty: l.qty, unit_price: l.unit, total: l.total })),
      grand_total: t.grand,
      paid: r.paid ?? null,
      remaining: r.remaining ?? null,
    });
    const s = scoreInvoice(`clean${t.id}`, t, buildInvoiceRead(text));
    assertEquals(s.fails, [], `الفاتورة ${t.id}`);
  }
});

Deno.test('ح3: كل صورة في القياس موجودة', () => {
  assertEquals(INVOICE_KEYS.length, 20);
  assertEquals(INVOICE_PARTS, 4);
  for (const k of INVOICE_KEYS) assert(INVOICE_IMAGES[k]?.startsWith('data:image/jpeg;base64,'), k);
});
