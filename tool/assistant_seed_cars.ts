/**
 * بذرة دليل السيارات (م1-15): الموديلات الأربعون من
 * docs/specs/naboo_assistant_seed_lists_ar.md بأسمائها الدارجة.
 *
 *   deno run -A tool/assistant_seed_cars.ts --aliases   يطبع SQL للأسماء الدارجة (بلا كلفة)
 *   deno run -A tool/assistant_seed_cars.ts --run       يبحث عن كل سيارة عبر assistant-chat (op: seed_car)
 *
 * --run يحتاج SUPABASE_URL وSUPABASE_ANON_KEY وEVAL_ACCESS_TOKEN لحساب المحل
 * النموذجي (tool/assistant_eval.local.env). الكلفة نحو 0.005 دولار لكل سيارة.
 * لا يطبع أي مفتاح.
 */

type Car = { make: string; model: string; year: number; engine: string; fuel?: string; aliases: string[] };

/** السنة والمحرك الأكثر شيوعاً لكل موديل؛ السنوات الأخرى تُبحث عند أول سؤال. */
export const CARS: Car[] = [
  { make: 'toyota', model: 'corolla', year: 2016, engine: '1.8', aliases: ['كورولا', 'كرولا'] },
  { make: 'toyota', model: 'camry', year: 2016, engine: '2.5', aliases: ['كامري', 'كمري'] },
  { make: 'toyota', model: 'land cruiser', year: 2016, engine: '4.6', aliases: ['لاندكروزر', 'لاندكروز', 'جكسارة', 'gxr', 'vxr'] },
  { make: 'toyota', model: 'prado', year: 2016, engine: '2.7', aliases: ['برادو'] },
  { make: 'toyota', model: 'hilux', year: 2016, engine: '2.7', aliases: ['هايلوكس', 'بيكب تويوتا', 'حوض'] },
  { make: 'toyota', model: 'yaris', year: 2016, engine: '1.5', aliases: ['يارس', 'يارِس'] },
  { make: 'toyota', model: 'avalon', year: 2016, engine: '3.5', aliases: ['افالون', 'أفالون'] },
  { make: 'toyota', model: 'fortuner', year: 2016, engine: '2.7', aliases: ['فورتشنر'] },
  { make: 'hyundai', model: 'elantra', year: 2016, engine: '2.0', aliases: ['النترا', 'ألنترا'] },
  { make: 'hyundai', model: 'sonata', year: 2016, engine: '2.4', aliases: ['سوناتا'] },
  { make: 'hyundai', model: 'accent', year: 2016, engine: '1.6', aliases: ['اكسنت', 'أكسنت'] },
  { make: 'hyundai', model: 'tucson', year: 2016, engine: '2.0', aliases: ['توسان', 'توكسان'] },
  { make: 'hyundai', model: 'santa fe', year: 2016, engine: '2.4', aliases: ['سنتافي', 'سانتافي'] },
  { make: 'hyundai', model: 'azera', year: 2016, engine: '3.0', aliases: ['ازيرا', 'أزيرا'] },
  { make: 'kia', model: 'cerato', year: 2016, engine: '2.0', aliases: ['سيراتو', 'فورتي'] },
  { make: 'kia', model: 'optima', year: 2016, engine: '2.4', aliases: ['اوبتيما', 'أوبتيما', 'كي فايف', 'k5'] },
  { make: 'kia', model: 'rio', year: 2016, engine: '1.4', aliases: ['ريو'] },
  { make: 'kia', model: 'sportage', year: 2016, engine: '2.0', aliases: ['سبورتج', 'سبورتاج'] },
  { make: 'kia', model: 'sorento', year: 2016, engine: '2.4', aliases: ['سورنتو', 'سورينتو'] },
  { make: 'kia', model: 'picanto', year: 2016, engine: '1.2', aliases: ['بيكانتو'] },
  { make: 'kia', model: 'pride', year: 2010, engine: '1.3', aliases: ['برايد', 'سايبا برايد'] },
  { make: 'nissan', model: 'sunny', year: 2016, engine: '1.5', aliases: ['صني'] },
  { make: 'nissan', model: 'altima', year: 2016, engine: '2.5', aliases: ['التيما', 'ألتيما'] },
  { make: 'nissan', model: 'patrol', year: 2016, engine: '5.6', aliases: ['باترول', 'بترول'] },
  { make: 'nissan', model: 'navara', year: 2016, engine: '2.5', fuel: 'diesel', aliases: ['نافارا', 'بيكب نيسان'] },
  { make: 'chevrolet', model: 'cruze', year: 2015, engine: '1.8', aliases: ['كروز'] },
  { make: 'chevrolet', model: 'malibu', year: 2016, engine: '2.5', aliases: ['ماليبو'] },
  { make: 'chevrolet', model: 'captiva', year: 2016, engine: '2.4', aliases: ['كابتيفا'] },
  { make: 'chevrolet', model: 'tahoe', year: 2016, engine: '5.3', aliases: ['تاهو'] },
  { make: 'gmc', model: 'yukon', year: 2016, engine: '5.3', aliases: ['يوكن', 'جمس'] },
  { make: 'ford', model: 'taurus', year: 2015, engine: '3.5', aliases: ['تورس'] },
  { make: 'mitsubishi', model: 'pajero', year: 2015, engine: '3.5', aliases: ['باجيرو', 'بجيرو'] },
  { make: 'mitsubishi', model: 'lancer', year: 2014, engine: '1.6', aliases: ['لانسر'] },
  { make: 'honda', model: 'accord', year: 2016, engine: '2.4', aliases: ['اكورد', 'أكورد'] },
  { make: 'honda', model: 'civic', year: 2016, engine: '2.0', aliases: ['سيفك', 'سيفيك'] },
  { make: 'saipa', model: 'saba', year: 2015, engine: '1.3', aliases: ['سايبا', 'صبا', 'سايبا 131'] },
  { make: 'iran khodro', model: 'samand', year: 2014, engine: '1.7', aliases: ['سمند'] },
  { make: 'chery', model: 'tiggo 7', year: 2021, engine: '1.5 turbo', aliases: ['تيكو', 'تيكو 7', 'شيري'] },
  { make: 'geely', model: 'emgrand', year: 2018, engine: '1.5', aliases: ['جيلي', 'امغراند', 'امكراند'] },
  { make: 'changan', model: 'cs35', year: 2020, engine: '1.6', aliases: ['شانجان', 'جانجان', 'cs35'] },
];

