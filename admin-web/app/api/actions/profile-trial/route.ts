import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type Body = {
  userId: string;
  /** إن وُجد: يُعيَّن كبداية تجربة (ISO). وإلا: الآن بتوقيت UTC */
  trial_started_at?: string | null;
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const userId = (body.userId ?? "").trim();
    if (!userId) {
      return NextResponse.json({ error: "معرّف المستخدم ناقص" }, { status: 400 });
    }
    const iso =
      body.trial_started_at && body.trial_started_at.trim().length > 0
        ? new Date(body.trial_started_at).toISOString()
        : new Date().toISOString();
    const supabase = getSupabaseAdmin();
    const { error } = await supabase
      .from("profiles")
      .update({
        trial_started_at: iso,
        updated_at: new Date().toISOString(),
      })
      .eq("id", userId);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true, trial_started_at: iso });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
