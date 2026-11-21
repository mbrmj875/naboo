import { NextResponse } from "next/server";
import {
  ensureOpsContact,
  findContactByAuthUserId,
  findContactByPhone,
  linkContactToAuthUser,
} from "@/lib/ops-contacts";
import { normalizePhoneE164 } from "@/lib/ops-phone";
import { getAccountStatus, pickLicenseForUser } from "@/lib/account-status";
import type { LicenseRow, UserRow } from "@/lib/dashboard-data";

type SyncBody = {
  user: UserRow;
  licenses?: LicenseRow[];
};

/** يربط حساب Auth بهوية ops_contacts عبر الهاتف ويحدّث lifecycle. */
export async function POST(req: Request) {
  try {
    const body = (await req.json()) as SyncBody;
    const user = body.user;
    if (!user?.id) {
      return NextResponse.json({ error: "المستخدم ناقص" }, { status: 400 });
    }

    const phone = normalizePhoneE164(user.phone);
    let contact = await findContactByAuthUserId(user.id);
    if (!contact && phone) {
      contact = await findContactByPhone(phone);
      if (contact) await linkContactToAuthUser(contact.id, user.id);
    }
    if (!contact && phone) {
      contact = await ensureOpsContact({
        phone,
        displayName: user.display_name,
        authUserId: user.id,
      });
    }
    if (!contact) {
      return NextResponse.json({
        ok: true,
        contact: null,
        reason: "لا يوجد هاتف لربط الهوية",
      });
    }

    const license = pickLicenseForUser(user.id, body.licenses ?? []);
    const status = getAccountStatus(user, license);
    const lifecycleMap: Record<string, string> = {
      trial: "trial",
      active: "active",
      expiring: "expiring",
      expired: "expired",
      disabled: "churned",
      no_subscription: "lead",
    };
    const lifecycle = lifecycleMap[status] ?? "lead";

    const { getSupabaseAdmin } = await import("@/lib/supabase-admin");
    const supabase = getSupabaseAdmin();
    const { data, error } = await supabase
      .from("ops_contacts")
      .update({
        auth_user_id: user.id,
        display_name: user.display_name || contact.display_name,
        email: user.email || contact.email,
        lifecycle,
        updated_at: new Date().toISOString(),
      })
      .eq("id", contact.id)
      .select("*")
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    await supabase.from("ops_crm_meta").upsert(
      {
        account_user_id: user.id,
        contact_id: contact.id,
        updated_at: new Date().toISOString(),
        updated_by: "sync",
      },
      { onConflict: "account_user_id" },
    );

    return NextResponse.json({ ok: true, contact: data });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
