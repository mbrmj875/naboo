/**
 * من يستلم كل تنبيه عمل (جدول الأنواع، خامسا البند 5). المالك والهواتف المعلَّمة
 * تستلم دائما، ويُضاف الموظف الذي يملك مفتاح الصلاحية (المرحلة 5).
 */
const AUDIENCE: Record<string, string> = {
  oil_garage_stale: 'perm:sales.pos',
  oil_active_garage: 'perm:sales.pos',
  oil_stock_shortage: 'perm:inventory.view',
  retail_stock_shortage: 'perm:inventory.view',
  clothing_variant_shortage: 'perm:inventory.view',
  clothing_slow_movers: 'perm:inventory.view',
  installment_overdue: 'perm:installments.plans',
  installment_due_today: 'perm:installments.plans',
  debt_customers: 'perm:debts.panel',
};

export function audienceForAlert(alertId: string): string {
  return AUDIENCE[alertId] ?? 'owner';
}
