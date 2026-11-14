import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

export async function GET() {
  try {
    const sb = getSupabaseAdmin();
    const { data, error } = await sb
      .from("marketplace_stores")
      .select("*")
      .order("created_at", { ascending: false });
    if (error) throw error;
    return NextResponse.json({ stores: data ?? [] });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "failed" },
      { status: 500 },
    );
  }
}

export async function POST(req: Request) {
  try {
    const body = await req.json();
    const sb = getSupabaseAdmin();
    const { data, error } = await sb
      .from("marketplace_stores")
      .insert({
        name: body.name,
        slug: body.slug,
        neighborhood_label: body.neighborhood_label ?? "العشار",
        pickup_address: body.pickup_address ?? null,
        internal_address: body.internal_address ?? null,
        is_published: body.is_published ?? true,
        is_pickup_point: body.is_pickup_point ?? false,
        tenant_uuid: body.tenant_uuid ?? null,
        commission_rate_bps: 0,
      })
      .select()
      .single();
    if (error) throw error;
    return NextResponse.json({ store: data });
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
    const { store_id, tenant_uuid, is_published } = body as {
      store_id: string;
      tenant_uuid?: string | null;
      is_published?: boolean;
    };
    if (!store_id) {
      return NextResponse.json({ error: "store_id required" }, { status: 400 });
    }
    const sb = getSupabaseAdmin();
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (tenant_uuid !== undefined) patch.tenant_uuid = tenant_uuid;
    if (is_published !== undefined) patch.is_published = is_published;

    const { data, error } = await sb
      .from("marketplace_stores")
      .update(patch)
      .eq("id", store_id)
      .select()
      .single();
    if (error) throw error;
    return NextResponse.json({ store: data });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "failed" },
      { status: 500 },
    );
  }
}
