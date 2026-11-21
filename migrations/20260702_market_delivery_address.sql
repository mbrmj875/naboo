ALTER TABLE public.marketplace_orders
ADD COLUMN IF NOT EXISTS delivery_address TEXT;

ALTER TABLE public.marketplace_customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Buyers can view own customer profile" ON public.marketplace_customers;
CREATE POLICY "Buyers can view own customer profile"
ON public.marketplace_customers
FOR SELECT
TO authenticated
USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS "Buyers can insert own customer profile" ON public.marketplace_customers;
CREATE POLICY "Buyers can insert own customer profile"
ON public.marketplace_customers
FOR INSERT
TO authenticated
WITH CHECK (auth_user_id = auth.uid());

DROP POLICY IF EXISTS "Buyers can update own customer profile" ON public.marketplace_customers;
CREATE POLICY "Buyers can update own customer profile"
ON public.marketplace_customers
FOR UPDATE
TO authenticated
USING (auth_user_id = auth.uid())
WITH CHECK (auth_user_id = auth.uid());
