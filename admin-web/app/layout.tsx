import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "NABOO — لوحة الإدارة",
  description: "متابعة المستخدمين والأجهزة والتراخيص",
  robots: "noindex, nofollow",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ar" dir="rtl">
      <head>
        <link
          href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700;800&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
