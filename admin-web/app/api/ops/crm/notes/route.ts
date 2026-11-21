import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type Body = {
  account_user_id: string;
  body: string;
  created_by?: string | null;
  contact_id?: string | null;
};

export async function POST(req: Request) {
  try {
    const payload = (await req.json()) as Body;
    const accountUserId = (payload.account_user_id ?? "").trim();
    const text = (payload.body ?? "").trim();
    if (!accountUserId) {
      return NextResponse.json({ error: "معرّف الحساب ناقص" }, { status: 400 });
    }
    if (text.length < 2) {
      return NextResponse.json({ error: "نص الملاحظة قصير جداً" }, { status: 400 });
    }
    if (text.length > 4000) {
      return NextResponse.json({ error: "نص الملاحظة طويل جداً" }, { status: 400 });
    }

    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from("ops_crm_notes")
      .insert({
        account_user_id: accountUserId,
        contact_id: payload.contact_id || null,
        body: text,
        created_by: payload.created_by?.trim() || "admin",
      })
      .select("*")
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true, note: data });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
