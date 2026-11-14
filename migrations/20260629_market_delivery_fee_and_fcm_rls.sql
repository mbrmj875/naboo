-- Delivery fee per store + FCM token RLS aligned to auth.uid()

ALTER TABLE marketplace_stores
  ADD COLUMN IF NOT EXISTS delivery_fee_fils INTEGER NOT NULL DEFAULT 3000;

DROP POLICY IF EXISTS "Merchants manage their FCM tokens" ON marketplace_merchant_fcm_tokens;

CREATE POLICY "Merchants manage their FCM tokens"
  ON marketplace_merchant_fcm_tokens
  FOR ALL
  TO authenticated
  USING (tenant_uuid = auth.uid())
  WITH CHECK (tenant_uuid = auth.uid());

COMMENT ON COLUMN marketplace_stores.delivery_fee_fils IS
  'COD pickup/delivery fee in fils shown at Market checkout';

CREATE OR REPLACE VIEW marketplace_stores_public AS
SELECT
  id, name, slug, description, logo_url,
  neighborhood_label, is_pickup_point,
  pickup_address, pickup_latitude, pickup_longitude,
  pickup_hours, delivery_fee_fils
FROM marketplace_stores
WHERE is_published = true;
