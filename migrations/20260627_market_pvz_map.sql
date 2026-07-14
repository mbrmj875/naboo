-- Naboo Market — PVZ map: إحداثيات Pilot + صلاحية التاجر لتحديث نقطة الاستلام
-- Run AFTER 20260620_market_mock_seed.sql

UPDATE marketplace_stores
SET
  pickup_latitude = 30.5085,
  pickup_longitude = 47.7835
WHERE id = '00000000-0000-0000-0000-000000000001';

UPDATE marketplace_stores
SET
  pickup_latitude = 30.5060,
  pickup_longitude = 47.7810
WHERE id = '00000000-0000-0000-0000-000000000002';

CREATE INDEX IF NOT EXISTS idx_marketplace_stores_pickup_map
  ON marketplace_stores (is_pickup_point, is_published)
  WHERE pickup_latitude IS NOT NULL AND pickup_longitude IS NOT NULL;

DROP POLICY IF EXISTS "Merchants can update linked store pickup." ON marketplace_stores;

CREATE POLICY "Merchants can update linked store pickup."
  ON marketplace_stores
  FOR UPDATE
  TO authenticated
  USING (
    tenant_uuid IS NOT NULL
    AND tenant_uuid::text = public.app_current_tenant_id()
  )
  WITH CHECK (
    tenant_uuid IS NOT NULL
    AND tenant_uuid::text = public.app_current_tenant_id()
  );
