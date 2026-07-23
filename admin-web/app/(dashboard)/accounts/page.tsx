"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { AccountDrawer } from "@/components/account-drawer";
import { AccountStatusBadge } from "@/components/account-status-badge";
import {
  formatSubscriptionColumn,
  getAccountStatus,
  matchesAccountListFilter,
  parseAccountListFilter,
  pickLicenseForUser,
  type AccountListFilter,
} from "@/lib/account-status";
import type { LicenseRow, UserRow } from "@/lib/dashboard-data";
import { formatDateTimeLatn, formatNumberLatn } from "@/lib/format-ar";
import { useDashboardData } from "@/lib/use-dashboard-data";

const FILTER_CHIPS: { id: AccountListFilter; label: string }[] = [
  { id: "all", label: "الكل" },
  { id: "trial", label: "تجريبي" },
  { id: "trial_expiring", label: "تجربة تنتهي قريباً" },
  { id: "active", label: "نشط" },
  { id: "expiring", label: "ينتهي قريباً" },
  { id: "expired", label: "منتهٍ" },
  { id: "disabled", label: "معطّل" },
  { id: "no_subscription", label: "بلا اشتراك" },
  { id: "no_devices", label: "بلا أجهزة" },
];

const PAGE_SIZE = 50;
const PAGINATE_THRESHOLD = 100;

function normalizePhone(value: string): string {
  return value.replace(/\s+/g, "");
}

function matchesSearch(
  user: UserRow,
  license: LicenseRow | null,
  rawQuery: string,
): boolean {
  const q = rawQuery.trim().toLowerCase();
  if (!q) return true;

  const phoneNorm = normalizePhone((user.phone ?? "").toLowerCase());
  const qPhone = normalizePhone(q);

  const hay = [
    user.email ?? "",
    user.display_name ?? "",
    user.phone ?? "",
    license?.license_key ?? "",
  ]
    .join(" ")
    .toLowerCase();

  if (hay.includes(q)) return true;
  if (qPhone && phoneNorm.includes(qPhone)) return true;
  return false;
}

function sortByLastLoginDesc(a: UserRow, b: UserRow): number {
  const ta = a.last_sign_in_at ? new Date(a.last_sign_in_at).getTime() : 0;
  const tb = b.last_sign_in_at ? new Date(b.last_sign_in_at).getTime() : 0;
  return tb - ta;
}

function resultCountLabel(n: number): string {
  if (n === 0) return "0 حساب";
  if (n === 1) return "حساب واحد";
  if (n === 2) return "حسابان";
  const num = formatNumberLatn(n);
  if (n >= 3 && n <= 10) return `${num} حسابات`;
  return `${num} حساباً`;
}

