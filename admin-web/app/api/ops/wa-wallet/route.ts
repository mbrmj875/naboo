import { NextResponse } from "next/server";
import {
  confirmWaPackOrder,
  creditWaWallet,
  fetchWaWalletBundle,
  listPendingWaOrders,
  setWaWalletFlags,
} from "@/lib/ops-wa-wallet";

type Body = {
  action?: string;
  tenantUserId?: string;
  accountUserId?: string;
  orderId?: string;
  qty?: number;
  billingCycle?: "monthly" | "annual";
  frozen?: boolean;
  sendBlocked?: boolean;
  walletExempt?: boolean;
  notesAdmin?: string | null;
  decidedBy?: string;
};

function tenantOf(body: Body): string {
  return (body.tenantUserId ?? body.accountUserId ?? "").trim();
}

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as Body;
    const action = (body.action ?? "bundle").trim();
    const tenantUserId = tenantOf(body);

    if (action === "list_pending") {
      const orders = await listPendingWaOrders();
      return NextResponse.json({ orders });
    }

    if (action === "bundle") {
      if (!tenantUserId) {
        return NextResponse.json({ error: "معرّف الحساب ناقص" }, { status: 400 });
      }
      const bundle = await fetchWaWalletBundle(tenantUserId);
      return NextResponse.json(bundle);
    }

    if (action === "credit") {
      if (!tenantUserId) {
        return NextResponse.json({ error: "معرّف الحساب ناقص" }, { status: 400 });
      }
      const qty = Number(body.qty ?? 0);
      if (!Number.isFinite(qty) || qty <= 0) {
        return NextResponse.json({ error: "كمية غير صالحة" }, { status: 400 });
      }
      const result = await creditWaWallet({
        tenantUserId,
        qty: Math.trunc(qty),
        billingCycle: body.billingCycle === "annual" ? "annual" : "monthly",
        createdBy: body.decidedBy?.trim() || "admin",
        reason: "admin_adjust",
      });
      return NextResponse.json({ ok: true, ...result });
    }

    if (action === "confirm_order") {
      const orderId = (body.orderId ?? "").trim();
      if (!orderId) {
        return NextResponse.json({ error: "معرّف الطلب ناقص" }, { status: 400 });
      }
      const result = await confirmWaPackOrder({
        orderId,
        decidedBy: body.decidedBy?.trim() || "admin",
      });
      if (!result.ok) {
        return NextResponse.json({ error: result.error }, { status: 400 });
      }
      return NextResponse.json({ ok: true });
    }

    if (action === "flags") {
      if (!tenantUserId) {
        return NextResponse.json({ error: "معرّف الحساب ناقص" }, { status: 400 });
      }
      await setWaWalletFlags({
        tenantUserId,
        frozen: body.frozen,
        sendBlocked: body.sendBlocked,
        walletExempt: body.walletExempt,
        notesAdmin: body.notesAdmin,
      });
      return NextResponse.json({ ok: true });
    }

    return NextResponse.json({ error: "إجراء غير معروف" }, { status: 400 });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    if (msg.includes("does not exist") || msg.includes("wa_message")) {
      return NextResponse.json(
        { error: "سكربت المحفظة غير مُثبّت — شغّل wa_message_wallet_v1.sql", schemaMissing: true },
        { status: 503 },
      );
    }
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
