import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "إعدادات المنصة — NABOO",
};

export default function SettingsLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
