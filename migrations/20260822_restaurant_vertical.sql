-- ============================================================================
-- Migration: 20260822_restaurant_vertical.sql
-- Restaurant OS cloud schema (Phase 4) — idempotent.
-- Requires: public.app_current_tenant_id() from 20260507_rls_tenant.sql
--
-- Conflict note: local SQLite uses INTEGER tenant_id; cloud uses tenant_uuid TEXT
-- matching the rest of Naboo. Slugs resolve tenant_uuid for public QR.
-- ============================================================================

-- ── Slug registry (public QR) ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.restaurant_tenant_slugs (
  tenant_uuid TEXT PRIMARY KEY,
  tenant_slug TEXT NOT NULL UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Stock micro levels (cloud BOM; Core products table is local-only) ─────
CREATE TABLE IF NOT EXISTS public.restaurant_stock_levels (
  tenant_uuid        TEXT NOT NULL,
  product_id         BIGINT NOT NULL,
  name_ar            TEXT,
  on_hand_qty_micro  BIGINT NOT NULL DEFAULT 0,
  unit_cost_fils     INTEGER NOT NULL DEFAULT 0,
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_uuid, product_id)
);

-- ── Rate limiter ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.restaurant_rate_limits (
  id           BIGSERIAL PRIMARY KEY,
  bucket_key   TEXT NOT NULL,
  window_start TIMESTAMPTZ NOT NULL,
  hit_count    INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX IF NOT EXISTS idx_restaurant_rate_limits_bucket
  ON public.restaurant_rate_limits (bucket_key, window_start DESC);

-- ── Core restaurant tables (BIGINT ids for sync with local) ───────────────
CREATE TABLE IF NOT EXISTS public.restaurant_floors (
  id          BIGSERIAL PRIMARY KEY,
  tenant_uuid TEXT NOT NULL,
  name_ar     TEXT NOT NULL,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  deleted_at  TIMESTAMPTZ,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.restaurant_tables (
  id           BIGSERIAL PRIMARY KEY,
  tenant_uuid  TEXT NOT NULL,
  floor_id     BIGINT REFERENCES public.restaurant_floors(id),
  table_number TEXT NOT NULL,
  capacity     INTEGER,
  table_slug   TEXT NOT NULL,
  session_seq  INTEGER NOT NULL DEFAULT 0,
  deleted_at   TIMESTAMPTZ,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_restaurant_tables_slug
  ON public.restaurant_tables (tenant_uuid, table_slug)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.restaurant_billing_drafts (
  id          BIGSERIAL PRIMARY KEY,
  tenant_uuid TEXT NOT NULL,
  total_fils  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.restaurant_sessions (
  id                  BIGSERIAL PRIMARY KEY,
  tenant_uuid         TEXT NOT NULL,
  table_id            BIGINT REFERENCES public.restaurant_tables(id),
  session_seq         INTEGER NOT NULL DEFAULT 0,
  channel             TEXT NOT NULL CHECK (channel IN ('qr_table','public_link','cashier')),
  state               TEXT NOT NULL CHECK (state IN ('open','awaiting_payment','closed')),
  invoice_id          BIGINT NOT NULL REFERENCES public.restaurant_billing_drafts(id),
  opened_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at           TIMESTAMPTZ,
  client_fingerprint  TEXT,
  deleted_at          TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_restaurant_sessions_active
  ON public.restaurant_sessions (tenant_uuid, table_id)
  WHERE state IN ('open','awaiting_payment')
    AND deleted_at IS NULL
    AND table_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.restaurant_menu_categories (
  id          BIGSERIAL PRIMARY KEY,
  tenant_uuid TEXT NOT NULL,
  name_ar     TEXT NOT NULL,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  deleted_at  TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.restaurant_menu_items (
  id                   BIGSERIAL PRIMARY KEY,
  tenant_uuid          TEXT NOT NULL,
  category_id          BIGINT REFERENCES public.restaurant_menu_categories(id),
  name_ar              TEXT NOT NULL,
  description_ar       TEXT,
  price_fils           INTEGER NOT NULL CHECK (price_fils >= 0),
  image_url            TEXT,
  is_available         BOOLEAN NOT NULL DEFAULT false,
  channels_json        JSONB NOT NULL DEFAULT '["qr_table","public_link","cashier"]'::jsonb,
  direct_stock_sku_id  BIGINT,
  sort_order           INTEGER NOT NULL DEFAULT 0,
  deleted_at           TIMESTAMPTZ,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_restaurant_menu_items_public
  ON public.restaurant_menu_items (tenant_uuid, is_available)
  WHERE deleted_at IS NULL AND is_available = true;

CREATE TABLE IF NOT EXISTS public.restaurant_menu_item_images (
  id            BIGSERIAL PRIMARY KEY,
  tenant_uuid   TEXT NOT NULL,
  menu_item_id  BIGINT NOT NULL REFERENCES public.restaurant_menu_items(id),
  image_url     TEXT NOT NULL,
  variants_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  is_primary    BOOLEAN NOT NULL DEFAULT false,
  width_px      INTEGER,
  height_px     INTEGER,
  bytes         INTEGER,
  mime          TEXT NOT NULL DEFAULT 'image/jpeg',
  alt_ar        TEXT,
  alt_en        TEXT,
  deleted_at    TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_menu_item_primary_image
  ON public.restaurant_menu_item_images (tenant_uuid, menu_item_id)
  WHERE is_primary = true AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.restaurant_recipes (
  id           BIGSERIAL PRIMARY KEY,
  tenant_uuid  TEXT NOT NULL,
  menu_item_id BIGINT NOT NULL,
  yield_qty    INTEGER NOT NULL DEFAULT 1,
  notes_ar     TEXT,
  deleted_at   TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_restaurant_recipes_item
  ON public.restaurant_recipes (tenant_uuid, menu_item_id)
  WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.restaurant_recipe_lines (
  id          BIGSERIAL PRIMARY KEY,
  recipe_id   BIGINT NOT NULL REFERENCES public.restaurant_recipes(id),
  product_id  BIGINT NOT NULL,
  base_unit   TEXT NOT NULL CHECK (base_unit IN ('g','ml','piece')),
  qty_micro   BIGINT NOT NULL CHECK (qty_micro > 0),
  is_critical BOOLEAN NOT NULL DEFAULT true,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  deleted_at  TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.restaurant_orders (
  id                   BIGSERIAL PRIMARY KEY,
  tenant_uuid          TEXT NOT NULL,
  session_id           BIGINT NOT NULL REFERENCES public.restaurant_sessions(id),
  invoice_id           BIGINT NOT NULL,
  channel              TEXT NOT NULL,
  state                TEXT NOT NULL CHECK (state IN ('new','accepted','preparing','ready','served','voided')),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at          TIMESTAMPTZ,
  preparing_at         TIMESTAMPTZ,
  ready_at             TIMESTAMPTZ,
  served_at            TIMESTAMPTZ,
  notes_ar             TEXT,
  client_generated_id  TEXT,
  deleted_at           TIMESTAMPTZ
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_restaurant_orders_client_gen
  ON public.restaurant_orders (tenant_uuid, client_generated_id)
  WHERE client_generated_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_restaurant_orders_state
  ON public.restaurant_orders (tenant_uuid, state, created_at);

CREATE TABLE IF NOT EXISTS public.restaurant_order_lines (
  id                      BIGSERIAL PRIMARY KEY,
  order_id                BIGINT NOT NULL REFERENCES public.restaurant_orders(id),
  menu_item_id            BIGINT NOT NULL,
  qty                     INTEGER NOT NULL CHECK (qty > 0),
  unit_price_fils_at_sale INTEGER NOT NULL,
  modifiers_json          JSONB,
  line_state              TEXT NOT NULL DEFAULT 'active'
    CHECK (line_state IN ('active','voided_stock_shortfall','voided_by_cashier')),
  void_reason_ar          TEXT,
  notes_ar                TEXT,
  deleted_at              TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.restaurant_ingredient_reservations (
  id                 BIGSERIAL PRIMARY KEY,
  tenant_uuid        TEXT NOT NULL,
  order_id           BIGINT NOT NULL,
  session_id         BIGINT NOT NULL,
  product_id         BIGINT NOT NULL,
  qty_micro_reserved BIGINT NOT NULL,
  state              TEXT NOT NULL CHECK (state IN ('reserved','consumed','released')),
  reserved_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_restaurant_reservations_product
  ON public.restaurant_ingredient_reservations (tenant_uuid, product_id, state);

CREATE TABLE IF NOT EXISTS public.restaurant_order_line_costs (
  id                      BIGSERIAL PRIMARY KEY,
  order_line_id           BIGINT NOT NULL,
  product_id              BIGINT NOT NULL,
  base_unit               TEXT NOT NULL,
  qty_micro               BIGINT NOT NULL,
  unit_cost_fils_at_sale  INTEGER NOT NULL,
  total_cost_fils_at_sale INTEGER NOT NULL,
  consumed_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.restaurant_menu_theme (
  id                    BIGSERIAL PRIMARY KEY,
  tenant_uuid           TEXT NOT NULL UNIQUE,
  draft_json            JSONB NOT NULL,
  published_json        JSONB,
  draft_version         INTEGER NOT NULL DEFAULT 0,
  published_version     INTEGER NOT NULL DEFAULT 0,
  menu_content_version  INTEGER NOT NULL DEFAULT 0,
  published_at          TIMESTAMPTZ,
  published_by          TEXT,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by            TEXT,
  deleted_at            TIMESTAMPTZ
);

-- ── Trigger: order.invoice_id must equal session.invoice_id ───────────────
CREATE OR REPLACE FUNCTION public.restaurant_order_invoice_matches_session()
RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  v_session_invoice BIGINT;
BEGIN
  SELECT invoice_id INTO v_session_invoice
  FROM public.restaurant_sessions
  WHERE id = NEW.session_id;
  IF v_session_invoice IS NULL OR NEW.invoice_id <> v_session_invoice THEN
    RAISE EXCEPTION 'order.invoice_id must equal session.invoice_id';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_restaurant_order_invoice_match ON public.restaurant_orders;
CREATE TRIGGER trg_restaurant_order_invoice_match
  BEFORE INSERT OR UPDATE OF invoice_id, session_id ON public.restaurant_orders
  FOR EACH ROW EXECUTE FUNCTION public.restaurant_order_invoice_matches_session();

-- ── RPC: atomic reserve (spec §8.2) ───────────────────────────────────────
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

  INSERT INTO public.restaurant_ingredient_reservations
    (tenant_uuid, order_id, session_id, product_id, qty_micro_reserved, state, reserved_at)
  SELECT p_tenant, p_order_id, p_session_id,
         (i->>'product_id')::BIGINT,
         (i->>'qty_micro_needed')::BIGINT,
         'reserved',
         now()
  FROM jsonb_array_elements(p_items) i;

  RETURN jsonb_build_object('ok', true);
END $$;

REVOKE ALL ON FUNCTION public.restaurant_reserve_ingredients(TEXT, BIGINT, BIGINT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.restaurant_reserve_ingredients(TEXT, BIGINT, BIGINT, JSONB) TO service_role;

-- ── Rate limit helper ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.restaurant_rate_limit_hit(
  p_bucket TEXT,
  p_window_seconds INTEGER,
  p_max_hits INTEGER
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start TIMESTAMPTZ := date_trunc('second', now())
    - make_interval(secs => (EXTRACT(EPOCH FROM now())::BIGINT % p_window_seconds));
  v_count INTEGER;
BEGIN
  SELECT hit_count INTO v_count
  FROM public.restaurant_rate_limits
  WHERE bucket_key = p_bucket AND window_start = v_start
  FOR UPDATE;

  IF v_count IS NULL THEN
    INSERT INTO public.restaurant_rate_limits (bucket_key, window_start, hit_count)
    VALUES (p_bucket, v_start, 1);
    RETURN true;
  END IF;

  IF v_count >= p_max_hits THEN
    RETURN false;
  END IF;

  UPDATE public.restaurant_rate_limits
  SET hit_count = hit_count + 1
  WHERE bucket_key = p_bucket AND window_start = v_start;
  RETURN true;
END $$;

GRANT EXECUTE ON FUNCTION public.restaurant_rate_limit_hit(TEXT, INTEGER, INTEGER) TO service_role;

-- ── RLS ───────────────────────────────────────────────────────────────────
ALTER TABLE public.restaurant_tenant_slugs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_stock_levels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_floors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_billing_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_menu_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_menu_item_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_recipe_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_ingredient_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_order_line_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_menu_theme ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_rate_limits ENABLE ROW LEVEL SECURITY;

-- Public read: available menu items (anon)
DROP POLICY IF EXISTS restaurant_menu_items_public_select ON public.restaurant_menu_items;
CREATE POLICY restaurant_menu_items_public_select
  ON public.restaurant_menu_items FOR SELECT
  TO anon, authenticated
  USING (is_available = true AND deleted_at IS NULL);

DROP POLICY IF EXISTS restaurant_menu_categories_public_select ON public.restaurant_menu_categories;
CREATE POLICY restaurant_menu_categories_public_select
  ON public.restaurant_menu_categories FOR SELECT
  TO anon, authenticated
  USING (is_active = true AND deleted_at IS NULL);

DROP POLICY IF EXISTS restaurant_menu_images_public_select ON public.restaurant_menu_item_images;
CREATE POLICY restaurant_menu_images_public_select
  ON public.restaurant_menu_item_images FOR SELECT
  TO anon, authenticated
  USING (deleted_at IS NULL);

DROP POLICY IF EXISTS restaurant_menu_theme_public_select ON public.restaurant_menu_theme;
CREATE POLICY restaurant_menu_theme_public_select
  ON public.restaurant_menu_theme FOR SELECT
  TO anon, authenticated
  USING (deleted_at IS NULL AND published_json IS NOT NULL);

DROP POLICY IF EXISTS restaurant_tenant_slugs_public_select ON public.restaurant_tenant_slugs;
CREATE POLICY restaurant_tenant_slugs_public_select
  ON public.restaurant_tenant_slugs FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS restaurant_tables_public_select ON public.restaurant_tables;
CREATE POLICY restaurant_tables_public_select
  ON public.restaurant_tables FOR SELECT
  TO anon, authenticated
  USING (deleted_at IS NULL);

-- Tenant JWT read/write for merchant app tables that carry tenant_uuid
DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'restaurant_floors','restaurant_tables','restaurant_sessions',
    'restaurant_menu_categories','restaurant_menu_items','restaurant_menu_item_images',
    'restaurant_recipes','restaurant_orders',
    'restaurant_ingredient_reservations',
    'restaurant_menu_theme','restaurant_stock_levels',
    'restaurant_billing_drafts'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I_tenant_all ON public.%I', t, t);
    EXECUTE format(
      'CREATE POLICY %I_tenant_all ON public.%I FOR ALL TO authenticated
       USING (tenant_uuid = public.app_current_tenant_id())
       WITH CHECK (tenant_uuid = public.app_current_tenant_id())',
      t, t
    );
  END LOOP;
END $$;

-- Child tables without tenant_uuid — scope via parent join
DROP POLICY IF EXISTS restaurant_recipe_lines_tenant_all ON public.restaurant_recipe_lines;
CREATE POLICY restaurant_recipe_lines_tenant_all
  ON public.restaurant_recipe_lines FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurant_recipes r
      WHERE r.id = recipe_id AND r.tenant_uuid = public.app_current_tenant_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.restaurant_recipes r
      WHERE r.id = recipe_id AND r.tenant_uuid = public.app_current_tenant_id()
    )
  );

DROP POLICY IF EXISTS restaurant_order_lines_tenant_all ON public.restaurant_order_lines;
CREATE POLICY restaurant_order_lines_tenant_all
  ON public.restaurant_order_lines FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurant_orders o
      WHERE o.id = order_id AND o.tenant_uuid = public.app_current_tenant_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.restaurant_orders o
      WHERE o.id = order_id AND o.tenant_uuid = public.app_current_tenant_id()
    )
  );

DROP POLICY IF EXISTS restaurant_order_line_costs_tenant_all ON public.restaurant_order_line_costs;
CREATE POLICY restaurant_order_line_costs_tenant_all
  ON public.restaurant_order_line_costs FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurant_order_lines l
      JOIN public.restaurant_orders o ON o.id = l.order_id
      WHERE l.id = order_line_id AND o.tenant_uuid = public.app_current_tenant_id()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.restaurant_order_lines l
      JOIN public.restaurant_orders o ON o.id = l.order_id
      WHERE l.id = order_line_id AND o.tenant_uuid = public.app_current_tenant_id()
    )
  );

-- Realtime publication (best effort)
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_orders;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_sessions;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_menu_theme;
EXCEPTION WHEN duplicate_object THEN NULL; WHEN undefined_object THEN NULL;
END $$;
