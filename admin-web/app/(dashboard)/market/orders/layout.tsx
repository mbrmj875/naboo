import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "الطلبات — NABOO",
};

export default function MarketOrdersLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
