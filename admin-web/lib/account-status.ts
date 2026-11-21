import type { LicenseRow, UserRow } from "./dashboard-data";
import { formatNumberLatn } from "./format-ar";

/** حالة حساب المنصة — مصدر واحد للجدول والفلاتر والشارات. */
export type AccountStatus =
  | "active"
  | "trial"
  | "expiring"
  | "expired"
  | "disabled"
  | "no_subscription";

/** عتبة انتهاء الاشتراك النشط (أيام) — مصدر واحد للفلاتر والشارات. */
export const EXPIRING_DAYS = 7;

/** عتبة انتهاء التجربة السارية (أيام) — مصدر واحد للفلاتر والشارات. */
export const TRIAL_ENDING_DAYS = 7;

/** فلاتر قائمة الحسابات (قيم `?filter=`). */
export type AccountListFilter =
  | "all"
  | AccountStatus
  | "no_devices"
  | "trial_expiring";

const ACCOUNT_LIST_FILTER_SET = new Set<string>([
  "all",
  "active",
  "trial",
  "trial_expiring",
  "expiring",
  "expired",
  "disabled",
  "no_subscription",
  "no_devices",
]);

export function parseAccountListFilter(
  raw: string | null | undefined,
): AccountListFilter {
  const v = (raw ?? "").trim().toLowerCase();
  if (!v || !ACCOUNT_LIST_FILTER_SET.has(v)) return "all";
  return v as AccountListFilter;
}

export type AccountLicenseInput = Pick<
  LicenseRow,
  "status" | "expires_at" | "expires_days_left" | "plan" | "license_key"
> | null;

function isUserDisabled(user: UserRow, nowMs: number): boolean {
  if (!user.banned_until) return false;
  const t = new Date(user.banned_until).getTime();
  return Number.isFinite(t) && t > nowMs;
}

function isLicenseActive(license: NonNullable<AccountLicenseInput>): boolean {
  return (license.status ?? "").toLowerCase() === "active";
}

function trialDaysRemaining(user: UserRow, nowMs: number): number | null {
  if (user.trial_days_left != null && user.trial_days_left > 0) {
    return user.trial_days_left;
  }
  if (user.trial_ends_at) {
    const end = new Date(user.trial_ends_at).getTime();
    if (!Number.isFinite(end)) return null;
    if (end <= nowMs) return 0;
    return Math.ceil((end - nowMs) / 86400000);
  }
  return null;
}

function hadEndedTrial(user: UserRow, nowMs: number): boolean {
  if (!user.trial_started_at) return false;
  const left = trialDaysRemaining(user, nowMs);
  if (left === 0) return true;
  if (user.trial_ends_at) {
    const end = new Date(user.trial_ends_at).getTime();
    return Number.isFinite(end) && end <= nowMs;
  }
  return user.trial_days_left === 0;
}

/**
 * يحسب حالة الحساب الواحدة.
 * الأولوية: معطّل → ترخيص نشط (منتهٍ / ينتهي قريباً / نشط) → تجربة → منتهٍ → بلا اشتراك.
 * اشتراك ينتهي ≤ EXPIRING_DAYS → `expiring`.
 * تجربة سارية (حتى ضمن TRIAL_ENDING_DAYS) → `trial` — للفصل استخدم فلتر `trial_expiring`.
 */
export function getAccountStatus(
  user: UserRow,
  license: AccountLicenseInput,
): AccountStatus {
  const nowMs = Date.now();

  if (isUserDisabled(user, nowMs)) return "disabled";

  if (license && isLicenseActive(license)) {
    const days = license.expires_days_left;
    if (days != null && days < 0) return "expired";
    if (days != null && days <= EXPIRING_DAYS) return "expiring";
    return "active";
  }

  const trialLeft = trialDaysRemaining(user, nowMs);
  if (trialLeft != null && trialLeft > 0) {
    return "trial";
  }

  if (license?.expires_days_left != null && license.expires_days_left < 0) {
    return "expired";
  }
  if (license?.expires_at) {
    const exp = new Date(license.expires_at).getTime();
    if (Number.isFinite(exp) && exp < nowMs) return "expired";
  }
  if (hadEndedTrial(user, nowMs)) return "expired";

  return "no_subscription";
}

/** تجربة سارية وتنتهي خلال TRIAL_ENDING_DAYS. */
export function isTrialExpiring(
  user: UserRow,
  license: AccountLicenseInput,
): boolean {
  if (getAccountStatus(user, license) !== "trial") return false;
  const left = trialDaysRemaining(user, Date.now());
  return left != null && left > 0 && left <= TRIAL_ENDING_DAYS;
}

export function accountStatusLabelAr(status: AccountStatus): string {
  switch (status) {
    case "active":
      return "نشط";
    case "trial":
      return "تجريبي";
    case "expiring":
      return "ينتهي قريباً";
    case "expired":
      return "منتهٍ";
    case "disabled":
      return "معطّل";
    case "no_subscription":
      return "بلا اشتراك";
  }
}

/** يختار أفضل ترخيص مربوط بالحساب.
 * الأولوية: نشط → مدى الحياة → بلا انتهاء → أكبر max_devices → أبعد انتهاء → أحدث id.
 */
