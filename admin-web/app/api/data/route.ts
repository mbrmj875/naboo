import { NextResponse } from "next/server";
import { loadDashboardData } from "@/lib/dashboard-data";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    const data = await loadDashboardData();
    return NextResponse.json(data);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "فشل تحميل البيانات";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
