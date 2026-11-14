import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "تسجيل الدخول — NABOO",
};

export default function LoginLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
