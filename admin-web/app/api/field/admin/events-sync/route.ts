import { NextResponse } from "next/server";
import { listVisitEventsSince } from "@/lib/field-db";
import { requireAdminSession } from "@/lib/field-request";

export async function GET(req: Request) {
  const auth = await requireAdminSession();
  if (!auth.ok) return auth.response;

  const url = new URL(req.url);
  let since = Number(url.searchParams.get("since") ?? "0");
  if (!Number.isFinite(since) || since < 0) since = 0;

  const events = await listVisitEventsSince(since, 200);
  return NextResponse.json({ events });
}
