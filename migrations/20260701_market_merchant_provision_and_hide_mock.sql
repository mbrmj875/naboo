-- Naboo Market: إخفاء mock التجريبي + إنشاء متجر تاجر + RLS بـ auth.uid()
-- يعمل حتى لو لم تُشغَّل 20260629 (يضيف الأعمدة الناقصة تلقائياً)

ALTER TABLE marketplace_stores
  ADD COLUMN IF NOT EXISTS delivery_fee_fils INTEGER NOT NULL DEFAULT 3000;

-- 1) العرض العام: متاجر مربوطة بتاجر فقط (لا pilot mock بدون tenant)
CREATE OR REPLACE VIEW marketplace_stores_public AS
SELECT
  id, name, slug, description, logo_url,
  neighborhood_label, is_pickup_point,
  pickup_address, pickup_latitude, pickup_longitude,
  pickup_hours, delivery_fee_fils
FROM marketplace_stores
WHERE is_published = true
  AND tenant_uuid IS NOT NULL;

-- 2) إخفاء بذور التطوير إن بقيت غير مربوطة
UPDATE marketplace_stores
SET is_published = false, updated_at = now()
WHERE tenant_uuid IS NULL
  AND slug IN ('al-noor-market', 'al-salam-grocery');

UPDATE marketplace_products
SET is_published = false, in_stock = false, updated_at = now()
WHERE product_global_id LIKE 'MOCK-%';

-- 3) RPC: إنشاء متجر للتاجر الحالي (مرة واحدة)
CREATE OR REPLACE FUNCTION public.marketplace_provision_store(
  p_name TEXT,
  p_slug TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
  v_slug TEXT;
  v_name TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT id INTO v_id
  FROM marketplace_stores
  WHERE tenant_uuid = auth.uid()
  LIMIT 1;

  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  v_name := NULLIF(TRIM(p_name), '');
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'store name required';
  END IF;

  v_slug := NULLIF(TRIM(p_slug), '');
  IF v_slug IS NULL THEN
    v_slug := 'store-' || LEFT(REPLACE(auth.uid()::text, '-', ''), 12);
  END IF;

  INSERT INTO marketplace_stores (
    tenant_uuid, name, slug, description,
    neighborhood_label, location_type,
    is_published, is_pickup_point,
    commission_rate_bps, pilot_started_at
  )
  VALUES (
    auth.uid(),
    v_name,
    v_slug,
    v_name,
    'العشار',
    'commercial',
    true,
    false,
    0,
    CURRENT_DATE
  )
  ON CONFLICT (slug) DO UPDATE
  SET
    tenant_uuid = EXCLUDED.tenant_uuid,
    name = EXCLUDED.name,
    is_published = true,
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.marketplace_provision_store(TEXT, TEXT) TO authenticated;

-- 4) RLS كتالوج: tenant المتجر = auth.uid() (ليس tenant_id محلي ERP)
DROP POLICY IF EXISTS "Merchants can insert their products." ON marketplace_products;
CREATE POLICY "Merchants can insert their products."
ON marketplace_products FOR INSERT
TO authenticated
WITH CHECK (
  store_id IN (
    SELECT ms.id
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid = auth.uid()
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
    WHERE ms.tenant_uuid = auth.uid()
  )
)
WITH CHECK (
  store_id IN (
    SELECT ms.id
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid = auth.uid()
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
    WHERE ms.tenant_uuid = auth.uid()
  )
);
