import 'dart:io';

void main() {
  final f = File('supabase_sync_queue_rpc.sql');
  var content = f.readAsStringSync();
  
  if (content.contains('CREATE TABLE IF NOT EXISTS public.installment_plans')) {
    print('already added');
    return;
  }
  
  final tables = '''
-- 15. Financial Obligations (Phase 5.5)
CREATE TABLE IF NOT EXISTS public.installment_plans (
  global_id text PRIMARY KEY,
  invoice_global_id text,
  customer_global_id text,
  customer_name text,
  total_amount numeric,
  paid_amount numeric,
  number_of_installments integer,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.installments (
  global_id text PRIMARY KEY,
  plan_global_id text REFERENCES public.installment_plans(global_id) ON DELETE CASCADE,
  due_date timestamptz,
  amount numeric,
  paid integer,
  paid_date timestamptz,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.customer_debt_payments (
  global_id text PRIMARY KEY,
  customer_global_id text REFERENCES public.customers(global_id),
  customer_name_snapshot text NOT NULL,
  amount numeric NOT NULL,
  debt_before numeric NOT NULL,
  debt_after numeric NOT NULL,
  created_at timestamptz NOT NULL,
  created_by_user_name text,
  note text,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.supplier_bills (
  global_id text PRIMARY KEY,
  supplier_global_id text REFERENCES public.suppliers(global_id),
  their_reference text,
  their_bill_date timestamptz,
  amount numeric NOT NULL,
  note text,
  image_path text,
  created_at timestamptz NOT NULL,
  created_by_user_name text,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.supplier_payouts (
  global_id text PRIMARY KEY,
  supplier_global_id text REFERENCES public.suppliers(global_id),
  amount numeric NOT NULL,
  note text,
  created_at timestamptz NOT NULL,
  created_by_user_name text,
  affects_cash integer NOT NULL DEFAULT 1,
  receipt_invoice_id integer,
  updated_at timestamptz DEFAULT now()
);

''';

  content = content.replaceFirst(
    "CREATE OR REPLACE FUNCTION rpc_process_sync_queue",
    tables + "CREATE OR REPLACE FUNCTION rpc_process_sync_queue"
  );
  
  f.writeAsStringSync(content);
  print('Added SQL tables');
}
