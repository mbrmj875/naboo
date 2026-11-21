"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { FIELD_MESSAGES } from "@/lib/field-messages";
import { countPendingOps } from "@/lib/field-offline";
import { fieldNetwork } from "@/lib/field-network";
import { startFieldSyncEngine } from "@/lib/field-sync";
import { maybeDailyCleanup } from "@/lib/field-cleanup";

function NavIcon({ name }: { name: "home" | "list" | "user" }) {
  if (name === "home") {
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
        <path
          d="M12 3.5 4.5 10v10.5h5.2V14h4.6v6.5h5.2V10L12 3.5Z"
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinejoin="round"
        />
      </svg>
    );
  }
  if (name === "list") {
    return (
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
        <path
          d="M8 7h12M8 12h12M8 17h12M4 7h.01M4 12h.01M4 17h.01"
          stroke="currentColor"
          strokeWidth="1.8"
          strokeLinecap="round"
        />
      </svg>
    );
  }
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden>
      <circle cx="12" cy="8" r="3.2" stroke="currentColor" strokeWidth="1.8" />
      <path
        d="M5 19.2c1.6-3 4-4.5 7-4.5s5.4 1.5 7 4.5"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </svg>
  );
}

export function FieldShell({
  title,
  children,
  mapMode = false,
}: {
  title: string;
  children: React.ReactNode;
  mapMode?: boolean;
}) {
  const pathname = usePathname() || "/field";
  const [pending, setPending] = useState(0);
  const [online, setOnline] = useState(true);

  useEffect(() => {
    void maybeDailyCleanup();
    const refresh = () => void countPendingOps().then(setPending);
    refresh();
    const stop = startFieldSyncEngine({
      onAuthInvalidated: () => {
        window.location.href = "/field/login?reason=session";
      },
    });
    const unsub = fieldNetwork.onChange((ok) => {
      setOnline(ok);
      refresh();
    });
    const t = setInterval(refresh, 5000);
    return () => {
      stop();
      unsub();
      clearInterval(t);
    };
  }, []);

  const chipClass = !online
    ? "offline"
    : pending > 0
      ? "pending"
      : "synced";
  const chipText = !online
    ? "بدون شبكة"
    : pending > 0
      ? `${pending} بانتظار الرفع`
      : FIELD_MESSAGES.SYNC_SYNCED;

  return (
    <>
      <header className="field-topbar">
        <h1>{title}</h1>
        <span className={`field-sync-chip ${chipClass}`}>{chipText}</span>
      </header>
      <main className={`field-main ${mapMode ? "map-mode" : ""}`}>{children}</main>
      <nav className="field-nav" aria-label="تنقل المندوب">
        <Link
          href="/field"
          className={pathname === "/field" ? "active" : ""}
        >
          <NavIcon name="home" />
          <span>جديد</span>
        </Link>
        <Link
          href="/field/visits"
          className={pathname.startsWith("/field/visits") ? "active" : ""}
        >
          <NavIcon name="list" />
          <span>زياراتي</span>
        </Link>
        <Link
          href="/field/account"
          className={pathname.startsWith("/field/account") ? "active" : ""}
        >
          <NavIcon name="user" />
          <span>حسابي</span>
        </Link>
      </nav>
    </>
  );
}
