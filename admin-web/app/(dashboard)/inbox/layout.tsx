import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "الصندوق — NABOO",
};

export default function InboxLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
