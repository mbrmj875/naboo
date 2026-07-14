import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

export async function GET(req: Request) {
  try {
    const url = new URL(req.url);
    const status = url.searchParams.get("status");
    const sb = getSupabaseAdmin();
    let query = sb
      .from("marketplace_orders")
      .select(
        "id, order_number, status, total_fils, payment_method, created_at, seller_store_id",
      )
      .order("created_at", { ascending: false })
      .limit(100);
    if (status) {
      query = query.eq("status", status);
    }
    const { data, error } = await query;
    if (error) throw error;
    return NextResponse.json({ orders: data ?? [] });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "failed" },
      { status: 500 },
    );
  }
}

export async function PATCH(req: Request) {
  try {
    const body = await req.json();
    const { order_id, status } = body as { order_id: string; status: string };
    if (!order_id || !status) {
      return NextResponse.json({ error: "order_id and status required" }, { status: 400 });
    }
    const sb = getSupabaseAdmin();
    const extra: Record<string, string> = {};
    if (status === "delivered") {
      extra.delivered_at = new Date().toISOString();
    }
    if (status === "accepted") {
      extra.accepted_at = new Date().toISOString();
    }
    const { data, error } = await sb
      .from("marketplace_orders")
      .update({ status, ...extra })
      .eq("id", order_id)
      .select()
      .single();
    if (error) throw error;
    return NextResponse.json({ order: data });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "failed" },
      { status: 500 },
    );
  }
}
