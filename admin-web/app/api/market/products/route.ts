import { NextResponse } from "next/server";
import { getSupabaseAdmin } from "@/lib/supabase-admin";

export async function GET() {
  try {
    const sb = getSupabaseAdmin();
    const { data, error } = await sb
      .from("marketplace_products")
      .select("*, marketplace_stores(name)")
      .order("created_at", { ascending: false })
      .limit(200);
    if (error) throw error;
    return NextResponse.json({ products: data ?? [] });
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
      .from("marketplace_products")
      .insert({
        store_id: body.store_id,
        product_global_id: body.product_global_id,
        name: body.name,
        description: body.description ?? null,
        category_id: body.category_id ?? "uncategorized",
        category_name: body.category_name ?? null,
        brand_name: body.brand_name ?? null,
        price_fils: body.price_fils,
        images: body.images ?? [],
        in_stock: body.in_stock ?? true,
        is_published: body.is_published ?? true,
      })
      .select()
      .single();
    if (error) throw error;
    return NextResponse.json({ product: data });
  } catch (e) {
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "failed" },
      { status: 500 },
    );
  }
}
