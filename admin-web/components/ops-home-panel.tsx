"use client";

import { useMemo } from "react";
import Link from "next/link";
import {
  attentionUrgencyScore,
  getAttentionReason,
  matchesAccountListFilter,
  pickLicenseForUser,
  type AccountListFilter,
} from "@/lib/account-status";
import type { LicenseRow, UserRow } from "@/lib/dashboard-data";
import { formatNumberLatn } from "@/lib/format-ar";

const OPS_CARDS: {
  filter: AccountListFilter;
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
  const counts = useMemo(() => {
    const map: Record<string, number> = {};
    for (const card of OPS_CARDS) {
      map[card.filter] = users.filter((u) =>
        matchesAccountListFilter(
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
    }[] = [];
    for (const user of users) {
      const license = pickLicenseForUser(user.id, licenses);
      const reason = getAttentionReason(user, license);
      if (!reason) continue;
      const score = attentionUrgencyScore(user, license);
      if (score == null) continue;
      rows.push({ user, reason, score });
    }
    rows.sort((a, b) => a.score - b.score);
    return rows.slice(0, 10);
  }, [users, licenses]);

  const allZero = OPS_CARDS.every((c) => (counts[c.filter] ?? 0) === 0);

  return (
    <section className="ops-home" aria-label="مركز العمليات">
      <h2 className="ops-home-title">مركز العمليات</h2>
      <p className="meta ops-home-sub">ما يحتاج قرارك اليوم — من حالة الحساب فقط</p>

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

      {allZero ? (
        <div className="ops-all-clear" role="status">
          لا شيء يحتاج قرارك اليوم
        </div>
      ) : null}

      <div className="ops-attention">
        <h3 className="ops-attention-title">حسابات تحتاج انتباهك</h3>
        {attentionRows.length === 0 ? (
          <div className="dash-state muted">لا حسابات عاجلة في الوقت الحالي.</div>
        ) : (
          <ul className="ops-attention-list">
            {attentionRows.map(({ user, reason }) => {
              const name =
                user.display_name?.trim() ||
                user.email?.split("@")[0] ||
                "بدون اسم";
              return (
                <li key={user.id} className="ops-attention-row">
                  <div className="ops-attention-main">
                    <span className="ops-attention-name">{name}</span>
                    <span className="ops-attention-sep">·</span>
                    <span className="ops-attention-email">
                      {user.email ?? "—"}
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
              );
            })}
          </ul>
        )}
      </div>
    </section>
  );
}
