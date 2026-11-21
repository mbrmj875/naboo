import type { DeviceRow, LicenseRow, UserRow } from "./dashboard-data";
import {
  accountStatusLabelAr,
  formatRemainingDaysAr,
  getAccountStatus,
  isTrialExpiring,
  pickLicenseForUser,
  type AccountListFilter,
  type AccountStatus,
} from "./account-status";
import { formatDateTimeLatn, formatNumberLatn } from "./format-ar";
import { whatsappMeUrl } from "./ops-phone";

/** أيام بلا دخول تُعد خمولاً يحتاج متابعة. */
export const INACTIVE_LOGIN_DAYS = 7;

export type OpsCrmMeta = {
  account_user_id: string;
  contact_id: string | null;
  owner: string | null;
  tags: string[];
  next_follow_up_at: string | null;
  updated_at: string | null;
  updated_by: string | null;
};

export type OpsCrmNote = {
  id: string;
  account_user_id: string | null;
  contact_id: string | null;
  body: string;
  created_by: string | null;
  created_at: string;
};

export type OpsCrmTask = {
  id: string;
  account_user_id: string | null;
  contact_id: string | null;
  title: string;
  due_at: string | null;
  done_at: string | null;
  assignee: string | null;
  kind: string;
  created_by: string | null;
  created_at: string;
};

export type OpsTimelineItem = {
  id: string;
  at: string;
  title: string;
  detail?: string;
  kind: "system" | "note" | "task" | "message";
};

export type AccountStatusCounts = Record<AccountStatus, number> & {
  trial_expiring: number;
  inactive: number;
  no_devices: number;
};

export function emptyStatusCounts(): AccountStatusCounts {
  return {
    active: 0,
    trial: 0,
    expiring: 0,
    expired: 0,
    disabled: 0,
    no_subscription: 0,
    trial_expiring: 0,
    inactive: 0,
    no_devices: 0,
  };
}

export function daysSinceLastSignIn(user: UserRow, nowMs = Date.now()): number | null {
  if (!user.last_sign_in_at) return null;
  const t = new Date(user.last_sign_in_at).getTime();
  if (!Number.isFinite(t)) return null;
  return Math.floor((nowMs - t) / 86400000);
}

/** نشط أو تجريبي ولم يدخل منذ INACTIVE_LOGIN_DAYS (أو بلا آخر دخول مع أجهزة). */
export function isInactiveLogin(
  user: UserRow,
  license: LicenseRow | null,
  nowMs = Date.now(),
): boolean {
  const status = getAccountStatus(user, license);
  if (status !== "active" && status !== "trial" && status !== "expiring") {
    return false;
  }
  if (!user.last_sign_in_at) {
    return user.linked_devices_count > 0 || Boolean(user.created_at);
  }
  const days = daysSinceLastSignIn(user, nowMs);
  return days != null && days >= INACTIVE_LOGIN_DAYS;
}

export function countAccountStatuses(
  users: UserRow[],
  licenses: LicenseRow[],
): AccountStatusCounts {
  const counts = emptyStatusCounts();
  for (const user of users) {
    const license = pickLicenseForUser(user.id, licenses);
    const status = getAccountStatus(user, license);
    counts[status] += 1;
    if (isTrialExpiring(user, license)) counts.trial_expiring += 1;
    if (isInactiveLogin(user, license)) counts.inactive += 1;
    if (user.linked_devices_count <= 0) counts.no_devices += 1;
  }
  return counts;
}

export type AttentionTone = "red" | "orange" | "yellow" | "neutral";

export function attentionToneForReason(reason: string): AttentionTone {
  if (reason.includes("ينتهي خلال") || reason.includes("التجربة تنتهي")) {
    const m = reason.match(/خلال\s+(\d+)/);
    const n = m ? Number(m[1]) : 99;
    if (n <= 3) return "red";
    return "orange";
  }
  if (reason.includes("لم يدخل") || reason.includes("خمول")) return "orange";
  if (reason.includes("بلا أجهزة") || reason.includes("بلا ترخيص")) return "yellow";
  if (reason.includes("معطّل")) return "red";
  return "neutral";
}

