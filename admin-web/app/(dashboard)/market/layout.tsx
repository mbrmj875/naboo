import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "السوق — NABOO",
};

export default function MarketLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
