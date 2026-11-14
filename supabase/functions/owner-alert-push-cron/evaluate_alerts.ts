import type {
  OwnerAlertFeatureFlags,
  OwnerAlertPrefs,
  OwnerAlertThresholds,
  PushAlertCandidate,
  SnapshotTables,
} from './types.ts';
import { DEFAULT_FEATURE_FLAGS, DEFAULT_THRESHOLDS } from './types.ts';

const OIL_CHANGE_KIND = 'oil_change';
const REPAIR_KIND = 'repair';
const CLOTHING_VARIANT_KIND = 2;
const VOLUME_LITER_KIND = 1;

export function parseThresholds(raw: Record<string, number>): OwnerAlertThresholds {
  const n = (k: keyof OwnerAlertThresholds, fallback: number) => {
    const v = raw[k as string];
    return typeof v === 'number' && Number.isFinite(v) ? Math.trunc(v) : fallback;
  };
  return {
    stockShortageMinCount: n('stockShortageMinCount', DEFAULT_THRESHOLDS.stockShortageMinCount),
    variantShortageMinCount: n('variantShortageMinCount', DEFAULT_THRESHOLDS.variantShortageMinCount),
    slowMoversMinCount: n('slowMoversMinCount', DEFAULT_THRESHOLDS.slowMoversMinCount),
    slowMoversDays: n('slowMoversDays', DEFAULT_THRESHOLDS.slowMoversDays),
    garageStaleHours: n('garageStaleHours', DEFAULT_THRESHOLDS.garageStaleHours),
    garageStaleMinCount: n('garageStaleMinCount', DEFAULT_THRESHOLDS.garageStaleMinCount),
    activeGarageMinCount: n('activeGarageMinCount', DEFAULT_THRESHOLDS.activeGarageMinCount),
    debtorsMinCount: n('debtorsMinCount', DEFAULT_THRESHOLDS.debtorsMinCount),
    installmentOverdueMinCount: n('installmentOverdueMinCount', DEFAULT_THRESHOLDS.installmentOverdueMinCount),
    installmentDueTodayMinCount: n('installmentDueTodayMinCount', DEFAULT_THRESHOLDS.installmentDueTodayMinCount),
  };
}

export function parseFeatureFlags(raw: unknown): OwnerAlertFeatureFlags {
  if (!raw || typeof raw !== 'object') return DEFAULT_FEATURE_FLAGS;
  const o = raw as Record<string, unknown>;
  return {
    enableDebts: o.enableDebts !== false,
    enableInstallments: o.enableInstallments !== false,
  };
}

function meetsMin(value: number, min: number): boolean {
  return value >= min;
}

function countLabel(n: number, one: string, many: string): string {
  return n === 1 ? one : many;
}

function tenantIdOf(row: Record<string, unknown>): number {
  const v = row.tenantId ?? row.tenant_id;
  if (typeof v === 'number') return v;
  return parseInt(String(v ?? '0'), 10) || 0;
}

function isActiveRow(row: Record<string, unknown>): boolean {
  const deleted = row.deleted_at ?? row.deletedAt;
  if (deleted == null) return true;
  const s = String(deleted).trim();
  return s === '' || s === 'null';
}

function todayYmd(): string {
  return new Date().toISOString().slice(0, 10);
}

function dateYmd(raw: unknown): string {
  if (raw == null) return '';
  return String(raw).trim().slice(0, 10);
}

function isOilOrder(row: Record<string, unknown>): boolean {
  const kind = String(row.orderKind ?? row.order_kind ?? '').trim();
  if (kind === OIL_CHANGE_KIND) return true;
  if (kind && kind !== REPAIR_KIND) return false;
  const oilType = String(row.oilType ?? row.oil_type ?? '').trim();
  const odometer = String(row.odometerCurrent ?? row.odometer_current ?? '').trim();
  return oilType !== '' || odometer !== '';
}