/** يوسّع سبب الانتباه ليشمل الخمول وبلا أجهزة. */
export function getOpsAttentionReason(
  user: UserRow,
  license: LicenseRow | null,
): string | null {
  const status = getAccountStatus(user, license);
  if (status === "disabled") return "معطّل";

  if (isTrialExpiring(user, license)) {
    const left =
      user.trial_days_left != null && user.trial_days_left > 0
        ? user.trial_days_left
        : 0;
    return `التجربة تنتهي خلال ${formatNumberLatn(left)} ${daysWordAr(left)}`;
  }

  if (status === "expiring") {
    const left = license?.expires_days_left ?? 0;
    const n = Math.max(0, Math.floor(left));
    return `الاشتراك ينتهي خلال ${formatNumberLatn(n)} ${daysWordAr(n)}`;
  }

  if (isInactiveLogin(user, license)) {
    const days = daysSinceLastSignIn(user);
    if (days == null) return "خمول: بلا آخر دخول مسجّل";
    return `لم يدخل منذ ${formatNumberLatn(days)} ${daysWordAr(days)}`;
  }

  if (
    (status === "active" || status === "trial") &&
    user.linked_devices_count <= 0
  ) {
    return "بلا أجهزة مسجّلة";
  }

  if (status === "no_subscription") return "بلا ترخيص نشط";

  return null;
}

export function opsAttentionUrgencyScore(
  user: UserRow,
  license: LicenseRow | null,
): number | null {
  const reason = getOpsAttentionReason(user, license);
  if (!reason) return null;
  const status = getAccountStatus(user, license);
  if (isTrialExpiring(user, license)) {
    return user.trial_days_left ?? 0;
  }
  if (status === "expiring") {
    return 100 + Math.max(0, license?.expires_days_left ?? 0);
  }
  if (isInactiveLogin(user, license)) {
    const days = daysSinceLastSignIn(user) ?? INACTIVE_LOGIN_DAYS;
    return 300 + days;
  }
  if (
    (status === "active" || status === "trial") &&
    user.linked_devices_count <= 0
  ) {
    return 400;
  }
  if (status === "disabled") return 1000;
  if (status === "no_subscription") return 2000;
  return 3000;
}

function daysWordAr(n: number): string {
  if (n === 1) return "يوم";
  if (n === 2) return "يومان";
  if (n >= 3 && n <= 10) return "أيام";
  return "يوماً";
}

export type ExtendedAccountFilter = AccountListFilter | "inactive" | "needs_followup";

const EXTENDED_FILTER_SET = new Set<string>([
  "all",
  "active",
  "trial",
  "trial_expiring",
  "expiring",
  "expired",
  "disabled",
  "no_subscription",
  "no_devices",
  "inactive",
  "needs_followup",
]);

export function parseExtendedAccountFilter(
  raw: string | null | undefined,
): ExtendedAccountFilter {
  const v = (raw ?? "").trim().toLowerCase();
  if (!v || !EXTENDED_FILTER_SET.has(v)) return "all";
  return v as ExtendedAccountFilter;
}

export function matchesExtendedAccountFilter(
  user: UserRow,
  license: LicenseRow | null,
  filter: ExtendedAccountFilter,
  opts?: { openTaskDue?: boolean },
): boolean {
  if (filter === "all") return true;
  if (filter === "inactive") return isInactiveLogin(user, license);
  if (filter === "needs_followup") {
    if (opts?.openTaskDue) return true;
    return getOpsAttentionReason(user, license) != null;
  }
  if (filter === "no_devices") return user.linked_devices_count <= 0;
  if (filter === "trial_expiring") return isTrialExpiring(user, license);
  return getAccountStatus(user, license) === filter;
}

