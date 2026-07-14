-- Naboo Market — real stock quantity from ERP catalog sync
-- Run after marketplace_products exists.

ALTER TABLE marketplace_products
  ADD COLUMN IF NOT EXISTS stock_quantity NUMERIC NOT NULL DEFAULT 0
  CHECK (stock_quantity >= 0);

CREATE INDEX IF NOT EXISTS idx_mp_stock_available
  ON marketplace_products(store_id, in_stock, stock_quantity)
  WHERE is_published = true;

CREATE OR REPLACE FUNCTION public.marketplace_validate_order_item_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock NUMERIC;
  v_in_stock BOOLEAN;
BEGIN
  IF NEW.product_global_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT stock_quantity, in_stock
  INTO v_stock, v_in_stock
  FROM marketplace_products
  WHERE product_global_id = NEW.product_global_id
  LIMIT 1;

  IF FOUND AND (v_in_stock IS NOT TRUE OR NEW.quantity > v_stock) THEN
    RAISE EXCEPTION 'stock_exceeded';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_marketplace_order_item_stock
  ON marketplace_order_items;
CREATE TRIGGER trg_marketplace_order_item_stock
BEFORE INSERT OR UPDATE ON marketplace_order_items
FOR EACH ROW
EXECUTE FUNCTION public.marketplace_validate_order_item_stock();