function countLowStockProducts(
  tables: SnapshotTables,
  tenantId: number,
  filter?: (row: Record<string, unknown>) => boolean,
): number {
  const products = tables.products ?? [];
  let n = 0;
  for (const p of products) {
    if (tenantIdOf(p) !== tenantId) continue;
    if (Number(p.isActive ?? 1) !== 1) continue;
    if (Number(p.trackInventory ?? 1) !== 1) continue;
    if (filter && !filter(p)) continue;

    const qty = Number(p.qty ?? 0);
    const threshold = Number(p.lowStockThreshold ?? 0);
    const kind = Number(p.stockBaseKind ?? p.stock_base_kind ?? 0);

    const low = qty <= 0 ||
      (threshold > 0 && qty <= threshold) ||
      (kind === VOLUME_LITER_KIND && threshold <= 0 && qty > 0 && qty < 1);

    if (low) n++;
  }
  return n;
}

function countOilGarage(
  tables: SnapshotTables,
  tenantId: number,
  staleHours: number,
): { active: number; stale: number } {
  const orders = tables.service_orders ?? [];
  const cutoff = Date.now() - staleHours * 3600 * 1000;
  let active = 0;
  let stale = 0;

  for (const o of orders) {
    if (tenantIdOf(o) !== tenantId || !isActiveRow(o)) continue;
    if (!isOilOrder(o)) continue;
    const status = String(o.status ?? '').trim();
    if (status !== 'pending' && status !== 'in_progress') continue;

    active++;
    const created = Date.parse(String(o.createdAt ?? o.created_at ?? ''));
    if (Number.isFinite(created) && created <= cutoff) stale++;
  }
  return { active, stale };
}

function countClothingVariantShortages(
  tables: SnapshotTables,
  tenantId: number,
): number {
  const variants = tables.product_variants ?? [];
  const products = new Map<number, Record<string, unknown>>();
  for (const p of tables.products ?? []) {
    if (tenantIdOf(p) === tenantId) products.set(Number(p.id), p);
  }
  const colors = new Set<number>();
  for (const c of tables.product_colors ?? []) {
    if (tenantIdOf(c) === tenantId && isActiveRow(c)) {
      colors.add(Number(c.id));
    }
  }

  let n = 0;
  for (const v of variants) {
    if (tenantIdOf(v) !== tenantId || !isActiveRow(v)) continue;
    const product = products.get(Number(v.productId ?? v.product_id));
    if (!product || Number(product.isActive ?? 1) !== 1) continue;
    if (Number(product.trackInventory ?? 1) !== 1) continue;
    if (Number(product.variantKind ?? product.variant_kind ?? 0) !== CLOTHING_VARIANT_KIND) {
      continue;
    }
    if (!colors.has(Number(v.colorId ?? v.color_id))) continue;

    const qty = Number(v.quantity ?? v.qty ?? 0);
    const threshold = Number(product.lowStockThreshold ?? 0);
    if (qty <= 0 || (threshold > 0 && qty <= threshold)) n++;
  }
  return n;
}

function countClothingSlowMovers(
  tables: SnapshotTables,
  tenantId: number,
  daysThreshold: number,
): number {
  const variants = tables.product_variants ?? [];
  if (!variants.length) return 0;

  const lastSaleByVariant = new Map<number, string>();
  for (const ii of tables.invoice_items ?? []) {
    if (!isActiveRow(ii)) continue;
    const variantId = Number(ii.productVariantId ?? ii.product_variant_id ?? 0);
    if (!variantId) continue;
    const invId = Number(ii.invoiceId ?? ii.invoice_id ?? 0);
    const inv = (tables.invoices ?? []).find(
      (i) => Number(i.id) === invId && tenantIdOf(i) === tenantId && isActiveRow(i),
    );
    if (!inv || Number(inv.isReturned ?? inv.is_returned ?? 0) === 1) continue;
    const d = dateYmd(inv.date);
    const prev = lastSaleByVariant.get(variantId);
    if (!prev || d > prev) lastSaleByVariant.set(variantId, d);
  }

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - daysThreshold);
  const cutoffYmd = cutoff.toISOString().slice(0, 10);

  let n = 0;
  for (const v of variants) {
    if (tenantIdOf(v) !== tenantId || !isActiveRow(v)) continue;
    const qty = Number(v.quantity ?? v.qty ?? 0);
    if (qty <= 0) continue;
    const variantId = Number(v.id);
    const last = lastSaleByVariant.get(variantId);
    if (!last || last < cutoffYmd) n++;
  }
  return n;
}

