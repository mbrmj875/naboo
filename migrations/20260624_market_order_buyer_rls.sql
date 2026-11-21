-- Buyer can read their order line items + cancel pending orders.
-- Idempotent: safe to re-run if policies already exist.

DROP POLICY IF EXISTS "Buyers can view their order items" ON marketplace_order_items;

CREATE POLICY "Buyers can view their order items"
  ON marketplace_order_items
  FOR SELECT
  TO authenticated
  USING (
    order_id IN (
      SELECT o.id
      FROM marketplace_orders o
      JOIN marketplace_customers c ON c.id = o.buyer_id
      WHERE c.auth_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Buyers can cancel pending orders" ON marketplace_orders;

CREATE POLICY "Buyers can cancel pending orders"
  ON marketplace_orders
  FOR UPDATE
  TO authenticated
  USING (
    buyer_id IN (
      SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()
    )
    AND status = 'pending'
  )
  WITH CHECK (
    buyer_id IN (
      SELECT id FROM marketplace_customers WHERE auth_user_id = auth.uid()
    )
    AND status = 'cancelled'
  );
