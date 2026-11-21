import type { ReactNode } from "react";
import "./[tenant_slug]/menu.css";

/** منيو عام — بلا Google Fonts؛ الخطوط من /public/fonts فقط. */
export default function PublicMenuRootLayout({
  children,
}: {
  children: ReactNode;
}) {
  return <>{children}</>;
}
