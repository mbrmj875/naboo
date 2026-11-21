import { getSupabaseAdmin } from "@/lib/supabase-admin";

export type WaWalletBundle = {
  balance: number;
  frozen: boolean;
  sendBlocked: boolean;
  walletExempt: boolean;
  notesAdmin: string | null;
  nearestExpiry: string | null;
  activeSub: {
    id: string;
    qty: number;
    monthsCredited: number;
    endsAt: string;
    status: string;
  } | null;
  pendingOrders: Array<{
    id: string;
    qty: number;
    billingCycle: string;
    amountIqd: number;
    createdAt: string;
  }>;
  ledger: Array<{
    id: string;
    delta: number;
    reason: string;
    createdAt: string;
  }>;
  schemaMissing?: boolean;
};

function asInt(v: unknown, fb = 0): number {
  if (typeof v === "number") return Math.trunc(v);
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : fb;
}

export async function fetchWaWalletBundle(
  tenantUserId: string,
): Promise<WaWalletBundle> {
  const db = getSupabaseAdmin();
  try {
    await db.rpc("wa_wallet_ensure", { p_tenant: tenantUserId });
  } catch {
    /* ensure may be missing */
  }

  const { data: wallet, error: wErr } = await db
    .from("wa_message_wallet")
    .select(
      "balance, frozen, send_blocked, wallet_exempt, notes_admin",
    )
    .eq("tenant_user_id", tenantUserId)
    .maybeSingle();

  if (wErr) {
    const msg = (wErr.message ?? "").toLowerCase();
    if (msg.includes("does not exist") || wErr.code === "42P01") {
      return {
        balance: 0,
        frozen: false,
        sendBlocked: false,
        walletExempt: false,
        notesAdmin: null,
        nearestExpiry: null,
        activeSub: null,
        pendingOrders: [],
        ledger: [],
        schemaMissing: true,
      };
    }
    throw wErr;
  }

  const { data: lots } = await db
    .from("wa_message_lots")
    .select("expires_at")
    .eq("tenant_user_id", tenantUserId)
    .eq("status", "active")
    .gt("messages_remaining", 0)
    .order("expires_at", { ascending: true })
    .limit(1);

  const { data: subs } = await db
    .from("wa_message_subscriptions")
    .select("id, qty, months_credited, ends_at, status")
    .eq("tenant_user_id", tenantUserId)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(1);

  const { data: orders } = await db
    .from("wa_message_pack_orders")
    .select("id, qty, billing_cycle, amount_iqd, created_at")
    .eq("tenant_user_id", tenantUserId)
    .eq("status", "pending_payment")
    .order("created_at", { ascending: false })
    .limit(10);

  const { data: ledger } = await db
    .from("wa_message_ledger")
    .select("id, delta, reason, created_at")
    .eq("tenant_user_id", tenantUserId)
    .order("created_at", { ascending: false })
    .limit(25);

  const sub = Array.isArray(subs) && subs.length ? subs[0] : null;

  return {
    balance: asInt(wallet?.balance),
    frozen: wallet?.frozen === true,
    sendBlocked: wallet?.send_blocked === true,
    walletExempt: wallet?.wallet_exempt === true,
    notesAdmin: (wallet?.notes_admin as string | null) ?? null,
    nearestExpiry:
      Array.isArray(lots) && lots[0]?.expires_at
        ? String(lots[0].expires_at)
        : null,
    activeSub: sub
      ? {
          id: String(sub.id),
          qty: asInt(sub.qty),
          monthsCredited: asInt(sub.months_credited),
          endsAt: String(sub.ends_at),
          status: String(sub.status),
        }
      : null,
    pendingOrders: (orders ?? []).map((o) => ({
      id: String(o.id),
      qty: asInt(o.qty),
      billingCycle: String(o.billing_cycle),
      amountIqd: asInt(o.amount_iqd),
      createdAt: String(o.created_at),
    })),
    ledger: (ledger ?? []).map((r) => ({
      id: String(r.id),
      delta: asInt(r.delta),
      reason: String(r.reason),
      createdAt: String(r.created_at),
    })),
  };
}

export async function listPendingWaOrders(): Promise<
  Array<{
    id: string;
    tenantUserId: string;
    email: string | null;
    qty: number;
    billingCycle: string;
    amountIqd: number;
    createdAt: string;
  }>
