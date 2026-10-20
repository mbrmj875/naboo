"use client";

import { useEffect, useMemo } from "react";
import Link from "next/link";
import {
  pickLicenseForUser,
} from "@/lib/account-status";
import type { LicenseRow, UserRow } from "@/lib/dashboard-data";
import { formatNumberLatn } from "@/lib/format-ar";
import {
  attentionToneForReason,
  countAccountStatuses,
  displayBusinessName,
  getOpsAttentionReason,
  matchesExtendedAccountFilter,
  opsAttentionUrgencyScore,
  type ExtendedAccountFilter,
} from "@/lib/ops-crm";
import { WaPendingOrdersHome } from "@/components/wa-pending-orders-home";

const OPS_CARDS: {
  filter: ExtendedAccountFilter;
  title: string;
  href: string;
}[] = [
  {
    filter: "trial_expiring",
    title: "تجارب تنتهي قريباً",
    href: "/accounts?filter=trial_expiring",
  },
  {
    filter: "expiring",
    title: "اشتراكات تنتهي خلال 7 أيام",
    href: "/accounts?filter=expiring",
  },
  {
    filter: "inactive",
    title: "خمول دخول (7+ أيام)",
    href: "/accounts?filter=inactive",
  },
  {
    filter: "no_subscription",
    title: "حسابات بلا ترخيص نشط",
    href: "/accounts?filter=no_subscription",
  },
  {
    filter: "disabled",
    title: "حسابات موقوفة",
    href: "/accounts?filter=disabled",
  },
];

type Props = {
  users: UserRow[];
  licenses: LicenseRow[];
};

export function OpsHomePanel({ users, licenses }: Props) {
  const statusCounts = useMemo(
    () => countAccountStatuses(users, licenses),
    [users, licenses],
  );

  const counts = useMemo(() => {
    const map: Record<string, number> = {};
    for (const card of OPS_CARDS) {
      map[card.filter] = users.filter((u) =>
        matchesExtendedAccountFilter(
          u,
          pickLicenseForUser(u.id, licenses),
          card.filter,
        ),
      ).length;
    }
    return map;
  }, [users, licenses]);

  const attentionRows = useMemo(() => {
    const rows: {
      user: UserRow;
      reason: string;
      score: number;
      tone: ReturnType<typeof attentionToneForReason>;
      business: string;
    }[] = [];
    for (const user of users) {
      const license = pickLicenseForUser(user.id, licenses);
      const reason = getOpsAttentionReason(user, license);
      if (!reason) continue;
      const score = opsAttentionUrgencyScore(user, license);
      if (score == null) continue;
      rows.push({
        user,
        reason,
        score,
        tone: attentionToneForReason(reason),
        business: displayBusinessName(user, license),
      });
    }
    rows.sort((a, b) => a.score - b.score);
    return rows.slice(0, 12);
  }, [users, licenses]);

  useEffect(() => {
    if (users.length === 0) return;
    void fetch("/api/ops/crm/ensure-renewal-tasks", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ users, licenses }),
    }).catch(() => undefined);
  }, [users, licenses]);

  const allZero = OPS_CARDS.every((c) => (counts[c.filter] ?? 0) === 0);

  return (
    <section className="ops-home" aria-label="مركز العمليات">
      <h2 className="ops-home-title">مركز عمليات نابو — CRM الاشتراكات</h2>
      <p className="meta ops-home-sub">
        متابعة الحسابات والتجديد والتفعيل — وما يحتاج قرارك اليوم
      </p>

      <div className="ops-stats" aria-label="إحصائيات الحالات">
        <div className="ops-stat">
          <div className="ops-stat-n">{formatNumberLatn(statusCounts.active)}</div>
          <div className="ops-stat-t">نشط</div>
        </div>
        <div className="ops-stat">
          <div className="ops-stat-n">{formatNumberLatn(statusCounts.trial)}</div>
          <div className="ops-stat-t">تجربة</div>
        </div>
        <div className="ops-stat">
          <div className="ops-stat-n">
            {formatNumberLatn(statusCounts.expiring)}
          </div>
          <div className="ops-stat-t">ينتهي قريباً</div>
        </div>
        <div className="ops-stat">
          <div className="ops-stat-n">{formatNumberLatn(statusCounts.expired)}</div>
          <div className="ops-stat-t">منتهٍ</div>
        </div>
        <div className="ops-stat">
          <div className="ops-stat-n">
            {formatNumberLatn(statusCounts.disabled)}
          </div>
          <div className="ops-stat-t">معطّل</div>
        </div>
        <div className="ops-stat">
          <div className="ops-stat-n">
            {formatNumberLatn(statusCounts.no_subscription)}
          </div>
          <div className="ops-stat-t">بلا اشتراك</div>
        </div>
      </div>

      <div className="ops-cards">
        {OPS_CARDS.map((card) => {
          const n = counts[card.filter] ?? 0;
          const empty = n === 0;
          return (
            <Link
              key={card.filter}
              href={card.href}
              className={empty ? "ops-card ops-card--empty" : "ops-card"}
            >
              <div className="ops-card-n">
                {empty ? "—" : formatNumberLatn(n)}
              </div>
              <div className="ops-card-t">{card.title}</div>
              <div className="ops-card-hint">
                {empty ? "لا شيء" : "عرض القائمة"}
              </div>
            </Link>
          );
        })}
      </div>

      <div className="ops-home-links">
        <Link className="btn-sm" href="/accounts?filter=needs_followup">
          يحتاج متابعة
        </Link>
        <Link className="btn-sm" href="/inbox">
          صندوق الوارد
        </Link>
        <Link className="btn-sm" href="/channels">
          القنوات
        </Link>
      </div>

      <WaPendingOrdersHome />

      {allZero ? (
        <div className="ops-all-clear" role="status">
          لا شيء يحتاج قرارك اليوم
        </div>
      ) : null}

      <div className="ops-attention">
        <h3 className="ops-attention-title">الأكثر احتياجاً للمتابعة</h3>
        {attentionRows.length === 0 ? (
          <div className="dash-state muted">لا حسابات عاجلة في الوقت الحالي.</div>
        ) : (
          <ul className="ops-attention-list">
            {attentionRows.map(({ user, reason, tone, business }) => (
              <li
                key={user.id}
                className={`ops-attention-row ops-attention-row--${tone}`}
              >
                <div className="ops-attention-main">
                  <span className="ops-attention-name">{business}</span>
                  <span className="ops-attention-sep">·</span>
                  <span className="ops-attention-email">
                    {user.email ?? user.phone ?? "—"}
                  </span>
                  <span className="ops-attention-sep">·</span>
                  <span className="ops-attention-reason">{reason}</span>
                </div>
                <Link
                  className="btn-sm"
                  href={`/accounts?account=${encodeURIComponent(user.id)}`}
                >
                  فتح
                </Link>
              </li>
            ))}
          </ul>
        )}
      </div>
    </section>
  );
}
