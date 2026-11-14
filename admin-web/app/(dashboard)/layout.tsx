import { DashboardSidebar } from "@/components/dashboard-sidebar";

export default function DashboardLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <div className="dash-shell">
      <DashboardSidebar />
      <main className="dash-main">{children}</main>
    </div>
  );
}
