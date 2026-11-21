-- Fix marketplace store claim: auth.uid() + is_published + RPC for ERP Pilot

CREATE OR REPLACE FUNCTION public.marketplace_claim_store(p_store_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  UPDATE marketplace_stores
  SET
    tenant_uuid = auth.uid(),
    is_published = true,
    updated_at = now()
  WHERE id = p_store_id
    AND tenant_uuid IS NULL
    AND is_published = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'store not claimable';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.marketplace_claim_store(uuid) TO authenticated;

DROP POLICY IF EXISTS "Merchants can view linked stores." ON marketplace_stores;
CREATE POLICY "Merchants can view linked stores."
  ON marketplace_stores FOR SELECT
  TO authenticated
  USING (tenant_uuid = auth.uid());

DROP POLICY IF EXISTS "Merchants can update linked store pickup." ON marketplace_stores;
CREATE POLICY "Merchants can update linked store pickup."
  ON marketplace_stores FOR UPDATE
  TO authenticated
  USING (tenant_uuid = auth.uid())
  WITH CHECK (tenant_uuid = auth.uid());

DROP POLICY IF EXISTS "Merchants can claim unlinked store (pilot)." ON marketplace_stores;
CREATE POLICY "Merchants can claim unlinked store (pilot)."
  ON marketplace_stores FOR UPDATE
  TO authenticated
  USING (is_published = true AND tenant_uuid IS NULL)
  WITH CHECK (tenant_uuid = auth.uid());
