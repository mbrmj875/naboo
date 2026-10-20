import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "أدوات الدعم — NABOO",
};

export default function SupportLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
