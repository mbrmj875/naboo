import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type Body = {
  userId: string;
  action: "ban" | "unban";
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const userId = (body.userId ?? "").trim();
    if (!userId) {
      return NextResponse.json({ error: "معرّف المستخدم ناقص" }, { status: 400 });
    }
    if (body.action !== "ban" && body.action !== "unban") {
      return NextResponse.json({ error: "إجراء غير معروف" }, { status: 400 });
    }
    const supabase = getSupabaseAdmin();
    const attrs =
      body.action === "ban"
        ? { ban_duration: "87600h" as const }
        : { ban_duration: "none" as const };
    const { error } = await supabase.auth.admin.updateUserById(userId, attrs);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
