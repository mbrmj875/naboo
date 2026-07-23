import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "المنتجات — NABOO",
};

export default function MarketProductsLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
