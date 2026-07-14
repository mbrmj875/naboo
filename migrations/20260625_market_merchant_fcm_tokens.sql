-- FCM device tokens for marketplace order push notifications (ERP merchant).

CREATE TABLE IF NOT EXISTS marketplace_merchant_fcm_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_uuid UUID NOT NULL,
  device_token TEXT NOT NULL,
  platform TEXT DEFAULT 'unknown',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_uuid, device_token)
);

CREATE INDEX IF NOT EXISTS idx_mmft_tenant ON marketplace_merchant_fcm_tokens (tenant_uuid);

ALTER TABLE marketplace_merchant_fcm_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Merchants manage their FCM tokens" ON marketplace_merchant_fcm_tokens;

CREATE POLICY "Merchants manage their FCM tokens"
  ON marketplace_merchant_fcm_tokens
  FOR ALL
  TO authenticated
  USING (tenant_uuid::text = public.app_current_tenant_id())
  WITH CHECK (tenant_uuid::text = public.app_current_tenant_id());
