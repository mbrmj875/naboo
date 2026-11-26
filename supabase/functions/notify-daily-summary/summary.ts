/**
 * الملخص اليومي (المرحلة 4) من نسخة بيانات المحل. بلا شبكة، قابل للاختبار.
 * docs/specs/notifications_master_plan_ar.md — المرحلة 4.
 */
import type { SnapshotTables } from '../owner-alert-push-cron/types.ts';

type Row = Record<string, unknown>;

/** InvoiceType في التطبيق: 0 نقدي، 1 آجل، 2 تقسيط، 3 توصيل، 4 و5 سندات قبض، 6 دفع مورد. */
const SALE_TYPES = new Set([0, 1, 2, 3]);
const FINANCED_TYPES = new Set([1, 2]);
const TYPE_NAMES: Record<string, number> = {
  cash: 0, credit: 1, installment: 2, delivery: 3,
  debtCollection: 4, installmentCollection: 5, supplierPayment: 6,
};

export type DailySummary = {
  ymd: string;
  salesFils: number;
  invoiceCount: number;
  yesterdaySalesFils: number;
  yesterdayCount: number;
  profitFils: number;
  debtFils: number;
  returnsFils: number;
  returnsCount: number;
  tomorrow: { installmentsDue: number; lowStock: number; expiringSoon: number };
  hasActivity: boolean;
};

const BAGHDAD_OFFSET_MS = 3 * 3600 * 1000;
export function baghdadYmdOffset(now: Date, days: number): string {
  return new Date(now.getTime() + BAGHDAD_OFFSET_MS + days * 86400_000).toISOString().slice(0, 10);
}

function tenantOf(r: Row): number {
  const v = r.tenantId ?? r.tenant_id;
  const n = typeof v === 'number' ? v : parseInt(String(v ?? ''), 10);
  return Number.isFinite(n) && n > 0 ? n : 1;
}
function alive(r: Row): boolean {
  const d = r.deleted_at ?? r.deletedAt;
  return d == null || String(d).trim() === '' || String(d) === 'null';
}
function fils(r: Row, filsKey: string, iqdKey: string): number {
  const f = Number(r[filsKey] ?? 0);
  if (Number.isFinite(f) && f !== 0) return f;
  const v = Number(r[iqdKey] ?? 0);
  return Number.isFinite(v) ? Math.round(v * 1000) : 0;
}
function typeOf(r: Row): number {
  const t = r.type;
  if (typeof t === 'number') return t;
  const s = String(t ?? '');
  if (s in TYPE_NAMES) return TYPE_NAMES[s];
  const n = parseInt(s, 10);
  return Number.isFinite(n) ? n : -1;
}
const day = (raw: unknown) => String(raw ?? '').trim().slice(0, 10);

export function computeDailySummary(tables: SnapshotTables, tenantId: number, now: Date): DailySummary {
  const today = baghdadYmdOffset(now, 0);
  const yesterday = baghdadYmdOffset(now, -1);
  const tomorrow = baghdadYmdOffset(now, 1);
  const weekAhead = baghdadYmdOffset(now, 7);

  let salesFils = 0, invoiceCount = 0, ySales = 0, yCount = 0, debtFils = 0, returnsFils = 0, returnsCount = 0;
  const todaySaleIds = new Set<number>();

  for (const inv of tables.invoices ?? []) {
    if (!alive(inv) || tenantOf(inv) !== tenantId) continue;
    const d = day(inv.date);
    if (d !== today && d !== yesterday) continue;
    const total = fils(inv, 'totalFils', 'total');
    const returned = Number(inv.isReturned ?? inv.is_returned ?? 0) === 1;
    const t = typeOf(inv);
    if (returned) {
      if (d === today) { returnsFils += total; returnsCount++; }
      continue;
    }
    if (!SALE_TYPES.has(t)) continue;
    if (d === yesterday) { ySales += total; yCount++; continue; }
    salesFils += total;
    invoiceCount++;
    todaySaleIds.add(Number(inv.id));
    if (FINANCED_TYPES.has(t)) {
      debtFils += Math.max(0, total - fils(inv, 'advancePaymentFils', 'advancePayment'));
    }
  }

  // الربح كما في تقارير التطبيق: مجموع (سعر البيع − الكلفة × الكمية) لبنود فواتير اليوم.
  let profitFils = 0;
  for (const it of tables.invoice_items ?? []) {
    if (!alive(it)) continue;
    if (!todaySaleIds.has(Number(it.invoiceId ?? it.invoice_id))) continue;
    profitFils += fils(it, 'totalFils', 'total') - Number(it.unitCostFils ?? 0) * Number(it.quantity ?? 0);
  }

  // غدا: أقساط تستحق، نواقص، وأصناف تنتهي صلاحيتها خلال أسبوع.
  const plans = new Map<number, Row>();
  for (const p of tables.installment_plans ?? []) plans.set(Number(p.id), p);
  const invTenant = new Map<number, number>();
  for (const inv of tables.invoices ?? []) invTenant.set(Number(inv.id), tenantOf(inv));
  let installmentsDue = 0;
  for (const i of tables.installments ?? []) {
    if (Number(i.paid ?? 0) === 1 || !alive(i)) continue;
    if (day(i.dueDate ?? i.due_date) !== tomorrow) continue;
    const plan = plans.get(Number(i.planId ?? i.plan_id));
    const t = plan ? invTenant.get(Number(plan.invoiceId ?? plan.invoice_id)) ?? 1 : 1;
    if (t === tenantId) installmentsDue++;
  }

  let lowStock = 0, expiringSoon = 0;
  for (const p of tables.products ?? []) {
    if (!alive(p) || tenantOf(p) !== tenantId || Number(p.isActive ?? 1) !== 1) continue;
    if (Number(p.trackInventory ?? 1) === 1) {
      const qty = Number(p.qty ?? 0);
      const th = Number(p.lowStockThreshold ?? 0);
      if (qty <= 0 || (th > 0 && qty <= th)) lowStock++;
    }
    const exp = day(p.expiryDate ?? p.expiry_date);
    if (exp && exp >= today && exp <= weekAhead && Number(p.qty ?? 0) > 0) expiringSoon++;
  }

  return {
    ymd: today,
    salesFils, invoiceCount,
    yesterdaySalesFils: ySales, yesterdayCount: yCount,
    profitFils, debtFils, returnsFils, returnsCount,
    tomorrow: { installmentsDue, lowStock, expiringSoon },
    hasActivity: invoiceCount > 0 || returnsCount > 0,
  };
}

export function iqd(f: number): string {
  return `${Math.round(f / 1000).toLocaleString('en-US')} د.ع`;
}

/**
 * نص شاشة القفل يحمل القسم الأول فقط (المبيعات وعدد الفواتير ومقارنة بأمس).
 * الربح والباقي داخل التطبيق فقط (قرارك).
 */
export function summaryText(s: DailySummary): { title: string; body: string } {
  const title = `ملخص اليوم: ${iqd(s.salesFils)}`;
  let cmp = '';
  if (s.yesterdaySalesFils > 0) {
    const pct = Math.round(((s.salesFils - s.yesterdaySalesFils) / s.yesterdaySalesFils) * 100);
    cmp = pct === 0 ? '، مثل أمس' : pct > 0 ? `، أعلى من أمس بـ${pct}%` : `، أقل من أمس بـ${-pct}%`;
  }
  return { title, body: `${s.invoiceCount} فاتورة${cmp}. افتح الإشعار لترى الربح والتفاصيل.` };
}
