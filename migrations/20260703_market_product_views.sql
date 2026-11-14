CREATE TABLE IF NOT EXISTS public.marketplace_product_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.marketplace_products(id) ON DELETE CASCADE,
  product_name TEXT NOT NULL,
  price_fils INTEGER NOT NULL DEFAULT 0,
  image_url TEXT,
  store_id UUID REFERENCES public.marketplace_stores(id) ON DELETE SET NULL,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (auth_user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_marketplace_product_views_user_time
ON public.marketplace_product_views(auth_user_id, viewed_at DESC);

ALTER TABLE public.marketplace_product_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Buyers can view own product views" ON public.marketplace_product_views;
CREATE POLICY "Buyers can view own product views"
ON public.marketplace_product_views
FOR SELECT
TO authenticated
USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS "Buyers can insert own product views" ON public.marketplace_product_views;
CREATE POLICY "Buyers can insert own product views"
ON public.marketplace_product_views
FOR INSERT
TO authenticated
WITH CHECK (auth_user_id = auth.uid());

DROP POLICY IF EXISTS "Buyers can delete own product views" ON public.marketplace_product_views;
CREATE POLICY "Buyers can delete own product views"
ON public.marketplace_product_views
FOR DELETE
TO authenticated
USING (auth_user_id = auth.uid());
