-- Naboo Market — ERP catalog sync (Phase 3)
-- Run AFTER 20260621_market_merchant_orders_rls.sql

ALTER TABLE marketplace_products
  ADD COLUMN IF NOT EXISTS brand_id TEXT,
  ADD COLUMN IF NOT EXISTS category_name TEXT,
  ADD COLUMN IF NOT EXISTS brand_name TEXT;

CREATE INDEX IF NOT EXISTS idx_mp_store_category
  ON marketplace_products(store_id, category_id)
  WHERE is_published = true;

CREATE INDEX IF NOT EXISTS idx_mp_store_brand
  ON marketplace_products(store_id, brand_id)
  WHERE is_published = true;

-- Merchants manage catalog for their linked store
DROP POLICY IF EXISTS "Merchants can insert their products." ON marketplace_products;
CREATE POLICY "Merchants can insert their products."
ON marketplace_products FOR INSERT
TO authenticated
WITH CHECK (
  store_id IN (
    SELECT ms.id
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
);

DROP POLICY IF EXISTS "Merchants can update their products." ON marketplace_products;
CREATE POLICY "Merchants can update their products."
ON marketplace_products FOR UPDATE
TO authenticated
USING (
  store_id IN (
    SELECT ms.id
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
)
WITH CHECK (
  store_id IN (
    SELECT ms.id
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
);

DROP POLICY IF EXISTS "Merchants can view all their store products." ON marketplace_products;
CREATE POLICY "Merchants can view all their store products."
ON marketplace_products FOR SELECT
TO authenticated
USING (
  store_id IN (
    SELECT ms.id
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
);
