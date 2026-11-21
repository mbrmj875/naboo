import type { Metadata, Viewport } from "next";
import "./field.css";
import { FieldRoot } from "@/components/field/field-root";

export const metadata: Metadata = {
  title: "مندوبو نابو",
  description: "تسجيل زيارات المحلات",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "نابو ميدان",
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f0f3f7" },
    { media: "(prefers-color-scheme: dark)", color: "#0b1f33" },
  ],
};

export default function FieldLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <FieldRoot>{children}</FieldRoot>;
}