function countInstallments(
  tables: SnapshotTables,
  tenantId: number,
): { overdue: number; dueToday: number } {
  const today = todayYmd();
  let overdue = 0;
  let dueToday = 0;

  for (const i of tables.installments ?? []) {
    if (Number(i.paid ?? 0) === 1) continue;
    const planId = Number(i.planId ?? i.plan_id ?? 0);
    const plan = (tables.installment_plans ?? []).find(
      (p) => Number(p.id) === planId,
    );
    if (!plan) continue;

    const invId = Number(plan.invoiceId ?? plan.invoice_id ?? 0);
    const inv = invId
      ? (tables.invoices ?? []).find((x) => Number(x.id) === invId)
      : null;
    const custId = Number(plan.customerId ?? plan.customer_id ?? 0);
    const cust = custId
      ? (tables.customers ?? []).find((c) => Number(c.id) === custId)
      : null;
    const rowTenant = inv ? tenantIdOf(inv) : cust ? tenantIdOf(cust) : 0;
    if (rowTenant !== tenantId) continue;

    const due = dateYmd(i.dueDate ?? i.due_date);
    if (!due) continue;
    if (due < today) overdue++;
    else if (due === today) dueToday++;
  }
  return { overdue, dueToday };
}

function countDebtCustomers(tables: SnapshotTables, tenantId: number): number {
  let n = 0;
  for (const c of tables.customers ?? []) {
    if (tenantIdOf(c) !== tenantId) continue;
    if (Number(c.balance ?? 0) > 1e-6) n++;
  }
  return n;
}

