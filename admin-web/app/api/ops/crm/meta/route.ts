import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type Body = {
  account_user_id: string;
  owner?: string | null;
  tags?: string[];
  next_follow_up_at?: string | null;
  contact_id?: string | null;
  updated_by?: string | null;
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const accountUserId = (body.account_user_id ?? "").trim();
    if (!accountUserId) {
      return NextResponse.json({ error: "معرّف الحساب ناقص" }, { status: 400 });
    }

    const supabase = getSupabaseAdmin();
    const row = {
      account_user_id: accountUserId,
      owner: body.owner?.trim() || null,
      tags: Array.isArray(body.tags)
        ? body.tags.map((t) => String(t).trim()).filter(Boolean).slice(0, 20)
        : [],
      next_follow_up_at: body.next_follow_up_at || null,
      contact_id: body.contact_id || null,
      updated_at: new Date().toISOString(),
      updated_by: body.updated_by?.trim() || "admin",
    };

    const { data, error } = await supabase
      .from("ops_crm_meta")
      .upsert(row, { onConflict: "account_user_id" })
      .select("*")
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true, meta: data });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
