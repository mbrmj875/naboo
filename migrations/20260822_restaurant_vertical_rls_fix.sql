-- Fix remaining RLS policies after partial apply of 20260822_restaurant_vertical.sql

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
