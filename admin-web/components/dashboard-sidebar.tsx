"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const PRIMARY: { href: string; label: string }[] = [
  { href: "/", label: "الرئيسية" },
  { href: "/accounts", label: "الحسابات" },
  { href: "/licenses", label: "التراخيص" },
  { href: "/market/stores", label: "السوق" },
  { href: "/settings", label: "إعدادات المنصة" },
];

function isActive(pathname: string, href: string): boolean {
  if (href === "/") return pathname === "/";
  if (href === "/market/stores") return pathname.startsWith("/market");
  return pathname === href || pathname.startsWith(`${href}/`);
}

function SupportIcon() {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      aria-hidden="true"
    >
      <path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z" />
    </svg>
  );
}

export function DashboardSidebar() {
  const pathname = usePathname() || "/";
  const supportActive = pathname === "/support" || pathname.startsWith("/support/");

  return (
    <aside className="dash-sidebar" aria-label="التنقل الرئيسي">
      <div className="dash-sidebar-brand">NABOO</div>
      <nav className="dash-sidebar-nav" aria-label="أقسام المنصة">
        {PRIMARY.map((item) => {
          const active = isActive(pathname, item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={["dash-sidebar-link", active ? "active" : ""]
                .filter(Boolean)
                .join(" ")}
            >
              {item.label}
            </Link>
          );
        })}
      </nav>
      <div className="dash-sidebar-footer">
        <div className="dash-sidebar-divider" aria-hidden="true" />
        <Link
          href="/support"
          className={[
            "dash-sidebar-link",
            "muted",
            "dash-sidebar-support",
            supportActive ? "active" : "",
          ]
            .filter(Boolean)
            .join(" ")}
        >
          <SupportIcon />
          <span>أدوات الدعم</span>
        </Link>
      </div>
    </aside>
  );
}
