-- Enable Realtime for marketplace catalog + orders (idempotent).

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'marketplace_products'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE marketplace_products;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'marketplace_orders'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE marketplace_orders;
  END IF;
END $$;
