import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "المحلات — NABOO",
};

export default function MarketStoresLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