/** يقيّم التنبيهات من لقطة SQLite — يطابق OwnerActionAlertResolver. */
export function evaluateAlertsFromSnapshot(
  prefs: OwnerAlertPrefs,
  tables: SnapshotTables,
  pushIds: string[],
): PushAlertCandidate[] {
  const t = parseThresholds(prefs.thresholds ?? {});
  const flags = parseFeatureFlags(prefs.feature_flags);
  const tenantId = prefs.local_tenant_id;
  const vertical = String(prefs.vertical ?? 'general_retail');
  const enabled = new Set(pushIds);
  const out: PushAlertCandidate[] = [];

  const push = (candidate: PushAlertCandidate) => {
    if (enabled.has(candidate.alertId)) out.push(candidate);
  };

  const isOil = vertical === 'oil_change';
  const isClothing = vertical === 'clothing_store';
  const isRetail = vertical === 'supermarket' || vertical === 'general_retail';

  if (isOil) {
    const garage = countOilGarage(tables, tenantId, t.garageStaleHours);
    if (meetsMin(garage.stale, t.garageStaleMinCount)) {
      push({
        alertId: 'oil_garage_stale',
        actionKind: 'openOilLog',
        titleAr: 'سيارات متأخرة',
        bodyAr: countLabel(
          garage.stale,
          `سيارة بانتظار منذ ${t.garageStaleHours} ساعة أو أكثر`,
          `${garage.stale} سيارات بانتظار منذ ${t.garageStaleHours} ساعة أو أكثر`,
        ),
        tenantId,
        metricCount: garage.stale,
      });
    } else if (meetsMin(garage.active, t.activeGarageMinCount)) {
      push({
        alertId: 'oil_active_garage',
        actionKind: 'openOilLog',
        titleAr: 'سيارات في الورشة',
        bodyAr: countLabel(
          garage.active,
          'سيارة واحدة قيد العمل',
          `${garage.active} سيارات قيد العمل`,
        ),
        tenantId,
        metricCount: garage.active,
      });
    }

    const oilShort = countLowStockProducts(
      tables,
      tenantId,
      (p) => Number(p.stockBaseKind ?? p.stock_base_kind ?? 0) === VOLUME_LITER_KIND,
    );
    if (meetsMin(oilShort, t.stockShortageMinCount)) {
      push({
        alertId: 'oil_stock_shortage',
        actionKind: 'purchasePdf',
        titleAr: 'نواقص زيوت وفلاتر',
        bodyAr: countLabel(oilShort, 'صنف واحد ناقص', `${oilShort} أصناف ناقصة`),
        tenantId,
        metricCount: oilShort,
      });
    }
  }

  if (isRetail) {
    const retailShort = countLowStockProducts(tables, tenantId);
    if (meetsMin(retailShort, t.stockShortageMinCount)) {
      push({
        alertId: 'retail_stock_shortage',
        actionKind: 'purchasePdf',
        titleAr: 'نواقص الرفوف',
        bodyAr: countLabel(
          retailShort,
          'صنف واحد ناقص على الرف',
          `${retailShort} أصناف ناقصة على الرف`,
        ),
        tenantId,
        metricCount: retailShort,
      });
    }
  }

  if (isClothing) {
    const variantShort = countClothingVariantShortages(tables, tenantId);
    if (meetsMin(variantShort, t.variantShortageMinCount)) {
      push({
        alertId: 'clothing_variant_shortage',
        actionKind: 'purchasePdf',
        titleAr: 'نواقص المقاسات',
        bodyAr: countLabel(
          variantShort,
          'مقاس أو لون واحد نفد',
          `${variantShort} مقاسات/ألوان ناقصة`,
        ),
        tenantId,
        metricCount: variantShort,
      });
    }

    const slow = countClothingSlowMovers(tables, tenantId, t.slowMoversDays);
    if (meetsMin(slow, t.slowMoversMinCount)) {
      push({
        alertId: 'clothing_slow_movers',
        actionKind: 'openInventory',
        titleAr: 'أرصدة راكدة',
        bodyAr: countLabel(
          slow,
          `متغيّر واحد بدون مبيعات منذ ${t.slowMoversDays} يوماً`,
          `${slow} متغيّرات بدون مبيعات منذ ${t.slowMoversDays} يوماً`,
        ),
        tenantId,
        metricCount: slow,
      });
    }
  }

  if (flags.enableInstallments) {
    const inst = countInstallments(tables, tenantId);
    if (meetsMin(inst.overdue, t.installmentOverdueMinCount)) {
      push({
        alertId: 'installment_overdue',
        actionKind: 'openInstallments',
        titleAr: 'أقساط متأخرة',
        bodyAr: countLabel(inst.overdue, 'قسط واحد متأخر', `${inst.overdue} أقساط متأخرة`),
        tenantId,
        metricCount: inst.overdue,
      });
    }
    if (meetsMin(inst.dueToday, t.installmentDueTodayMinCount)) {
      push({
        alertId: 'installment_due_today',
        actionKind: 'openInstallments',
        titleAr: 'أقساط اليوم',
        bodyAr: countLabel(
          inst.dueToday,
          'قسط واحد مستحق اليوم',
          `${inst.dueToday} أقساط مستحقة اليوم`,
        ),
        tenantId,
        metricCount: inst.dueToday,
      });
    }
  }

  if (flags.enableDebts) {
    const debtors = countDebtCustomers(tables, tenantId);
    if (meetsMin(debtors, t.debtorsMinCount)) {
      push({
        alertId: 'debt_customers',
        actionKind: 'debtReminders',
        titleAr: 'ديون العملاء',
        bodyAr: countLabel(debtors, 'عميل واحد مدين', `${debtors} عملاء مدينون`),
        tenantId,
        metricCount: debtors,
      });
    }
  }

  return out;
}
