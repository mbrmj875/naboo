import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type Body = {
  userId: string;
  title_ar?: string | null;
  body_ar?: string | null;
  active?: boolean;
  clear?: boolean;
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const userId = (body.userId ?? "").trim();
    if (!userId) {
      return NextResponse.json({ error: "معرّف المستخدم ناقص" }, { status: 400 });
    }

    const clear = body.clear === true;
    const nowIso = new Date().toISOString();
    const title = (body.title_ar ?? "").trim();
    const msgBody = (body.body_ar ?? "").trim();
    const active = body.active !== false;

    if (!clear && msgBody.length < 2) {
      return NextResponse.json(
        { error: "نص الرسالة قصير جداً (حد أدنى حرفان)" },
        { status: 400 },
      );
    }
    if (!clear && msgBody.length > 4000) {
      return NextResponse.json(
        { error: "نص الرسالة طويل جداً (الحد 4000 حرف)" },
        { status: 400 },
      );
    }
    if (!clear && title.length > 120) {
      return NextResponse.json(
        { error: "عنوان الرسالة طويل جداً (الحد 120 حرف)" },
        { status: 400 },
      );
    }

    const supabase = getSupabaseAdmin();
    const patch = clear
      ? {
          custom_message_title_ar: null,
          custom_message_body_ar: null,
          custom_message_active: false,
          custom_message_updated_at: nowIso,
          updated_at: nowIso,
        }
      : {
          custom_message_title_ar: title || null,
          custom_message_body_ar: msgBody,
          custom_message_active: active,
          custom_message_updated_at: nowIso,
          updated_at: nowIso,
        };

    const { error } = await supabase.from("profiles").update(patch).eq("id", userId);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
