-- Naboo Market — تقييمات المنتجات والمتاجر + وسائط المتجر (غلاف/معرض) + تقييم مجمّع
-- يعمل بعد 20260701_market_merchant_provision_and_hide_mock.sql
-- المتجر مربوط بالتاجر عبر tenant_uuid = auth.uid()
-- المشتري مربوط عبر marketplace_customers.auth_user_id = auth.uid()

-- =========================================================================
-- 1) أعمدة وسائط المتجر + التقييم المجمّع
-- =========================================================================
ALTER TABLE marketplace_stores
  ADD COLUMN IF NOT EXISTS cover_url    TEXT,
  ADD COLUMN IF NOT EXISTS gallery      TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS rating_avg   NUMERIC(2,1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rating_count INTEGER NOT NULL DEFAULT 0;

ALTER TABLE marketplace_products
  ADD COLUMN IF NOT EXISTS rating_avg   NUMERIC(2,1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS rating_count INTEGER NOT NULL DEFAULT 0;

-- =========================================================================
-- 2) إعادة تعريف العرض العام: + غلاف/معرض/تقييم + عدد المنتجات
-- ملاحظة: CREATE OR REPLACE VIEW لا يسمح بإعادة ترتيب الأعمدة الموجودة،
-- لذا نُبقي ترتيب 20260701 كما هو ونُلحِق الأعمدة الجديدة في النهاية فقط.
-- =========================================================================
CREATE OR REPLACE VIEW marketplace_stores_public AS
SELECT
  s.id, s.name, s.slug, s.description, s.logo_url,
  s.neighborhood_label, s.is_pickup_point,
  s.pickup_address, s.pickup_latitude, s.pickup_longitude,
  s.pickup_hours, s.delivery_fee_fils,
  -- أعمدة جديدة (مُلحَقة في النهاية)
  s.cover_url, s.gallery,
  s.rating_avg, s.rating_count,
  (
    SELECT count(*)
    FROM marketplace_products p
    WHERE p.store_id = s.id AND p.is_published = true
  ) AS product_count
FROM marketplace_stores s
WHERE s.is_published = true
  AND s.tenant_uuid IS NOT NULL;

-- =========================================================================
-- 3) سياسات المتجر: التاجر يقرأ/يحدّث متجره (tenant_uuid = auth.uid())
-- =========================================================================
DROP POLICY IF EXISTS "Merchants view their store" ON marketplace_stores;
CREATE POLICY "Merchants view their store"
ON marketplace_stores FOR SELECT
TO authenticated
USING (tenant_uuid = auth.uid());

DROP POLICY IF EXISTS "Merchants update their store" ON marketplace_stores;
CREATE POLICY "Merchants update their store"
ON marketplace_stores FOR UPDATE
TO authenticated
USING (tenant_uuid = auth.uid())
WITH CHECK (tenant_uuid = auth.uid());

-- =========================================================================
-- 4) جدول تقييمات المنتج (نجوم + تعليق) — موثّق بالشراء
-- =========================================================================
CREATE TABLE IF NOT EXISTS marketplace_product_reviews (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_global_id TEXT NOT NULL,
  store_id          UUID REFERENCES marketplace_stores(id),
  buyer_id          UUID REFERENCES marketplace_customers(id),
  order_id          UUID REFERENCES marketplace_orders(id),
  rating            INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment           TEXT,
  author_name       TEXT,
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now(),
  UNIQUE (buyer_id, product_global_id)
);
CREATE INDEX IF NOT EXISTS idx_mp_product_reviews_gid
  ON marketplace_product_reviews(product_global_id);

-- =========================================================================
-- 5) جدول تقييمات المتجر (تجربة المتجر) — موثّق بطلب مكتمل
-- =========================================================================
CREATE TABLE IF NOT EXISTS marketplace_store_reviews (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  store_id    UUID NOT NULL REFERENCES marketplace_stores(id),
  buyer_id    UUID REFERENCES marketplace_customers(id),
  order_id    UUID REFERENCES marketplace_orders(id),
  rating      INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment     TEXT,
  author_name TEXT,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE (buyer_id, store_id)
);
CREATE INDEX IF NOT EXISTS idx_mp_store_reviews_store
  ON marketplace_store_reviews(store_id);

-- =========================================================================
-- 6) RLS — قراءة عامة، كتابة موثّقة بالشراء، تعديل/حذف للمالك
-- =========================================================================
ALTER TABLE marketplace_product_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE marketplace_store_reviews   ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON marketplace_product_reviews TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON marketplace_product_reviews TO authenticated;
GRANT SELECT ON marketplace_store_reviews TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON marketplace_store_reviews TO authenticated;

-- قراءة عامة
DROP POLICY IF EXISTS "Public read product reviews" ON marketplace_product_reviews;
CREATE POLICY "Public read product reviews"
ON marketplace_product_reviews FOR SELECT
TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS "Public read store reviews" ON marketplace_store_reviews;
CREATE POLICY "Public read store reviews"
ON marketplace_store_reviews FOR SELECT
TO anon, authenticated
USING (true);

-- إدراج تقييم المنتج: فقط لمشترٍ لديه طلب delivered يحوي المنتج
DROP POLICY IF EXISTS "Buyers review purchased products" ON marketplace_product_reviews;
CREATE POLICY "Buyers review purchased products"
ON marketplace_product_reviews FOR INSERT
TO authenticated
WITH CHECK (
  buyer_id IN (
    SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()
  )
  AND EXISTS (
    SELECT 1
    FROM marketplace_order_items oi
    JOIN marketplace_orders o ON o.id = oi.order_id
    WHERE oi.product_global_id = marketplace_product_reviews.product_global_id
      AND o.status = 'delivered'
      AND o.buyer_id IN (
        SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()
      )
  )
);

