"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const TABS = [
  { href: "/market/stores", label: "المحلات" },
  { href: "/market/products", label: "المنتجات" },
  { href: "/market/orders", label: "الطلبات" },
] as const;

export function MarketSubnav() {
  const pathname = usePathname() || "";
  return (
    <nav className="market-subnav" aria-label="أقسام السوق">
      {TABS.map((t) => (
        <Link
          key={t.href}
          href={t.href}
          className={
            pathname === t.href || pathname.startsWith(`${t.href}/`)
              ? "market-subnav-link active"
              : "market-subnav-link"
          }
        >
          {t.label}
        </Link>
      ))}
    </nav>
  );
}
