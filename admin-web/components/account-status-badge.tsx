"use client";

import {
  accountStatusLabelAr,
  type AccountStatus,
} from "@/lib/account-status";

export function AccountStatusBadge({ status }: { status: AccountStatus }) {
  return (
    <span className={`acct-badge acct-badge--${status}`}>
      {accountStatusLabelAr(status)}
    </span>
  );
}
