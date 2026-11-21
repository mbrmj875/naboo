-- restaurant-auto-accept-tick — pg_cron every 15s via pg_net + Vault secrets
-- Idempotent: safe to re-run (unschedule by name, then schedule).
-- Secrets are NOT hardcoded here — upsert via vault using names below before first run:
--   restaurant_project_url, restaurant_anon_key, restaurant_cron_secret

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;

-- One reservation row per (order, product) while reserved — blocks double-reserve races
CREATE UNIQUE INDEX IF NOT EXISTS idx_restaurant_reservations_order_product_active
  ON public.restaurant_ingredient_reservations (order_id, product_id)
  WHERE state = 'reserved';

-- Make reserve idempotent under concurrent ticks
CREATE OR REPLACE FUNCTION public.restaurant_reserve_ingredients(
  p_tenant TEXT,
  p_order_id BIGINT,
  p_session_id BIGINT,
  p_items JSONB
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_item JSONB;
  v_available BIGINT;
  v_shortages JSONB := '[]'::JSONB;
  v_product_id BIGINT;
  v_needed BIGINT;
BEGIN
  -- Already reserved for this order → no-op (concurrent tick lost the race safely)
  IF EXISTS (
    SELECT 1
    FROM public.restaurant_ingredient_reservations r
    WHERE r.order_id = p_order_id
      AND r.state = 'reserved'
  ) THEN
    RETURN jsonb_build_object('ok', true, 'already', true);
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_product_id := (v_item->>'product_id')::BIGINT;
    v_needed := (v_item->>'qty_micro_needed')::BIGINT;

    SELECT s.on_hand_qty_micro
           - COALESCE((
               SELECT SUM(r.qty_micro_reserved)
               FROM public.restaurant_ingredient_reservations r
               WHERE r.product_id = s.product_id
                 AND r.tenant_uuid = s.tenant_uuid
                 AND r.state = 'reserved'
             ), 0)
    INTO v_available
    FROM public.restaurant_stock_levels s
    WHERE s.product_id = v_product_id
      AND s.tenant_uuid = p_tenant
    FOR UPDATE OF s;

    v_available := COALESCE(v_available, 0);

    IF v_available < v_needed THEN
      v_shortages := v_shortages || jsonb_build_object(
        'product_id', v_product_id,
        'available', v_available,
        'requested', v_needed
      );
    END IF;
  END LOOP;

  IF jsonb_array_length(v_shortages) > 0 THEN
    RAISE EXCEPTION 'ingredient_shortage: %', v_shortages USING ERRCODE = 'RSTR1';
  END IF;

  BEGIN
    INSERT INTO public.restaurant_ingredient_reservations
      (tenant_uuid, order_id, session_id, product_id, qty_micro_reserved, state, reserved_at)
    SELECT p_tenant, p_order_id, p_session_id,
           (i->>'product_id')::BIGINT,
           (i->>'qty_micro_needed')::BIGINT,
           'reserved',
           now()
    FROM jsonb_array_elements(p_items) i;
  EXCEPTION
    WHEN unique_violation THEN
      -- Peer tick inserted first
      RETURN jsonb_build_object('ok', true, 'already', true);
  END;

  RETURN jsonb_build_object('ok', true);
END $$;

REVOKE ALL ON FUNCTION public.restaurant_reserve_ingredients(TEXT, BIGINT, BIGINT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restaurant_reserve_ingredients(TEXT, BIGINT, BIGINT, JSONB) TO service_role;

-- CAS helper: only one tick may flip new → accepted
CREATE OR REPLACE FUNCTION public.restaurant_claim_order_accepted(p_order_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id BIGINT;
BEGIN
  UPDATE public.restaurant_orders
  SET state = 'accepted',
      accepted_at = now()
  WHERE id = p_order_id
    AND state = 'new'
    AND deleted_at IS NULL
  RETURNING id INTO v_id;

  RETURN v_id IS NOT NULL;
END $$;

REVOKE ALL ON FUNCTION public.restaurant_claim_order_accepted(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restaurant_claim_order_accepted(BIGINT) TO service_role;

-- Schedule Edge Function (Vault names only — no secret literals in this file)
DO $$
DECLARE
  v_jobid BIGINT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'pg_cron not enabled — skip schedule';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RAISE NOTICE 'pg_net not enabled — skip schedule';
    RETURN;
  END IF;

  -- Drop prior job(s) by name to keep re-apply idempotent
  FOR v_jobid IN
    SELECT jobid FROM cron.job WHERE jobname = 'restaurant-auto-accept-tick'
  LOOP
    PERFORM cron.unschedule(v_jobid);
  END LOOP;

  PERFORM cron.schedule(
    'restaurant-auto-accept-tick',
    '15 seconds',
    $cron$
    SELECT net.http_post(
      url := (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'restaurant_project_url'
        LIMIT 1
      ) || '/functions/v1/restaurant-auto-accept-tick',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'restaurant_anon_key'
          LIMIT 1
        ),
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'restaurant_anon_key'
          LIMIT 1
        ),
        'x-cron-secret', (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'restaurant_cron_secret'
          LIMIT 1
        )
      ),
      body := jsonb_build_object(
        'source', 'pg_cron',
        'job', 'restaurant-auto-accept-tick',
        'ts', now()
      ),
      timeout_milliseconds := 15000
    ) AS request_id;
    $cron$
  );
END $$;
