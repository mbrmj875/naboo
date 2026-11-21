import { NextResponse } from "next/server";
import { requireFieldOrAdminSession } from "@/lib/field-request";

export async function HEAD() {
  const auth = await requireFieldOrAdminSession();
  if (!auth.ok) return auth.response;
  return new NextResponse(null, { status: 204 });
}

export async function GET() {
  const auth = await requireFieldOrAdminSession();
  if (!auth.ok) return auth.response;
  return new NextResponse(null, { status: 204 });
}
