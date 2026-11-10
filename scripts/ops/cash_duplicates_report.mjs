// البند 4.2: مسودة قيود عكسية للبيع المكرر من النسخة المحلية للأرشيف. قراءة فقط،
// لا يكتب في أي حساب. يكتب تقريراً لكل حساب في مجلد النسخة.
import fs from 'node:fs';
import zlib from 'node:zlib';
import readline from 'node:readline';

const dir = process.argv[2];
const outDir = `${dir}/cash_duplicates_report`;
fs.mkdirSync(outDir, { recursive: true });

async function* rows(file) {
  const rl = readline.createInterface({
    input: fs.createReadStream(file).pipe(zlib.createGunzip()),
    crlfDelay: Infinity,
  });
  for await (const line of rl) if (line.trim()) yield JSON.parse(line);
}

// أجزاء اللقطات الحالية (للحسابات المجزأة)
const chunksByUpload = new Map();
for await (const c of rows(`${dir}/app_snapshot_chunks.ndjson.gz`)) {
  const k = `${c.user_id}|${c.upload_id || c.sync_id}`;
  if (!chunksByUpload.has(k)) chunksByUpload.set(k, []);
  chunksByUpload.get(k).push(c);
}

function resolvePayload(userId, payload) {
  if (!payload || typeof payload !== 'object') return null;
  if (payload.chunked !== true) return payload;
  const up = payload.upload_id || payload.sync_id;
  const parts = (chunksByUpload.get(`${userId}|${up}`) || [])
    .sort((a, b) => a.chunk_index - b.chunk_index);
  if (!parts.length || (payload.chunk_count && parts.length !== payload.chunk_count)) return null;
  try {
    if (payload.encoding === 'gzip-bytechunks-base64-v2') {
      const buf = Buffer.concat(parts.map((p) => Buffer.from(p.chunk_data, 'base64')));
      return JSON.parse(zlib.gunzipSync(buf).toString('utf8'));
    }
    const joined = parts.map((p) => p.chunk_data).join('');
    return JSON.parse(zlib.gunzipSync(Buffer.from(joined, 'base64')).toString('utf8'));
  } catch {
    return null;
  }
}

// قراءة فقط. لا يكتب في أي حساب. لكل حساب: مجموعات قيود بيع لنفس الفاتورة،
// وتصنيفها، ومسودة قيد عكسي لكل قيد زائد مرجّح. لا يُطبَّق شيء قبل موافقة المالك.
const fils = (r) => {
  const f = Number(r.amountFils || 0);
  return f !== 0 ? f : Math.round(Number(r.amount || 0) * 1000);
};
const live = (r) => !(r.deleted_at || r.deletedAt);
const invFils = (r) => {
  const f = Number(r.totalFils || 0);
  return f !== 0 ? f : Math.round(Number(r.total || 0) * 1000);
};

const summary = [];
for await (const s of rows(`${dir}/app_snapshots.ndjson.gz`)) {
  const p = resolvePayload(s.user_id, s.payload);
  const t = p && (p.tables || p);
  const cash = t && Array.isArray(t.cash_ledger) ? t.cash_ledger.filter(live) : null;
  if (!cash) continue;
  const invoices = new Map((Array.isArray(t.invoices) ? t.invoices : []).filter(live).map((i) => [String(i.id), i]));
  const groups = new Map();
  for (const r of cash) {
    if (!String(r.transactionType || '').startsWith('sale') || r.invoiceId == null || r.invoiceId === '') continue;
    const k = `${r.transactionType}|${r.invoiceId}`;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(r);
  }
  const items = [];
  for (const [k, list] of groups) {
    if (list.length < 2) continue;
    list.sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));
    const amounts = new Set(list.map(fils));
    const spanMs = Date.parse(list.at(-1).createdAt) - Date.parse(list[0].createdAt);
    const inv = invoices.get(String(list[0].invoiceId));
    const invTotal = inv ? invFils(inv) : null;
    const sum = list.reduce((a, r) => a + fils(r), 0);
    let verdict;
    if (amounts.size === 1 && spanMs <= 120000 && invTotal !== null && invTotal === fils(list[0]) && sum > invTotal) {
      verdict = 'likely_duplicate';
    } else if (amounts.size > 1) {
      verdict = 'different_invoices_same_local_id';
    } else {
      verdict = 'needs_owner_review';
    }
    items.push({
      group: k,
      verdict,
      invoice_total_fils: invTotal,
      entries: list.map((r) => ({ id: r.id, global_id: r.global_id || null, fils: fils(r), createdAt: r.createdAt })),
      // يبقى الأول، ويُعكس كل ما بعده بقيد سحب يحمل مرجع القيد الأصلي. لا حذف.
      draft_reversals: verdict === 'likely_duplicate'
        ? list.slice(1).map((r) => ({
            transactionType: 'manual_out',
            amountFils: fils(r),
            amount: fils(r) / 1000,
            invoiceId: r.invoiceId,
            description: `تصحيح قيد بيع مكرر للفاتورة ${r.invoiceId} (أصل القيد ${r.global_id || r.id})`,
            reverses_global_id: r.global_id || null,
            reverses_local_id: r.id,
          }))
        : [],
    });
  }
  if (!items.length) continue;
  const acct = String(s.user_id).slice(0, 8);
  fs.writeFileSync(`${outDir}/${acct}.json`, JSON.stringify({ user_id: s.user_id, snapshot_updated_at: s.updated_at, items }, null, 2));
  const by = (v) => items.filter((i) => i.verdict === v);
  const rev = by('likely_duplicate').flatMap((i) => i.draft_reversals);
  summary.push({
    acct,
    likely_duplicate_groups: by('likely_duplicate').length,
    draft_reversals: rev.length,
    reversal_dinar: rev.reduce((a, r) => a + r.amountFils, 0) / 1000,
    needs_owner_review: by('needs_owner_review').length,
    different_invoices_same_local_id: by('different_invoices_same_local_id').length,
  });
}
fs.writeFileSync(`${outDir}/summary.json`, JSON.stringify(summary, null, 2));
console.log(JSON.stringify(summary, null, 2));