export function buildSystemTimeline(args: {
  user: UserRow;
  license: LicenseRow | null;
  devices: DeviceRow[];
}): OpsTimelineItem[] {
  const { user, license, devices } = args;
  const items: OpsTimelineItem[] = [];

  items.push({
    id: `sys-created-${user.id}`,
    at: user.created_at,
    title: "إنشاء الحساب",
    detail: user.email ?? undefined,
    kind: "system",
  });

  if (user.trial_started_at) {
    items.push({
      id: `sys-trial-${user.id}`,
      at: user.trial_started_at,
      title: "بدء التجربة",
      detail:
        user.trial_days_left != null && user.trial_days_left > 0
          ? formatRemainingDaysAr(user.trial_days_left)
          : undefined,
      kind: "system",
    });
  }

  if (license?.expires_at || license?.license_key) {
    items.push({
      id: `sys-license-${license.license_key}`,
      at: license.expires_at ?? user.created_at,
      title: "ترخيص مربوط",
      detail: [
        accountStatusLabelAr(getAccountStatus(user, license)),
        license.business_name,
        license.plan,
      ]
        .filter(Boolean)
        .join(" · "),
      kind: "system",
    });
  }

  for (const d of devices.slice(0, 8)) {
    items.push({
      id: `sys-device-${d.id}`,
      at: d.created_at || d.last_seen_at,
      title: "تسجيل جهاز",
      detail: [d.device_name, d.platform].filter(Boolean).join(" · "),
      kind: "system",
    });
  }

  if (user.last_sign_in_at) {
    items.push({
      id: `sys-signin-${user.id}`,
      at: user.last_sign_in_at,
      title: "آخر دخول للتطبيق",
      detail: formatDateTimeLatn(user.last_sign_in_at),
      kind: "system",
    });
  }

  if (user.banned_until) {
    const banMs = new Date(user.banned_until).getTime();
    if (Number.isFinite(banMs) && banMs > Date.now()) {
      items.push({
        id: `sys-ban-${user.id}`,
        at: user.banned_until,
        title: "الحساب معطّل",
        detail: `حتى ${formatDateTimeLatn(user.banned_until)}`,
        kind: "system",
      });
    }
  }

  items.sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime());
  return items;
}

export function mergeTimeline(
  system: OpsTimelineItem[],
  notes: OpsCrmNote[],
  tasks: OpsCrmTask[],
  messageItems: OpsTimelineItem[] = [],
): OpsTimelineItem[] {
  const fromNotes: OpsTimelineItem[] = notes.map((n) => ({
    id: `note-${n.id}`,
    at: n.created_at,
    title: "ملاحظة فريق",
    detail: n.body,
    kind: "note",
  }));
  const fromTasks: OpsTimelineItem[] = tasks.map((t) => ({
    id: `task-${t.id}`,
    at: t.done_at ?? t.due_at ?? t.created_at,
    title: t.done_at ? `مهمة مكتملة: ${t.title}` : `مهمة: ${t.title}`,
    detail: [t.assignee, t.due_at ? `استحقاق ${formatDateTimeLatn(t.due_at)}` : null]
      .filter(Boolean)
      .join(" · "),
    kind: "task",
  }));
  const all = [...system, ...fromNotes, ...fromTasks, ...messageItems];
  all.sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime());
  return all;
}

export function accountWhatsAppHref(user: UserRow): string | null {
  return whatsappMeUrl(user.phone);
}

export function displayBusinessName(
  user: UserRow,
  license: LicenseRow | null,
): string {
  const fromLic = license?.business_name?.trim();
  if (fromLic) return fromLic;
  const fromUser = user.display_name?.trim();
  if (fromUser) return fromUser;
  if (user.email) return user.email.split("@")[0] ?? user.email;
  return "بدون اسم";
}
