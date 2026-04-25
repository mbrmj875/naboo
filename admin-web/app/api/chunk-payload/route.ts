import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

const PREVIEW_MAX_CHARS = 200_000;

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  try {
    const url = new URL(req.url);
    const userId = url.searchParams.get("userId")?.trim();
    const syncId = url.searchParams.get("syncId")?.trim();
    const indexRaw = url.searchParams.get("chunkIndex") ?? "0";
    const chunkIndex = parseInt(indexRaw, 10);
    if (!userId || !syncId) {
      return NextResponse.json({ error: "ناقص userId أو syncId" }, { status: 400 });
    }
    if (!Number.isFinite(chunkIndex) || chunkIndex < 0) {
      return NextResponse.json({ error: "chunkIndex غير صالح" }, { status: 400 });
    }

    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from("app_snapshot_chunks")
      .select("chunk_data,updated_at,user_id,sync_id,chunk_index")
      .eq("user_id", userId)
      .eq("sync_id", syncId)
      .eq("chunk_index", chunkIndex)
      .maybeSingle();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    if (!data) {
      return NextResponse.json({ error: "الجزء غير موجود" }, { status: 404 });
    }

    const raw = data.chunk_data as string;
    const truncated = raw.length > PREVIEW_MAX_CHARS;
    const preview = truncated ? `${raw.slice(0, PREVIEW_MAX_CHARS)}\n\n… [مقطوع]` : raw;

    return NextResponse.json({
      preview,
      truncated,
      approxChars: raw.length,
      updated_at: data.updated_at,
      sync_id: data.sync_id,
      chunk_index: data.chunk_index,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
