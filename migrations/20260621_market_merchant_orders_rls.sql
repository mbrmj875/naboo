-- Naboo Market — merchant order management (ERP Phase 2)
-- Run AFTER 20260620_market_pilot.sql and 20260620_market_customers_rls.sql

-- Merchants can UPDATE order status for their linked stores
DROP POLICY IF EXISTS "Merchants can update their orders." ON marketplace_orders;
CREATE POLICY "Merchants can update their orders."
ON marketplace_orders FOR UPDATE
TO authenticated
USING (
  seller_store_id IN (
    SELECT ms.id
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
)
WITH CHECK (
  seller_store_id IN (
    SELECT ms.id
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
);

-- Merchants can read line items for their orders
DROP POLICY IF EXISTS "Merchants can view their order items." ON marketplace_order_items;
CREATE POLICY "Merchants can view their order items."
ON marketplace_order_items FOR SELECT
TO authenticated
USING (
  order_id IN (
    SELECT o.id
    FROM marketplace_orders o
    WHERE o.seller_store_id IN (
      SELECT ms.id
      FROM marketplace_stores ms
      WHERE ms.tenant_uuid IS NOT NULL
        AND ms.tenant_uuid::text = public.app_current_tenant_id()
    )
  )
);

-- Pilot: merchant claims an unlinked published store (sets tenant_uuid = auth user)
DROP POLICY IF EXISTS "Merchants can claim unlinked store (pilot)." ON marketplace_stores;
CREATE POLICY "Merchants can claim unlinked store (pilot)."
ON marketplace_stores FOR UPDATE
TO authenticated
USING (is_published = true AND tenant_uuid IS NULL)
WITH CHECK (tenant_uuid::text = public.app_current_tenant_id());

-- Merchant reads stores linked to their account (including after claim)
DROP POLICY IF EXISTS "Merchants can view linked stores." ON marketplace_stores;
CREATE POLICY "Merchants can view linked stores."
ON marketplace_stores FOR SELECT
TO authenticated
USING (
  tenant_uuid IS NOT NULL
  AND tenant_uuid::text = public.app_current_tenant_id()
);

-- List unlinked published stores so ERP can show claim UI (pilot)
DROP POLICY IF EXISTS "Merchants can list claimable stores (pilot)." ON marketplace_stores;
CREATE POLICY "Merchants can list claimable stores (pilot)."
ON marketplace_stores FOR SELECT
TO authenticated
USING (is_published = true AND tenant_uuid IS NULL);
