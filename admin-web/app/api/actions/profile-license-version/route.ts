import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type Body = {
  userId: string;
  version: "v1" | "v2";
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const userId = (body.userId ?? "").trim();
    const version = body.version;
    if (!userId) {
      return NextResponse.json({ error: "معرّف المستخدم ناقص" }, { status: 400 });
    }
    if (version !== "v1" && version !== "v2") {
      return NextResponse.json({ error: "الإصدار يجب أن يكون v1 أو v2" }, { status: 400 });
    }

    const nowIso = new Date().toISOString();
    const supabase = getSupabaseAdmin();
    const { error } = await supabase
      .from("profiles")
      .update({
        license_system_version: version,
        updated_at: nowIso,
      })
      .eq("id", userId);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
