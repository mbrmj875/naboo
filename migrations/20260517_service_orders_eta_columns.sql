-- ETA للتذاكر: مدة متوقعة + موعد تسليم مقترح (مزامنة Supabase الاختيارية).

alter table public.service_orders
  add column if not exists expected_duration_minutes integer;

alter table public.service_orders
  add column if not exists promised_delivery_at timestamptz;

alter table public.service_orders
  add column if not exists work_started_at timestamptz;
