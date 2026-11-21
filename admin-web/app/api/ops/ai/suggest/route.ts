import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import {
  ensureOpsContact,
  findContactByAuthUserId,
  findContactByPhone,
} from "@/lib/ops-contacts";
import { suggestOpsAiReply } from "@/lib/ops-ai";
import type { LicenseRow, UserRow } from "@/lib/dashboard-data";

type Body = {
  contact_id?: string;
  phone?: string;
  account_user_id?: string;
  latest_message?: string;
  user?: UserRow | null;
  licenses?: LicenseRow[];
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    let contact =
      (body.contact_id
        ? (
            await getSupabaseAdmin()
              .from("ops_contacts")
              .select("*")
              .eq("id", body.contact_id)
              .maybeSingle()
          ).data
        : null) ?? null;

    if (!contact && body.account_user_id) {
      contact = await findContactByAuthUserId(body.account_user_id);
    }
    if (!contact && body.phone) {
      contact = await findContactByPhone(body.phone);
    }
    if (!contact && body.phone) {
      contact = await ensureOpsContact({ phone: body.phone });
    }
    if (!contact) {
      return NextResponse.json(
        { error: "تعذر تحديد جهة التواصل" },
        { status: 400 },
      );
    }

    const latest =
      (body.latest_message ?? "").trim() ||
      "مرحبا، أحتاج مساعدة بخصوص نابو";

    const contactRow = contact as { id: string; auth_user_id?: string | null };
    // لا نثق بـ user/licenses من العميل إن لم يطابقا جهة التواصل.
    let user: UserRow | null = null;
    let licenses: LicenseRow[] = [];
    if (
      body.user &&
      contactRow.auth_user_id &&
      body.user.id === contactRow.auth_user_id
    ) {
      user = body.user;
      licenses = body.licenses ?? [];
    }

    const suggestion = await suggestOpsAiReply({
      contact: contact as never,
      user,
      licenses,
      latestCustomerMessage: latest,
    });

    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from("ops_ai_suggestions")
      .insert({
        contact_id: (contact as { id: string }).id,
        response_text: suggestion.text,
        confidence: suggestion.confidence,
        status: "pending",
        created_by: "admin",
      })
      .select("*")
      .single();

    if (error) {
      return NextResponse.json(
        {
          ok: true,
          suggestion: {
            response_text: suggestion.text,
            confidence: suggestion.confidence,
            status: "pending",
          },
          persistError: error.message,
        },
        { status: 200 },
      );
    }

    return NextResponse.json({ ok: true, suggestion: data });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
