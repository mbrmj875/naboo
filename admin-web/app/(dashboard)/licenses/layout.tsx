import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "التراخيص — NABOO",
};

export default function LicensesLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
