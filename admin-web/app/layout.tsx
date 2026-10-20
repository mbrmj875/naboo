import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://admin.naboo.fun"),
  title: "NABOO — لوحة الإدارة",
  description: "متابعة المستخدمين والأجهزة والتراخيص",
  robots: "noindex, nofollow",
  alternates: {
    canonical: "https://admin.naboo.fun",
  },
  openGraph: {
    title: "NABOO — لوحة الإدارة",
    description: "متابعة المستخدمين والأجهزة والتراخيص",
    url: "https://admin.naboo.fun",
    siteName: "NABOO",
    locale: "ar_SA",
    type: "website",
    images: [
      {
        url: "https://naboo.fun/app/icons/Icon-512.png",
        width: 512,
        height: 512,
        alt: "NABOO",
      },
    ],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ar" dir="rtl">
      <head>
        {/* Self-hosted only — لا Google Fonts CDN (restaurant public menu + admin) */}
        <link
          rel="preload"
          as="font"
          href="/fonts/tajawal/400.ttf"
          type="font/ttf"
          crossOrigin="anonymous"
        />
        <style
          dangerouslySetInnerHTML={{
            __html: `
@font-face {
  font-family: 'Tajawal';
  font-weight: 400;
  font-style: normal;
  font-display: swap;
  src: url('/fonts/tajawal/400.ttf') format('truetype');
}
@font-face {
  font-family: 'Tajawal';
  font-weight: 700;
  font-style: normal;
  font-display: swap;
  src: url('/fonts/tajawal/700.ttf') format('truetype');
}
body { font-family: 'Tajawal', system-ui, sans-serif; }
`,
          }}
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
