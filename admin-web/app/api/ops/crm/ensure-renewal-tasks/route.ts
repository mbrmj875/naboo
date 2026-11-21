import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import {
  EXPIRING_DAYS,
  getAccountStatus,
  isTrialExpiring,
  pickLicenseForUser,
  TRIAL_ENDING_DAYS,
} from "@/lib/account-status";
import type { LicenseRow, UserRow } from "@/lib/dashboard-data";
import { formatNumberLatn } from "@/lib/format-ar";
import { isInactiveLogin, INACTIVE_LOGIN_DAYS } from "@/lib/ops-crm";

type Body = {
  users: UserRow[];
  licenses: LicenseRow[];
};

/**
 * ينشئ مهام تجديد/خمول تلقائية إن لم توجد مفتوحة من نفس النوع لنفس الحساب.
 */
export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const users = Array.isArray(body.users) ? body.users : [];
    const licenses = Array.isArray(body.licenses) ? body.licenses : [];
    if (users.length === 0) {
      return NextResponse.json({ ok: true, created: 0 });
    }

    const supabase = getSupabaseAdmin();
    const { data: openTasks, error: listErr } = await supabase
      .from("ops_crm_tasks")
      .select("account_user_id,kind")
      .is("done_at", null)
      .in("kind", ["renewal", "inactive"]);

    if (listErr) {
      return NextResponse.json({ error: listErr.message }, { status: 400 });
    }

    const existing = new Set(
      (openTasks ?? []).map(
        (t) =>
          `${(t as { account_user_id: string }).account_user_id}:${(t as { kind: string }).kind}`,
      ),
    );

    const inserts: {
      account_user_id: string;
      title: string;
      due_at: string;
      kind: string;
      created_by: string;
    }[] = [];

    const now = Date.now();

    for (const user of users) {
      const license = pickLicenseForUser(user.id, licenses);
      const status = getAccountStatus(user, license);

      if (status === "expiring" || isTrialExpiring(user, license)) {
        const key = `${user.id}:renewal`;
        if (!existing.has(key)) {
          const days =
            status === "expiring"
              ? Math.max(0, license?.expires_days_left ?? EXPIRING_DAYS)
              : Math.max(0, user.trial_days_left ?? TRIAL_ENDING_DAYS);
          inserts.push({
            account_user_id: user.id,
            title: `متابعة تجديد الاشتراك (متبقي ${formatNumberLatn(days)} يوم)`,
            due_at: new Date(now + Math.min(days, 7) * 86400000).toISOString(),
            kind: "renewal",
            created_by: "system",
          });
          existing.add(key);
        }
      }

      if (isInactiveLogin(user, license, now)) {
        const key = `${user.id}:inactive`;
        if (!existing.has(key)) {
          inserts.push({
            account_user_id: user.id,
            title: `تحفيز استخدام — لم يدخل منذ ${formatNumberLatn(INACTIVE_LOGIN_DAYS)}+ يوم`,
            due_at: new Date(now + 2 * 86400000).toISOString(),
            kind: "inactive",
            created_by: "system",
          });
          existing.add(key);
        }
      }
    }

    if (inserts.length === 0) {
      return NextResponse.json({ ok: true, created: 0 });
    }

    const { error } = await supabase.from("ops_crm_tasks").insert(inserts);
    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
    return NextResponse.json({ ok: true, created: inserts.length });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