export function pickLicenseForUser(
  userId: string,
  licenses: LicenseRow[],
): LicenseRow | null {
  const linked = licenses.filter((l) => l.assigned_user_id === userId);
  if (linked.length === 0) return null;
  const active = linked.filter((l) => isLicenseActive(l));
  const pool = active.length > 0 ? active : linked;

  const planRank = (p: string | null | undefined): number => {
    const k = (p ?? "").toLowerCase().trim();
    if (k === "lifetime") return 3;
    if (k === "annual") return 2;
    if (k === "monthly") return 1;
    return 0;
  };

  pool.sort((a, b) => {
    const pr = planRank(b.plan) - planRank(a.plan);
    if (pr !== 0) return pr;

    const aOpen = a.expires_at == null || planRank(a.plan) === 3 ? 1 : 0;
    const bOpen = b.expires_at == null || planRank(b.plan) === 3 ? 1 : 0;
    if (bOpen !== aOpen) return bOpen - aOpen;

    const mdA = a.max_devices ?? 0;
    const mdB = b.max_devices ?? 0;
    if (mdB !== mdA) return mdB - mdA;

    const da = a.expires_days_left;
    const db = b.expires_days_left;
    if (da == null && db == null) {
      /* fall through */
    } else if (da == null) return -1;
    else if (db == null) return 1;
    else if (db !== da) return db - da;

    const idA = a.db_id ?? 0;
    const idB = b.db_id ?? 0;
    return idB - idA;
  });
  return pool[0] ?? null;
}

/** صياغة عربية صحيحة لعدد الأيام المتبقية (أرقام غربية). */
export function formatRemainingDaysAr(days: number): string {
  const n = Math.floor(days);
  if (n <= 0) return "منتهٍ";
  if (n === 1) return "متبقي يوم";
  if (n === 2) return "متبقي يومان";
  const num = formatNumberLatn(n);
  if (n >= 3 && n <= 10) return `متبقي ${num} أيام`;
  return `متبقي ${num} يوماً`;
}

/** تسمية خطة قصيرة لعمود الاشتراك. */
export function shortPlanLabelAr(plan: string | null | undefined): string {
  const p = (plan ?? "").toLowerCase().trim();
  if (p === "monthly") return "شهري";
  if (p === "annual") return "سنوي";
  if (p === "lifetime") return "مدى الحياة";
  if (p === "basic") return "أساسية";
  if (p === "pro") return "احترافية";
  if (p === "unlimited") return "غير محدودة";
  if (!p) return "—";
  return p;
}

/**
 * نص عمود الاشتراك: نوع + متبقي، أو «—».
 */
export function formatSubscriptionColumn(
  user: UserRow,
  license: AccountLicenseInput,
): string {
  const nowMs = Date.now();
  if (license && isLicenseActive(license)) {
    const plan = shortPlanLabelAr(license.plan);
    const days = license.expires_days_left;
    if (days == null || (license.plan ?? "").toLowerCase() === "lifetime") {
      return plan === "—" ? "اشتراك" : plan;
    }
    if (days < 0) return `${plan} · منتهٍ`;
    return `${plan} · ${formatRemainingDaysAr(days)}`;
  }

  const trialLeft = trialDaysRemaining(user, nowMs);
  if (trialLeft != null && trialLeft > 0) {
    return `تجريبي · ${formatRemainingDaysAr(trialLeft)}`;
  }

  return "—";
}

/** هل يطابق الحساب فلتر القائمة (بدون بحث نصي). */
export function matchesAccountListFilter(
  user: UserRow,
  license: AccountLicenseInput,
  filter: AccountListFilter,
): boolean {
  if (filter === "all") return true;
  if (filter === "no_devices") return user.linked_devices_count <= 0;
  if (filter === "trial_expiring") return isTrialExpiring(user, license);
  return getAccountStatus(user, license) === filter;
}

/**
 * سبب انتباه تشغيلي بالعربية، أو null إن لا يحتاج قراراً اليوم.
 * يعتمد على getAccountStatus / isTrialExpiring فقط.
 */
export function getAttentionReason(
  user: UserRow,
  license: AccountLicenseInput,
): string | null {
  const status = getAccountStatus(user, license);
  if (status === "disabled") return "معطّل";

  if (isTrialExpiring(user, license)) {
    const left = trialDaysRemaining(user, Date.now()) ?? 0;
    return `التجربة تنتهي خلال ${formatNumberLatn(left)} ${daysWordAr(left)}`;
  }

  if (status === "expiring") {
    const left = license?.expires_days_left ?? 0;
    const n = Math.max(0, Math.floor(left));
    return `الاشتراك ينتهي خلال ${formatNumberLatn(n)} ${daysWordAr(n)}`;
  }

  if (status === "no_subscription") return "بلا ترخيص نشط";

  return null;
}

function daysWordAr(n: number): string {
  if (n === 1) return "يوم";
  if (n === 2) return "يومان";
  if (n >= 3 && n <= 10) return "أيام";
  return "يوماً";
}

/** درجة استعجال أقل = أعلى أولوية في قائمة الانتباه. */
export function attentionUrgencyScore(
  user: UserRow,
  license: AccountLicenseInput,
): number | null {
  const reason = getAttentionReason(user, license);
  if (!reason) return null;
  const status = getAccountStatus(user, license);
  if (isTrialExpiring(user, license)) {
    return trialDaysRemaining(user, Date.now()) ?? 0;
  }
  if (status === "expiring") {
    return 100 + Math.max(0, license?.expires_days_left ?? 0);
  }
  if (status === "disabled") return 1000;
  if (status === "no_subscription") return 2000;
  return 3000;
}
