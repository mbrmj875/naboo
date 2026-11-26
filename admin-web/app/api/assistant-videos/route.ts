import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import { ASSISTANT_SCREENS } from "@/lib/assistant-screens";

/** روابط فيديو شرح الشاشات (م3-15): تُحفظ في app_remote_config.config.assistant.videos
 *  ويقرؤها التطبيق عند فتح المساعد، فتظهر بلا تحديث للتطبيق. */

const known = new Set(ASSISTANT_SCREENS.map((s) => s.routeId));

function cleanVideos(raw: unknown): Record<string, string> | string {
  if (!raw || typeof raw !== "object") return "قائمة الروابط غير صالحة";
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    const url = (v ?? "").toString().trim();
    if (!url) continue;
    if (!known.has(k)) return `شاشة غير معروفة: ${k}`;
    let u: URL;
    try {
      u = new URL(url);
    } catch {
      return `رابط غير صالح: ${url}`;
    }
    if (u.protocol !== "https:") return `الرابط يجب أن يبدأ بـ https: ${url}`;
    if (url.length > 500) return "الرابط طويل جداً";
    out[k] = url;
  }
  return out;
}

async function readConfig() {
  const supabase = getSupabaseAdmin();
  const { data, error } = await supabase
    .from("app_remote_config")
    .select("config")
    .eq("id", 1)
    .maybeSingle();
  if (error) throw new Error(error.message);
  const config =
    data?.config && typeof data.config === "object"
      ? (data.config as Record<string, unknown>)
      : {};
  return { supabase, config };
}

export async function GET() {
  try {
    const { config } = await readConfig();
    const assistant =
      config.assistant && typeof config.assistant === "object"
        ? (config.assistant as Record<string, unknown>)
        : {};
    const videos =
      assistant.videos && typeof assistant.videos === "object" ? assistant.videos : {};
    return NextResponse.json({ videos });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "خطأ" }, { status: 500 });
  }
}

export async function POST(req: Request) {
  try {
    const raw = (await req.json()) as { videos?: unknown };
    const videos = cleanVideos(raw.videos);
    if (typeof videos === "string") {
      return NextResponse.json({ error: videos }, { status: 400 });
    }
    const { supabase, config } = await readConfig();
    const assistant =
      config.assistant && typeof config.assistant === "object"
        ? (config.assistant as Record<string, unknown>)
        : {};
    const { error } = await supabase.from("app_remote_config").upsert(
      {
        id: 1,
        config: { ...config, assistant: { ...assistant, videos } },
        updated_at: new Date().toISOString(),
      },
      { onConflict: "id" },
    );
    if (error) return NextResponse.json({ error: error.message }, { status: 400 });
    return NextResponse.json({ ok: true, count: Object.keys(videos).length });
  } catch (e) {
    return NextResponse.json({ error: e instanceof Error ? e.message : "خطأ" }, { status: 500 });
  }
}
