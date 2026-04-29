/** يطابق app/lib أو lib/services/license_service.dart في تطبيق Flutter */

export const PLAN_KEYS = ["basic", "pro", "unlimited"] as const;

export type PlanKey = (typeof PLAN_KEYS)[number];

export function maxDevicesForPlan(plan: PlanKey): number {
  switch (plan) {
    case "basic":
      return 2;
    case "pro":
      return 3;
    case "unlimited":
      return 0;
  }
}

export function planLabelAr(plan: PlanKey): string {
  switch (plan) {
    case "basic":
      return "الأساسية — 15000 د.ع/شهر تقريباً";
    case "pro":
      return "الاحترافية — 30000 د.ع/شهر تقريباً";
    case "unlimited":
      return "غير المحدود — 50000 د.ع/شهر تقريباً";
  }
}