function AccountsPageInner() {
  const { data, loadErr, loading, reload } = useDashboardData();
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const accountId = searchParams.get("account");
  const filter = parseAccountListFilter(searchParams.get("filter"));

  const [searchInput, setSearchInput] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [page, setPage] = useState(1);

  useEffect(() => {
    const t = window.setTimeout(() => {
      setDebouncedSearch(searchInput);
    }, 300);
    return () => window.clearTimeout(t);
  }, [searchInput]);

  useEffect(() => {
    setPage(1);
  }, [debouncedSearch, filter]);

  const licenses = data?.licenses ?? [];
  const users = data?.users ?? [];
  const devices = data?.devices ?? [];
  const snapshots = data?.snapshots ?? [];
  const chunks = data?.snapshotChunks ?? [];

  const setFilter = useCallback(
    (next: AccountListFilter) => {
      const params = new URLSearchParams(searchParams.toString());
      if (next === "all") params.delete("filter");
      else params.set("filter", next);
      const q = params.toString();
      router.push(q ? `${pathname}?${q}` : pathname, { scroll: false });
    },
    [pathname, router, searchParams],
  );

  const openAccount = useCallback(
    (id: string) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set("account", id);
      router.push(`${pathname}?${params.toString()}`, { scroll: false });
    },
    [pathname, router, searchParams],
  );

  const closeAccount = useCallback(() => {
    const params = new URLSearchParams(searchParams.toString());
    params.delete("account");
    const q = params.toString();
    router.push(q ? `${pathname}?${q}` : pathname, { scroll: false });
  }, [pathname, router, searchParams]);

  const filtered = useMemo(() => {
    const list = [...users].sort(sortByLastLoginDesc);
    return list.filter((user) => {
      const license = pickLicenseForUser(user.id, licenses);
      if (!matchesAccountListFilter(user, license, filter)) return false;
      return matchesSearch(user, license, debouncedSearch);
    });
  }, [users, licenses, filter, debouncedSearch]);

  const usePagination = filtered.length > PAGINATE_THRESHOLD;
  const totalPages = usePagination
    ? Math.max(1, Math.ceil(filtered.length / PAGE_SIZE))
    : 1;
  const safePage = Math.min(page, totalPages);
  const pageRows = usePagination
    ? filtered.slice((safePage - 1) * PAGE_SIZE, safePage * PAGE_SIZE)
    : filtered;

  const selectedUser = useMemo(() => {
    if (!accountId) return null;
    return users.find((u) => u.id === accountId) ?? null;
  }, [accountId, users]);

  const selectedLicense = selectedUser
    ? pickLicenseForUser(selectedUser.id, licenses)
    : null;
  const selectedDevices = selectedUser
    ? devices.filter((d) => d.user_id === selectedUser.id)
    : [];
  const selectedSnapshots = selectedUser
    ? snapshots.filter((s) => s.user_id === selectedUser.id)
    : [];
  const selectedChunks = selectedUser
    ? chunks.filter((c) => c.user_id === selectedUser.id)
    : [];

  const hasUsers = users.length > 0;
  const showTable = !loading && !loadErr && hasUsers;

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>الحسابات</h1>
          <div className="meta">إدارة حسابات منصة NABOO</div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void reload()}>
          تحديث
        </button>
      </header>

      {loading ? (
        <div className="dash-state" role="status">
          جاري التحميل…
        </div>
      ) : null}

      {!loading && loadErr ? (
        <div className="alert" role="alert">
          <div>{loadErr}</div>
          <button type="button" className="btn-ghost" onClick={() => void reload()}>
            إعادة المحاولة
          </button>
        </div>
      ) : null}

      {!loading && !loadErr && !hasUsers ? (
        <div className="dash-state">لا توجد حسابات مسجّلة بعد.</div>
      ) : null}

      {!loading && !loadErr && accountId && !selectedUser && hasUsers ? (
        <div className="alert" role="alert">
          <div>الحساب المطلوب غير موجود ضمن القائمة الحالية.</div>
          <button type="button" className="btn-ghost" onClick={closeAccount}>
            إغلاق الرابط
          </button>
        </div>
      ) : null}

      {showTable ? (
        <>
          <div className="acct-toolbar">
            <input
              type="search"
              className="search-input acct-search"
              placeholder="بحث بالبريد أو الهاتف أو الاسم أو مفتاح الترخيص…"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              aria-label="بحث في الحسابات"
            />
            <div className="acct-result-count" aria-live="polite">
              {resultCountLabel(filtered.length)}
            </div>
          </div>

          <div className="acct-filters" role="toolbar" aria-label="تصفية الحسابات">
            {FILTER_CHIPS.map((chip) => (
              <button
                key={chip.id}
                type="button"
                className={
                  filter === chip.id ? "acct-chip active" : "acct-chip"
                }
                onClick={() => setFilter(chip.id)}
              >
                {chip.label}
              </button>
            ))}
          </div>

          {filtered.length === 0 ? (
            <div className="dash-state muted">لا نتائج تطابق البحث أو التصفية.</div>
          ) : (
            <>
              <div className="acct-table-wrap">
                <table className="acct-table">
                  <thead>
                    <tr>
                      <th scope="col">الحساب</th>
                      <th scope="col">الحالة</th>
                      <th scope="col">الاشتراك</th>
                      <th scope="col" className="acct-col-devices">
                        الأجهزة
                      </th>
                      <th scope="col" className="acct-col-last">
                        آخر دخول
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    {pageRows.map((user) => {
                      const license = pickLicenseForUser(user.id, licenses);
                      const status = getAccountStatus(user, license);
                      const name =
                        user.display_name?.trim() ||
                        user.email?.split("@")[0] ||
                        "بدون اسم";
                      return (
                        <tr
                          key={user.id}
                          className={
                            accountId === user.id
                              ? "acct-row acct-row--open"
                              : "acct-row"
                          }
                          tabIndex={0}
                          onClick={() => openAccount(user.id)}
                          onKeyDown={(e) => {
                            if (e.key === "Enter" || e.key === " ") {
                              e.preventDefault();
                              openAccount(user.id);
                            }
                          }}
                        >
                          <td>
                            <div className="acct-identity">
                              <div className="acct-name">{name}</div>
                              {user.email ? (
                                <div className="acct-sub">{user.email}</div>
                              ) : null}
                              {user.phone ? (
                                <div className="acct-sub acct-phone" dir="ltr">
                                  {user.phone}
                                </div>
                              ) : null}
                            </div>
                          </td>
                          <td>
                            <AccountStatusBadge status={status} />
                          </td>
                          <td className="acct-sub-col">
                            {formatSubscriptionColumn(user, license)}
                          </td>
                          <td className="acct-col-devices">
                            {formatNumberLatn(user.linked_devices_count)}
                          </td>
                          <td className="acct-col-last">
                            {formatDateTimeLatn(user.last_sign_in_at)}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>

              {usePagination ? (
                <div className="acct-pagination">
                  <button
                    type="button"
                    className="btn-ghost"
                    disabled={safePage <= 1}
                    onClick={() => setPage((p) => Math.max(1, p - 1))}
                  >
                    السابق
                  </button>
                  <span className="meta">
                    صفحة {formatNumberLatn(safePage)} من{" "}
                    {formatNumberLatn(totalPages)}
                  </span>
                  <button
                    type="button"
                    className="btn-ghost"
                    disabled={safePage >= totalPages}
                    onClick={() =>
                      setPage((p) => Math.min(totalPages, p + 1))
                    }
                  >
                    التالي
                  </button>
                </div>
              ) : null}
            </>
          )}
        </>
      ) : null}

      {selectedUser ? (
        <AccountDrawer
          user={selectedUser}
          license={selectedLicense}
          devices={selectedDevices}
          snapshots={selectedSnapshots}
          chunks={selectedChunks}
          allUsers={users}
          allLicenses={licenses}
          onClose={closeAccount}
          reload={reload}
          onAccountDeleted={closeAccount}
        />
      ) : null}
    </div>
  );
}

export default function AccountsPage() {
  return (
    <Suspense
      fallback={
        <div className="shell dash-page">
          <div className="dash-state" role="status">
            جاري التحميل…
          </div>
        </div>
      }
    >
      <AccountsPageInner />
    </Suspense>
  );
}
