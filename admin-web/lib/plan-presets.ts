/** يطابق lib/models/subscription_pricing.dart + SubscriptionPlan في Flutter */

export const PLAN_KEYS = ["monthly", "annual"] as const;

/** خطط قديمة — للتراخيص السابقة فقط */
export const LEGACY_PLAN_KEYS = ["basic", "pro", "unlimited"] as const;

export type PlanKey = (typeof PLAN_KEYS)[number];
export type LegacyPlanKey = (typeof LEGACY_PLAN_KEYS)[number];
export type AnyPlanKey = PlanKey | LegacyPlanKey;

export const SUBSCRIPTION_PRICE_PER_COMPUTER_IQD = 15000;
export const SUBSCRIPTION_INCLUDED_PHONES = 1;
export const SUBSCRIPTION_MIN_COMPUTERS = 1;
export const SUBSCRIPTION_ANNUAL_PAID_MONTHS = 10;

export function clampComputers(computers: number): number {
  const n = Math.floor(Number(computers));
  if (!Number.isFinite(n)) return SUBSCRIPTION_MIN_COMPUTERS;
  return Math.min(12, Math.max(SUBSCRIPTION_MIN_COMPUTERS, n));
}

export function maxDevicesForComputers(computers: number): number {
  return SUBSCRIPTION_INCLUDED_PHONES + clampComputers(computers);
}

export function monthlyPriceIqd(computers: number): number {
  return SUBSCRIPTION_PRICE_PER_COMPUTER_IQD * clampComputers(computers);
}

export function annualPriceIqd(computers: number): number {
  return monthlyPriceIqd(computers) * SUBSCRIPTION_ANNUAL_PAID_MONTHS;
}

/** افتراضي لوحة الإدارة: هاتف + حاسوب واحد */
export function maxDevicesForPlan(plan: AnyPlanKey): number {
  switch (plan) {
    case "monthly":
    case "annual":
      return maxDevicesForComputers(SUBSCRIPTION_MIN_COMPUTERS);
    case "basic":
      return 2;
    case "pro":
      return 3;
    case "unlimited":
      return 0;
  }
}

export function planLabelAr(plan: AnyPlanKey): string {
  switch (plan) {
    case "monthly":
      return "شهري — 15,000 د.ع/حاسوب (يشمل هاتفاً)";
    case "annual":
      return "سنوي — 10 أشهر = 12 شهراً (150,000 د.ع لحاسوب واحد)";
    case "basic":
      return "قديم: الأساسية — 2 أجهزة";
    case "pro":
      return "قديم: الاحترافية — 3 أجهزة";
    case "unlimited":
      return "قديم: غير المحدودة";
  }
}

export function isKnownPlanKey(plan: string): plan is AnyPlanKey {
  return (
    (PLAN_KEYS as readonly string[]).includes(plan) ||
    (LEGACY_PLAN_KEYS as readonly string[]).includes(plan)
  );
}
