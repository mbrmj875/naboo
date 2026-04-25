import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

const PREVIEW_MAX_CHARS = 250_000;

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  try {
    const userId = new URL(req.url).searchParams.get("userId")?.trim();
    if (!userId) {
      return NextResponse.json({ error: "ناقص userId" }, { status: 400 });
    }
    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from("app_snapshots")
      .select("payload,updated_at,device_label,schema_version,user_id")
      .eq("user_id", userId)
      .maybeSingle();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    if (!data) {
      return NextResponse.json({ error: "لا توجد لقطة مزامنة لهذا المستخدم" }, { status: 404 });
    }

    const payload = data.payload as unknown;
    let str: string;
    try {
      str = JSON.stringify(payload, null, 2);
    } catch {
      str = String(payload);
    }
    const truncated = str.length > PREVIEW_MAX_CHARS;
    const preview = truncated ? `${str.slice(0, PREVIEW_MAX_CHARS)}\n\n… [مقطوع — المعاينة محدودة]` : str;

    const topLevelKeys =
      payload !== null &&
      typeof payload === "object" &&
      !Array.isArray(payload)
        ? Object.keys(payload as Record<string, unknown>).slice(0, 120)
        : [];

    return NextResponse.json({
      preview,
      truncated,
      approxChars: str.length,
      topLevelKeys,
      updated_at: data.updated_at,
      device_label: data.device_label,
      schema_version: data.schema_version,
      user_id: data.user_id,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
