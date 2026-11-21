-- Migration for Naboo Market MVP (Pilot)
-- Run FIRST in Supabase SQL Editor, then 20260620_market_mock_seed.sql
-- Requires: public.app_current_tenant_id() from migrations/20260507_rls_tenant.sql

CREATE TABLE IF NOT EXISTS marketplace_neighborhoods (
  id          TEXT PRIMARY KEY,  -- 'ashar'
  name_ar     TEXT NOT NULL,
  city        TEXT NOT NULL DEFAULT 'basra',
  is_active   BOOLEAN DEFAULT true
);

INSERT INTO marketplace_neighborhoods (id, name_ar) 
VALUES ('ashar', 'العشار')
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS marketplace_stores (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_uuid         UUID,
  name                TEXT NOT NULL,
  slug                TEXT UNIQUE NOT NULL,
  description         TEXT,
  logo_url            TEXT,
  neighborhood_label  TEXT,
  internal_address    TEXT,          -- ops only - RLS prevents public read
  location_type       TEXT DEFAULT 'commercial',
  pickup_address      TEXT,
  pickup_latitude     DOUBLE PRECISION,
  pickup_longitude    DOUBLE PRECISION,
  is_published        BOOLEAN DEFAULT false,
  is_pickup_point     BOOLEAN DEFAULT false,
  pickup_hours        JSONB,
  commission_rate_bps INTEGER DEFAULT 0,  -- Pilot: 0 first 30 days
  pilot_started_at    DATE,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS marketplace_products (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id            UUID NOT NULL REFERENCES marketplace_stores(id),
  product_global_id   TEXT UNIQUE,
  name                TEXT NOT NULL,
  description         TEXT,
  category_id         TEXT,
  price_fils          INTEGER NOT NULL CHECK (price_fils >= 0),
  images              TEXT[] DEFAULT '{}',
  in_stock            BOOLEAN DEFAULT true,
  is_published        BOOLEAN DEFAULT true,
  sort_order          INTEGER DEFAULT 0,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mp_pub ON marketplace_products(store_id, is_published)
  WHERE is_published = true;

CREATE TABLE IF NOT EXISTS marketplace_customers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id    UUID UNIQUE REFERENCES auth.users(id),
  phone           TEXT UNIQUE NOT NULL,
  display_name    TEXT,
  neighborhood_id TEXT REFERENCES marketplace_neighborhoods(id),
  default_pickup_store_id UUID REFERENCES marketplace_stores(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);

DO $$ BEGIN
  CREATE TYPE marketplace_order_status AS ENUM (
    'pending', 'accepted', 'ready_to_ship', 'in_transit',
    'at_pickup_point', 'delivered', 'cancelled'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS marketplace_orders (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number        TEXT UNIQUE NOT NULL,
  buyer_id            UUID REFERENCES marketplace_customers(id),
  seller_store_id     UUID NOT NULL REFERENCES marketplace_stores(id),
  pickup_store_id     UUID NOT NULL REFERENCES marketplace_stores(id),
  status              marketplace_order_status NOT NULL DEFAULT 'pending',
  payment_method      TEXT NOT NULL DEFAULT 'cod',
  payment_status      TEXT NOT NULL DEFAULT 'pending',
  subtotal_fils       INTEGER NOT NULL,
  delivery_fee_fils   INTEGER NOT NULL DEFAULT 0,
  total_fils          INTEGER NOT NULL,
  commission_fils     INTEGER NOT NULL DEFAULT 0,
  commission_rate_bps INTEGER NOT NULL DEFAULT 0,
  pickup_code         TEXT,
  buyer_notes         TEXT,
  cancelled_at        TIMESTAMPTZ,
  cancel_reason       TEXT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  accepted_at         TIMESTAMPTZ,
  delivered_at        TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS marketplace_order_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id            UUID NOT NULL REFERENCES marketplace_orders(id),
  product_global_id   TEXT,
  product_name        TEXT NOT NULL,
  quantity            NUMERIC NOT NULL CHECK (quantity > 0),
  unit_price_fils     INTEGER NOT NULL,
  line_total_fils     INTEGER NOT NULL
);

CREATE OR REPLACE VIEW marketplace_stores_public AS
SELECT
  id, name, slug, description, logo_url,
  neighborhood_label, is_pickup_point,
  pickup_address, pickup_latitude, pickup_longitude,
  pickup_hours
FROM marketplace_stores
WHERE is_published = true;

-- Basic RLS
ALTER TABLE marketplace_stores ENABLE ROW LEVEL SECURITY;
ALTER TABLE marketplace_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE marketplace_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE marketplace_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE marketplace_order_items ENABLE ROW LEVEL SECURITY;

-- Allow public read for published products
DROP POLICY IF EXISTS "Public profiles are viewable by everyone." ON marketplace_products;
CREATE POLICY "Public profiles are viewable by everyone."
ON marketplace_products FOR SELECT
TO anon, authenticated
USING (is_published = true);

-- Allow public read for published stores (for marketplace_stores_public view)
DROP POLICY IF EXISTS "Public can view published stores" ON marketplace_stores;
CREATE POLICY "Public can view published stores"
ON marketplace_stores FOR SELECT
TO anon, authenticated
USING (is_published = true);

-- Neighborhoods list (onboarding)
ALTER TABLE marketplace_neighborhoods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public can view active neighborhoods" ON marketplace_neighborhoods;
CREATE POLICY "Public can view active neighborhoods"
ON marketplace_neighborhoods FOR SELECT
TO anon, authenticated
USING (is_active = true);

-- Allow authenticated buyers to read their own orders
DROP POLICY IF EXISTS "Buyers can view their own orders." ON marketplace_orders;
CREATE POLICY "Buyers can view their own orders."
ON marketplace_orders FOR SELECT
USING (buyer_id IN (
  SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()
));

-- Merchants: match store tenant_uuid to JWT tenant (app_current_tenant_id from ERP RLS)
-- profiles has no tenant_id column; do not reference it.
DROP POLICY IF EXISTS "Merchants can view their orders." ON marketplace_orders;
CREATE POLICY "Merchants can view their orders."
ON marketplace_orders FOR SELECT
USING (
  seller_store_id IN (
    SELECT ms.id
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
);

-- Allow buyers to insert orders
DROP POLICY IF EXISTS "Buyers can insert orders." ON marketplace_orders;
CREATE POLICY "Buyers can insert orders."
ON marketplace_orders FOR INSERT
WITH CHECK (buyer_id IN (
  SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()
));

-- Allow buyers to insert order items
DROP POLICY IF EXISTS "Buyers can insert order items." ON marketplace_order_items;
CREATE POLICY "Buyers can insert order items."
ON marketplace_order_items FOR INSERT
WITH CHECK (
  order_id IN (
    SELECT id FROM marketplace_orders WHERE buyer_id IN (
      SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()
    )
  )
);
