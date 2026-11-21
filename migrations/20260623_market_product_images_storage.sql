-- Naboo Market — product images in Supabase Storage (compressed JPEG from ERP)
-- Run AFTER 20260622_market_catalog_sync.sql

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'marketplace-product-images',
  'marketplace-product-images',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Public read for catalog display
DROP POLICY IF EXISTS "Public read marketplace product images" ON storage.objects;
CREATE POLICY "Public read marketplace product images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'marketplace-product-images');

-- Merchants upload into their store folder: {store_uuid}/{product_global_id}.jpg
DROP POLICY IF EXISTS "Merchants upload product images" ON storage.objects;
CREATE POLICY "Merchants upload product images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'marketplace-product-images'
  AND (storage.foldername(name))[1] IN (
    SELECT ms.id::text
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
);

DROP POLICY IF EXISTS "Merchants update product images" ON storage.objects;
CREATE POLICY "Merchants update product images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'marketplace-product-images'
  AND (storage.foldername(name))[1] IN (
    SELECT ms.id::text
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
)
WITH CHECK (
  bucket_id = 'marketplace-product-images'
  AND (storage.foldername(name))[1] IN (
    SELECT ms.id::text
    FROM marketplace_stores ms
    WHERE ms.tenant_uuid IS NOT NULL
      AND ms.tenant_uuid::text = public.app_current_tenant_id()
  )
);
