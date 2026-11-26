/** Run: deno test supabase/functions/notify-daily-summary/summary_test.ts */
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { computeDailySummary, summaryText } from './summary.ts';

// 19:00 UTC = 22:00 بغداد يوم 2026-11-25
const NOW = new Date('2026-11-25T19:00:00Z');

const tables = {
  invoices: [
    { id: 1, date: '2026-11-25T10:00:00', type: 0, totalFils: 100000000, isReturned: 0 },
    { id: 2, date: '2026-11-25T11:00:00', type: 1, totalFils: 50000000, advancePaymentFils: 10000000, isReturned: 0 },
    { id: 3, date: '2026-11-25T12:00:00', type: 2, total: 30000, isReturned: 0 },
    { id: 4, date: '2026-11-25T13:00:00', type: 0, totalFils: 5000000, isReturned: 1, originalInvoiceId: 1 },
    { id: 5, date: '2026-11-25T14:00:00', type: 4, totalFils: 999000000, isReturned: 0 },
    { id: 6, date: '2026-11-24T14:00:00', type: 0, totalFils: 120000000, isReturned: 0 },
    { id: 7, date: '2026-11-25T15:00:00', type: 0, totalFils: 1000, isReturned: 0, deleted_at: '2026-11-25' },
    { id: 8, date: '2026-11-25T15:00:00', type: 0, totalFils: 7000000, tenantId: 2 },
  ],
  invoice_items: [
    { invoiceId: 1, totalFils: 100000000, unitCostFils: 30000000, quantity: 2 },
    { invoiceId: 2, totalFils: 50000000, unitCostFils: 40000000, quantity: 1 },
    { invoiceId: 6, totalFils: 120000000, unitCostFils: 1, quantity: 1 },
  ],
  installment_plans: [{ id: 1, invoiceId: 3 }],
  installments: [
    { planId: 1, dueDate: '2026-11-26', paid: 0 },
    { planId: 1, dueDate: '2026-11-26', paid: 1 },
    { planId: 1, dueDate: '2026-12-26', paid: 0 },
  ],
  products: [
    { id: 1, qty: 0, trackInventory: 1, isActive: 1 },
    { id: 2, qty: 5, lowStockThreshold: 10, isActive: 1 },
    { id: 3, qty: 50, lowStockThreshold: 10, expiryDate: '2026-11-30', isActive: 1 },
    { id: 4, qty: 50, expiryDate: '2027-01-30', isActive: 1 },
  ],
};

Deno.test('daily summary numbers', () => {
  const s = computeDailySummary(tables, 1, NOW);
  assertEquals(s.ymd, '2026-11-25');
  assertEquals(s.invoiceCount, 3);
  assertEquals(s.salesFils, 180000000);
  assertEquals(s.yesterdaySalesFils, 120000000);
  assertEquals(s.debtFils, 40000000 + 30000000);
  assertEquals(s.returnsFils, 5000000);
  assertEquals(s.returnsCount, 1);
  assertEquals(s.profitFils, (100000000 - 60000000) + (50000000 - 40000000));
  assertEquals(s.tomorrow, { installmentsDue: 1, lowStock: 2, expiringSoon: 1 });
  assertEquals(s.hasActivity, true);
});

Deno.test('lock screen text carries sales only, never profit', () => {
  const t = summaryText(computeDailySummary(tables, 1, NOW));
  assertEquals(t.title, 'ملخص اليوم: 180,000 د.ع');
  assertEquals(t.body, '3 فاتورة، أعلى من أمس بـ50%. افتح الإشعار لترى الربح والتفاصيل.');
});

Deno.test('no activity today', () => {
  const s = computeDailySummary({ invoices: [{ id: 6, date: '2026-11-24', type: 0, totalFils: 1 }] }, 1, NOW);
  assertEquals(s.hasActivity, false);
});
