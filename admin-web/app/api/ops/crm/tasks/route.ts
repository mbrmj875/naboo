import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type CreateBody = {
  account_user_id: string;
  title: string;
  due_at?: string | null;
  assignee?: string | null;
  kind?: string;
  created_by?: string | null;
  contact_id?: string | null;
};

type PatchBody = {
  id: string;
  done?: boolean;
  title?: string;
  due_at?: string | null;
  assignee?: string | null;
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as CreateBody;
    const accountUserId = (body.account_user_id ?? "").trim();
    const title = (body.title ?? "").trim();
    if (!accountUserId) {
      return NextResponse.json({ error: "معرّف الحساب ناقص" }, { status: 400 });
    }
    if (title.length < 2) {
      return NextResponse.json({ error: "عنوان المهمة قصير جداً" }, { status: 400 });
    }

    const kind = (body.kind ?? "manual").trim();
    const allowed = new Set(["manual", "renewal", "inactive", "onboarding"]);
    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from("ops_crm_tasks")
      .insert({
        account_user_id: accountUserId,
        contact_id: body.contact_id || null,
        title: title.slice(0, 240),
        due_at: body.due_at || null,
        assignee: body.assignee?.trim() || null,
        kind: allowed.has(kind) ? kind : "manual",
        created_by: body.created_by?.trim() || "admin",
      })
      .select("*")
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true, task: data });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}

export async function PATCH(req: Request) {
  try {
    const body = (await req.json()) as PatchBody;
    const id = (body.id ?? "").trim();
    if (!id) {
      return NextResponse.json({ error: "معرّف المهمة ناقص" }, { status: 400 });
    }

    const patch: Record<string, unknown> = {};
    if (body.done === true) patch.done_at = new Date().toISOString();
    if (body.done === false) patch.done_at = null;
    if (body.title != null) patch.title = String(body.title).trim().slice(0, 240);
    if (body.due_at !== undefined) patch.due_at = body.due_at;
    if (body.assignee !== undefined) {
      patch.assignee = body.assignee?.trim() || null;
    }

    if (Object.keys(patch).length === 0) {
      return NextResponse.json({ error: "لا يوجد تعديل" }, { status: 400 });
    }

    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from("ops_crm_tasks")
      .update(patch)
      .eq("id", id)
      .select("*")
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true, task: data });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
