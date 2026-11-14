-- Naboo Market — RLS for marketplace_customers (Pilot Phase 1)
-- Run AFTER 20260620_market_pilot.sql
-- Allows authenticated buyers to create/read/update their own customer row.

DROP POLICY IF EXISTS "Buyers can view own customer profile" ON marketplace_customers;
CREATE POLICY "Buyers can view own customer profile"
ON marketplace_customers FOR SELECT
TO authenticated
USING (auth_user_id = auth.uid());

DROP POLICY IF EXISTS "Buyers can insert own customer profile" ON marketplace_customers;
CREATE POLICY "Buyers can insert own customer profile"
ON marketplace_customers FOR INSERT
TO authenticated
WITH CHECK (auth_user_id = auth.uid());

DROP POLICY IF EXISTS "Buyers can update own customer profile" ON marketplace_customers;
CREATE POLICY "Buyers can update own customer profile"
ON marketplace_customers FOR UPDATE
TO authenticated
USING (auth_user_id = auth.uid())
WITH CHECK (auth_user_id = auth.uid());
