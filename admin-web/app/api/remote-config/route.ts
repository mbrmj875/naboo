import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import {
  defaultAppRemoteConfig,
  type AppRemoteConfigPayload,
} from "@/lib/dashboard-data";

function sanitize(body: unknown): AppRemoteConfigPayload {
  const d = defaultAppRemoteConfig();
  if (!body || typeof body !== "object") return d;
  const o = body as Record<string, unknown>;
  const b = (k: string) => o[k] === true;
  const s = (k: string) => (o[k] != null ? String(o[k]).trim() : "");
  return {
    maintenance_mode: b("maintenance_mode"),
    maintenance_message_ar: s("maintenance_message_ar"),
    sync_paused_globally: b("sync_paused_globally"),
    sync_paused_message_ar: s("sync_paused_message_ar") || d.sync_paused_message_ar,
    min_supported_version: s("min_supported_version") || d.min_supported_version,
    latest_version: s("latest_version") || d.latest_version,
    update_message_ar: s("update_message_ar"),
    force_update: b("force_update"),
    update_download_url: s("update_download_url"),
    announcement_title_ar: s("announcement_title_ar"),
    announcement_body_ar: s("announcement_body_ar"),
    announcement_url: s("announcement_url"),
  };
}

export async function POST(req: Request) {
  try {
    const raw = (await req.json()) as { config?: unknown };
    const config = sanitize(raw.config);
    const supabase = getSupabaseAdmin();
    const { error } = await supabase.from("app_remote_config").upsert(
      {
        id: 1,
        config,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "id" },
    );
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
