/**
 * Unit tests for owner alert evaluation (Deno).
 * Run: deno test supabase/functions/owner-alert-push-cron/evaluate_alerts_test.ts
 */

import {
  assertEquals,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { evaluateAlertsFromSnapshot } from './evaluate_alerts.ts';
import type { OwnerAlertPrefs, SnapshotTables } from './types.ts';

const basePrefs: OwnerAlertPrefs = {
  user_id: '00000000-0000-0000-0000-000000000001',
  local_tenant_id: 1,
  vertical: 'supermarket',
  thresholds: { stockShortageMinCount: 2 },
  push_alert_ids: ['retail_stock_shortage', 'debt_customers'],
};

Deno.test('retail shortage suppressed below threshold', () => {
  const tables: SnapshotTables = {
    products: [
      {
        id: 1,
        tenantId: 1,
        isActive: 1,
        trackInventory: 1,
        qty: 0,
        lowStockThreshold: 5,
        name: 'A',
      },
    ],
  };
  const alerts = evaluateAlertsFromSnapshot(basePrefs, tables, [
    'retail_stock_shortage',
  ]);
  assertEquals(alerts.length, 0);
});

Deno.test('retail shortage fires at threshold', () => {
  const tables: SnapshotTables = {
    products: [
      {
        id: 1,
        tenantId: 1,
        isActive: 1,
        trackInventory: 1,
        qty: 0,
        lowStockThreshold: 5,
        name: 'A',
      },
      {
        id: 2,
        tenantId: 1,
        isActive: 1,
        trackInventory: 1,
        qty: 0,
        lowStockThreshold: 3,
        name: 'B',
      },
    ],
  };
  const alerts = evaluateAlertsFromSnapshot(basePrefs, tables, [
    'retail_stock_shortage',
  ]);
  assertEquals(alerts.length, 1);
  assertEquals(alerts[0].alertId, 'retail_stock_shortage');
  assertEquals(alerts[0].actionKind, 'purchasePdf');
  assertEquals(alerts[0].metricCount, 2);
});

Deno.test('oil stale garage uses hours threshold', () => {
  const staleDate = new Date(Date.now() - 3 * 3600 * 1000).toISOString();
  const prefs: OwnerAlertPrefs = {
    ...basePrefs,
    vertical: 'oil_change',
    thresholds: { garageStaleHours: 2, garageStaleMinCount: 1 },
    push_alert_ids: ['oil_garage_stale'],
  };
  const tables: SnapshotTables = {
    service_orders: [
      {
        id: 1,
        tenantId: 1,
        status: 'in_progress',
        orderKind: 'oil_change',
        createdAt: staleDate,
      },
    ],
  };
  const alerts = evaluateAlertsFromSnapshot(prefs, tables, ['oil_garage_stale']);
  assertEquals(alerts.length, 1);
  assertEquals(alerts[0].alertId, 'oil_garage_stale');
});

Deno.test('installments skipped when feature flag disabled', () => {
  const today = new Date().toISOString().slice(0, 10);
  const prefs: OwnerAlertPrefs = {
    ...basePrefs,
    feature_flags: { enableDebts: true, enableInstallments: false },
    push_alert_ids: ['installment_overdue', 'installment_due_today'],
  };
  const tables: SnapshotTables = {
    installments: [
      { id: 1, planId: 1, paid: 0, dueDate: '2000-01-01' },
      { id: 2, planId: 1, paid: 0, dueDate: today },
    ],
    installment_plans: [{ id: 1, customerId: 1 }],
    customers: [{ id: 1, tenantId: 1, balance: 0 }],
  };
  const alerts = evaluateAlertsFromSnapshot(prefs, tables, prefs.push_alert_ids);
  assertEquals(alerts.length, 0);
});

Deno.test('debt alert skipped when enableDebts false', () => {
  const prefs: OwnerAlertPrefs = {
    ...basePrefs,
    feature_flags: { enableDebts: false, enableInstallments: true },
    push_alert_ids: ['debt_customers'],
  };
  const tables: SnapshotTables = {
    customers: [{ id: 1, tenantId: 1, balance: 50000 }],
  };
  const alerts = evaluateAlertsFromSnapshot(prefs, tables, ['debt_customers']);
  assertEquals(alerts.length, 0);
});