> {
  const db = getSupabaseAdmin();
  const { data, error } = await db
    .from("wa_message_pack_orders")
    .select("id, tenant_user_id, qty, billing_cycle, amount_iqd, created_at")
    .eq("status", "pending_payment")
    .order("created_at", { ascending: false })
    .limit(50);
  if (error) {
    const msg = (error.message ?? "").toLowerCase();
    if (msg.includes("does not exist") || error.code === "42P01") return [];
    throw error;
  }

  const rows = data ?? [];
  const emails = new Map<string, string | null>();
  for (const row of rows) {
    const tid = String(row.tenant_user_id);
    if (emails.has(tid)) continue;
    try {
      const { data: userData } = await db.auth.admin.getUserById(tid);
      emails.set(tid, userData.user?.email ?? null);
    } catch {
      emails.set(tid, null);
    }
  }

  return rows.map((o) => ({
    id: String(o.id),
    tenantUserId: String(o.tenant_user_id),
    email: emails.get(String(o.tenant_user_id)) ?? null,
    qty: asInt(o.qty),
    billingCycle: String(o.billing_cycle),
    amountIqd: asInt(o.amount_iqd),
    createdAt: String(o.created_at),
  }));
}

export async function creditWaWallet(opts: {
  tenantUserId: string;
  qty: number;
  billingCycle: "monthly" | "annual";
  createdBy: string;
  reason?: string;
  paymentRef?: string;
}): Promise<{ lotId: string | null }> {
  const db = getSupabaseAdmin();
  const { data, error } = await db.rpc("wa_wallet_credit_lot", {
    p_tenant: opts.tenantUserId,
    p_qty: opts.qty,
    p_billing_cycle: opts.billingCycle,
    p_reason: opts.reason ?? "admin_adjust",
    p_created_by: opts.createdBy,
    p_payment_ref: opts.paymentRef ?? null,
    p_idempotency_key: `admin_credit:${opts.tenantUserId}:${Date.now()}`,
  });
  if (error) throw error;
  return { lotId: data ? String(data) : null };
}

export async function confirmWaPackOrder(opts: {
  orderId: string;
  decidedBy: string;
}): Promise<{ ok: boolean; error?: string }> {
  const db = getSupabaseAdmin();
  const { data: order, error } = await db
    .from("wa_message_pack_orders")
    .select("*")
    .eq("id", opts.orderId)
    .maybeSingle();
  if (error) throw error;
  if (!order) return { ok: false, error: "الطلب غير موجود" };
  if (order.status !== "pending_payment") {
    return { ok: false, error: "الطلب ليس بانتظار الدفع" };
  }

  const tenant = String(order.tenant_user_id);
  const qty = asInt(order.qty);
  const cycle = order.billing_cycle === "annual" ? "annual" : "monthly";

  let subscriptionId: string | null = null;
  if (cycle === "annual") {
    const starts = new Date();
    const ends = new Date(starts);
    ends.setMonth(ends.getMonth() + 12);
    const next = new Date(starts);
    next.setMonth(next.getMonth() + 1);
    const { data: sub, error: subErr } = await db
      .from("wa_message_subscriptions")
      .insert({
        tenant_user_id: tenant,
        qty,
        yearly_pay_iqd: asInt(order.amount_iqd),
        starts_at: starts.toISOString(),
        ends_at: ends.toISOString(),
        months_credited: 1,
        next_credit_at: next.toISOString(),
        status: "active",
        created_by: opts.decidedBy,
      })
      .select("id")
      .single();
    if (subErr) throw subErr;
    subscriptionId = String(sub.id);
  }

  const { error: creditErr } = await db.rpc("wa_wallet_credit_lot", {
    p_tenant: tenant,
    p_qty: qty,
    p_billing_cycle: cycle,
    p_reason: cycle === "annual" ? "subscription_credit" : "purchase",
    p_created_by: opts.decidedBy,
    p_subscription_id: subscriptionId,
    p_payment_ref: opts.orderId,
    p_idempotency_key: `order_credit:${opts.orderId}`,
  });
  if (creditErr) throw creditErr;

  const { error: updErr } = await db
    .from("wa_message_pack_orders")
    .update({
      status: "credited",
      decided_at: new Date().toISOString(),
      decided_by: opts.decidedBy,
      subscription_id: subscriptionId,
    })
    .eq("id", opts.orderId);
  if (updErr) throw updErr;

  return { ok: true };
}

export async function setWaWalletFlags(opts: {
  tenantUserId: string;
  frozen?: boolean;
  sendBlocked?: boolean;
  walletExempt?: boolean;
  notesAdmin?: string | null;
}): Promise<void> {
  const db = getSupabaseAdmin();
  await db.rpc("wa_wallet_ensure", { p_tenant: opts.tenantUserId });
  const patch: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };
  if (opts.frozen !== undefined) patch.frozen = opts.frozen;
  if (opts.sendBlocked !== undefined) patch.send_blocked = opts.sendBlocked;
  if (opts.walletExempt !== undefined) patch.wallet_exempt = opts.walletExempt;
  if (opts.notesAdmin !== undefined) patch.notes_admin = opts.notesAdmin;
  const { error } = await db
    .from("wa_message_wallet")
    .update(patch)
    .eq("tenant_user_id", opts.tenantUserId);
  if (error) throw error;
}