-- إدراج تقييم المتجر: فقط لمشترٍ لديه طلب delivered من هذا المتجر
DROP POLICY IF EXISTS "Buyers review purchased stores" ON marketplace_store_reviews;
CREATE POLICY "Buyers review purchased stores"
ON marketplace_store_reviews FOR INSERT
TO authenticated
WITH CHECK (
  buyer_id IN (
    SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()
  )
  AND EXISTS (
    SELECT 1
    FROM marketplace_orders o
    WHERE o.seller_store_id = marketplace_store_reviews.store_id
      AND o.status = 'delivered'
      AND o.buyer_id IN (
        SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()
      )
  )
);

-- تعديل/حذف: المالك فقط
DROP POLICY IF EXISTS "Buyers manage their product reviews" ON marketplace_product_reviews;
CREATE POLICY "Buyers manage their product reviews"
ON marketplace_product_reviews FOR UPDATE
TO authenticated
USING (buyer_id IN (SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()))
WITH CHECK (buyer_id IN (SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "Buyers delete their product reviews" ON marketplace_product_reviews;
CREATE POLICY "Buyers delete their product reviews"
ON marketplace_product_reviews FOR DELETE
TO authenticated
USING (buyer_id IN (SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "Buyers manage their store reviews" ON marketplace_store_reviews;
CREATE POLICY "Buyers manage their store reviews"
ON marketplace_store_reviews FOR UPDATE
TO authenticated
USING (buyer_id IN (SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()))
WITH CHECK (buyer_id IN (SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "Buyers delete their store reviews" ON marketplace_store_reviews;
CREATE POLICY "Buyers delete their store reviews"
ON marketplace_store_reviews FOR DELETE
TO authenticated
USING (buyer_id IN (SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()));

-- =========================================================================
-- 7) Triggers — إعادة حساب rating_avg/rating_count عند أي تغيير
-- =========================================================================
CREATE OR REPLACE FUNCTION public.mp_refresh_product_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gid TEXT := COALESCE(NEW.product_global_id, OLD.product_global_id);
BEGIN
  UPDATE marketplace_products p
  SET rating_avg = COALESCE(sub.avg, 0),
      rating_count = COALESCE(sub.cnt, 0),
      updated_at = now()
  FROM (
    SELECT ROUND(AVG(rating)::numeric, 1) AS avg, COUNT(*) AS cnt
    FROM marketplace_product_reviews
    WHERE product_global_id = v_gid
  ) sub
  WHERE p.product_global_id = v_gid;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_mp_product_rating ON marketplace_product_reviews;
CREATE TRIGGER trg_mp_product_rating
AFTER INSERT OR UPDATE OR DELETE ON marketplace_product_reviews
FOR EACH ROW EXECUTE FUNCTION public.mp_refresh_product_rating();

CREATE OR REPLACE FUNCTION public.mp_refresh_store_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_store UUID := COALESCE(NEW.store_id, OLD.store_id);
BEGIN
  UPDATE marketplace_stores s
  SET rating_avg = COALESCE(sub.avg, 0),
      rating_count = COALESCE(sub.cnt, 0),
      updated_at = now()
  FROM (
    SELECT ROUND(AVG(rating)::numeric, 1) AS avg, COUNT(*) AS cnt
    FROM marketplace_store_reviews
    WHERE store_id = v_store
  ) sub
  WHERE s.id = v_store;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_mp_store_rating ON marketplace_store_reviews;
CREATE TRIGGER trg_mp_store_rating
AFTER INSERT OR UPDATE OR DELETE ON marketplace_store_reviews
FOR EACH ROW EXECUTE FUNCTION public.mp_refresh_store_rating();

-- =========================================================================
-- 8) Storage: bucket صور المتجر (شعار/غلاف/معرض) — مسار {store_id}/...
-- =========================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'marketplace-store-images',
  'marketplace-store-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Public read store images" ON storage.objects;
CREATE POLICY "Public read store images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'marketplace-store-images');

DROP POLICY IF EXISTS "Merchants upload store images" ON storage.objects;
CREATE POLICY "Merchants upload store images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'marketplace-store-images'
  AND (storage.foldername(name))[1] IN (
    SELECT ms.id::text FROM marketplace_stores ms WHERE ms.tenant_uuid = auth.uid()
  )
);

DROP POLICY IF EXISTS "Merchants update store images" ON storage.objects;
CREATE POLICY "Merchants update store images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'marketplace-store-images'
  AND (storage.foldername(name))[1] IN (
    SELECT ms.id::text FROM marketplace_stores ms WHERE ms.tenant_uuid = auth.uid()
  )
)
WITH CHECK (
  bucket_id = 'marketplace-store-images'
  AND (storage.foldername(name))[1] IN (
    SELECT ms.id::text FROM marketplace_stores ms WHERE ms.tenant_uuid = auth.uid()
  )
);

DROP POLICY IF EXISTS "Merchants delete store images" ON storage.objects;
CREATE POLICY "Merchants delete store images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'marketplace-store-images'
  AND (storage.foldername(name))[1] IN (
    SELECT ms.id::text FROM marketplace_stores ms WHERE ms.tenant_uuid = auth.uid()
  )
);
