import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { type Article, checkMemoryText, knowledgeMessage, lastUserText, pickArticles, scoreArticle } from './knowledge.ts';
import { buildMessages } from './prompt.ts';
import { runServerTool } from './server_tools.ts';

const art = (id: number, title: string, body: string, keywords = '', kind: Article['kind'] = 'library'): Article => ({
  id,
  kind,
  title,
  body,
  keywords,
});

const library = [
  art(1, 'زيت القير الأوتوماتيك', 'يُغيّر كل 60 ألف كم في ظروف العراق.', 'قير، جير، اوتوماتيك، ATF'),
  art(2, 'تجديد الاشتراك', 'من الإعدادات ثم الاشتراك، والدفع عبر الوكيل.', 'اشتراك، تجديد، دفع', 'naboo'),
  art(3, 'سائل التبريد', 'الأخضر والأحمر لا يُخلطان.', 'رديتر، تبريد، انتيفريز'),
];

Deno.test('library: keywords pick the right article, unrelated questions pick none', () => {
  assertEquals(pickArticles(library, 'شوكت أبدل زيت الجير الأوتوماتيك؟').map((a) => a.id), [1]);
  assertEquals(pickArticles(library, 'شلون أجدد الاشتراك').map((a) => a.id), [2]);
  assertEquals(pickArticles(library, 'شكد بعت اليوم'), []);
  assert(scoreArticle(library[2], 'الرديتر يغلي') >= 3);
});

Deno.test('library: at most two articles, best first', () => {
  const many = [art(10, 'فلتر الزيت', 'فلتر', 'فلتر'), art(11, 'فلتر الهواء', 'فلتر هواء', 'فلتر، هواء'), art(12, 'فلتر المكيف', 'فلتر', 'فلتر')];
  const got = pickArticles(many, 'فلتر الهواء');
  assertEquals(got.length, 2);
  assertEquals(got[0].id, 11);
});

Deno.test('memory text: phones and long amounts are refused, plain preferences pass', () => {
  assertEquals(checkMemoryText('  نفضّل   موبيل ون للسيارات الحديثة ').ok, true);
  assertEquals(checkMemoryText('رقم المورد 07701234567').ok, false);
  assertEquals(checkMemoryText('رقم المورد ٠٧٧٠١٢٣٤٥٦٧').ok, false);
  assertEquals(checkMemoryText('نغلق الجمعة، وسعر 5W-30 عندنا ثابت').ok, true);
  assertEquals(checkMemoryText('x'.repeat(201)).ok, false);
  assertEquals(checkMemoryText('   ').ok, false);
});

Deno.test('memory and library go in their own system message after the context', () => {
  const k = knowledgeMessage(['نغلق الجمعة'], [library[0]]);
  assert(k.includes('نغلق الجمعة'));
  assert(k.includes('زيت القير الأوتوماتيك'));
  assertEquals(knowledgeMessage([], []), '');
  const msgs = buildMessages(
    { isOwner: true, roleKey: 'owner', guideOnly: false, routeId: null, economy: false },
    [],
    [{ role: 'user', content: 'هلو' }],
    k,
  );
  assertEquals(msgs[msgs.length - 2].content, k);
  assertEquals(buildMessages({ isOwner: true, roleKey: 'owner', guideOnly: false, routeId: null, economy: false }, [], []).length, 2);
});

Deno.test('lastUserText reads text parts and skips images', () => {
  assertEquals(
    lastUserText([
      { role: 'user', content: 'قديم' },
      { role: 'assistant', content: 'x' },
      { role: 'user', content: [{ type: 'image_url', image_url: { url: 'data:image/jpeg;base64,AA' } }, { type: 'text', text: 'شنو هذا الزيت' }] },
    ]).trim(),
    'شنو هذا الزيت',
  );
});

/** قاعدة وهمية لذاكرة المحل. */
function memAdmin(existing: number) {
  const inserted: Record<string, unknown>[] = [];
  const admin = {
    from: () => {
      const api: Record<string, unknown> = {
        select: (_c: string, o?: { head?: boolean }) => (o?.head ? { eq: () => Promise.resolve({ count: existing }) } : api),
        insert: (row: Record<string, unknown>) => (inserted.push(row), api),
        single: () => Promise.resolve({ data: { id: 7 }, error: null }),
      };
      return api;
    },
  } as never;
  return { admin, inserted };
}

Deno.test('memory_save: saves for the caller tenant, refuses when full', async () => {
  const ok = memAdmin(3);
  const r = await runServerTool('memory_save', { text: 'ما نبيع معدني' }, {
    admin: ok.admin,
    tenantId: 't1',
    userId: 'u',
    roleKey: 'owner',
    routeId: null,
    createdBy: 'المالك',
  });
  assertEquals(r.result.ok, true);
  assertEquals(ok.inserted[0], { tenant_id: 't1', text: 'ما نبيع معدني', created_by: 'المالك' });

  const full = memAdmin(40);
  const r2 = await runServerTool('memory_save', { text: 'شي' }, { admin: full.admin, tenantId: 't1', userId: 'u', roleKey: 'owner', routeId: null });
  assertEquals(r2.result.error, 'memory_full');
  assertEquals(full.inserted.length, 0);
});

Deno.test('screen item: a known kind and numeric id become one context line', async () => {
  const { buildContextMessage } = await import('./prompt.ts');
  const base = { isOwner: true, roleKey: 'owner', guideOnly: false, routeId: null, economy: false };
  const line = buildContextMessage({ ...base, screenItem: { kind: 'product', id: 12 } });
  assert(line.includes('product_id=12'));
  assert(!buildContextMessage(base).includes('العنصر المفتوح'));
});