/** نفس تطبيع الخادم (assistant-chat/car_spec.ts → norm). */
function norm(s: string): string {
  return s.trim().toLowerCase()
    .replace(/[أإآ]/g, 'ا').replace(/ة/g, 'ه').replace(/ى/g, 'ي')
    .replace(/[^a-z0-9ء-ي]+/g, ' ').trim();
}

function aliasSql(): string {
  const rows = new Map<string, Car>();
  for (const c of CARS) {
    for (const a of [...c.aliases, c.model]) {
      // يُطابَق «الشركة + الموديل» كما يكتبهما النموذج، والموديل وحده أيضاً.
      rows.set(norm(a), c);
    }
  }
  const q = (s: string) => `'${s.replaceAll("'", "''")}'`;
  const values = [...rows].map(([k, c]) => `(${q(k)}, ${q(c.make)}, ${q(norm(c.model))})`).join(',\n  ');
  return `insert into public.assistant_car_aliases (alias_norm, make, model) values\n  ${values}\non conflict (alias_norm) do update set make = excluded.make, model = excluded.model;`;
}

async function run(): Promise<void> {
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  let token = Deno.env.get('EVAL_ACCESS_TOKEN') ?? '';
  if (!token && url && anon) {
    // دخول حساب المحل النموذجي من الملف المحلي (لا يُطبع شيء منه).
    const email = Deno.env.get('EVAL_EMAIL') ?? '';
    const password = Deno.env.get('EVAL_PASSWORD') ?? '';
    const r = await fetch(`${url}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: anon, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });
    token = String((await r.json().catch(() => ({})))?.access_token ?? '');
  }
  if (!url || !anon || !token) throw new Error('env missing or sign-in failed');
  let total = 0;
  for (const c of CARS) {
    const res = await fetch(`${url}/functions/v1/assistant-chat`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, apikey: anon, 'Content-Type': 'application/json' },
      body: JSON.stringify({ op: 'seed_car', car: { make: c.make, model: c.model, year: c.year, engine: c.engine, fuel: c.fuel } }),
    });
    const j = await res.json().catch(() => ({}));
    const row = j?.result?.rows?.[0];
    total += Number(j?.cost_micro_usd ?? 0);
    console.log([c.make, c.model, c.year, row?.capacity_l ?? '-', row?.oil ?? '-', row?.confidence ?? j?.result?.extra?.confidence ?? j?.error ?? '?'].join(' | '));
  }
  console.log(`total ≈ $${(total / 1e6).toFixed(4)}`);
}

if (import.meta.main) {
  if (Deno.args.includes('--aliases')) console.log(aliasSql());
  else if (Deno.args.includes('--run')) await run();
  else console.log('use --aliases or --run');
}
