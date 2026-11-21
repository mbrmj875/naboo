import { NextResponse } from "next/server";
import { fetchCrmBundle } from "@/lib/ops-crm-db";
import {
  buildSystemTimeline,
  mergeTimeline,
  type OpsTimelineItem,
} from "@/lib/ops-crm";
import type { DeviceRow, LicenseRow, UserRow } from "@/lib/dashboard-data";
import { getSupabaseAdmin } from "@/lib/supabase-admin";
import {
  findContactByAuthUserId,
  findContactByPhone,
  listRecentMessagesForContact,
} from "@/lib/ops-contacts";
import { opsChannelLabelAr } from "@/lib/ops-channels";

type Body = {
  accountUserId?: string;
  user?: UserRow;
  license?: LicenseRow | null;
  devices?: DeviceRow[];
};

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const accountUserId = (body.accountUserId ?? body.user?.id ?? "").trim();
    if (!accountUserId) {
      return NextResponse.json({ error: "معرّف الحساب ناقص" }, { status: 400 });
    }

    let bundle;
    try {
      bundle = await fetchCrmBundle(accountUserId);
    } catch (e) {
      const msg = e instanceof Error ? e.message : "خطأ";
      if (msg.includes("ops_crm") || msg.includes("does not exist")) {
        return NextResponse.json({
          meta: null,
          notes: [],
          tasks: [],
          timeline: body.user
            ? buildSystemTimeline({
                user: body.user,
                license: body.license ?? null,
                devices: body.devices ?? [],
              })
            : [],
          schemaMissing: true,
        });
      }
      throw e;
    }

    const messageItems: OpsTimelineItem[] = [];
    try {
      let contact = await findContactByAuthUserId(accountUserId);
      if (!contact && body.user?.phone) {
        contact = await findContactByPhone(body.user.phone);
      }
      if (contact) {
        const msgs = await listRecentMessagesForContact(contact.id, 20);
        for (const m of msgs) {
          messageItems.push({
            id: `msg-${m.id}`,
            at: m.created_at,
            title: `رسالة ${opsChannelLabelAr(m.channel)}`,
            detail: m.body.slice(0, 240),
            kind: "message",
          });
        }
      }
    } catch {
      /* جداول الرسائل قد لا تكون مُنشأة بعد */
    }

    const system = body.user
      ? buildSystemTimeline({
          user: body.user,
          license: body.license ?? null,
          devices: body.devices ?? [],
        })
      : [];

    const timeline = mergeTimeline(
      system,
      bundle.notes,
      bundle.tasks,
      messageItems,
    );

    return NextResponse.json({
      meta: bundle.meta,
      notes: bundle.notes,
      tasks: bundle.tasks,
      timeline,
      schemaMissing: false,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}

/** ربط بسيط: التأكد أن supabase admin يعمل. */
export async function GET() {
  try {
    const supabase = getSupabaseAdmin();
    const { error } = await supabase.from("ops_crm_meta").select("account_user_id").limit(1);
    if (error) {
      return NextResponse.json({
        ok: false,
        schemaReady: false,
        error: error.message,
      });
    }
    return NextResponse.json({ ok: true, schemaReady: true });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ ok: false, error: msg }, { status: 500 });
  }
}
