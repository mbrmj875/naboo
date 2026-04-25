import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

type Body = {
  deviceRowId: number;
  access_status: "active" | "revoked";
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const id = Number(body.deviceRowId);
    if (!Number.isFinite(id) || id <= 0) {
      return NextResponse.json({ error: "معرّف الجهاز غير صالح" }, { status: 400 });
    }
    if (body.access_status !== "active" && body.access_status !== "revoked") {
      return NextResponse.json({ error: "الحالة يجب أن تكون active أو revoked" }, { status: 400 });
    }
    const supabase = getSupabaseAdmin();
    const { error } = await supabase
      .from("account_devices")
      .update({
        access_status: body.access_status,
        last_seen_at: new Date().toISOString(),
      })
      .eq("id", id);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
