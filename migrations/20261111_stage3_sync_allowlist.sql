-- المرحلة 3، البند 3.3: قائمة الجداول المسموحة وحد الحجم والدفعة.
-- يبدأ بوضع التسجيل فقط (log): لا يُرفض أي رفع، يُكتب المخالف في جدول خاص.
-- التحويل إلى الرفض لاحقاً بعد أسبوع بلا مخالفات حقيقية:
--   update public.sync_guard_config set mode = 'enforce';
-- القائمة عامة لا حسب التخصص، لأن الحسابات ترفع كل الجداول اليوم
-- (جداول الصيدلية في 23 حساباً والمطعم في 9).
-- القياس يوم 2026-11-11: أكبر لقطة 3,038,621 بايت نصاً، والتطبيق يرسل 50 عملية في الدفعة.
-- الرجوع:
--   drop trigger if exists trg_guard_snapshot_payload on public.app_snapshots;
--   drop function if exists public.fn_guard_snapshot_payload();
--   create or replace function public.rpc_process_sync_queue ... (النسخة السابقة محفوظة في النسخة الاحتياطية 20261111)
--   drop function if exists public.sync_guard_log(text, text, jsonb);
--   drop table if exists public.sync_guard_violations, public.sync_guard_allowed_tables, public.sync_guard_config;

create table if not exists public.sync_guard_config (
  id boolean primary key default true check (id),
  mode text not null default 'log' check (mode in ('log', 'enforce')),
  max_payload_bytes bigint not null default 20000000,
  max_batch_mutations integer not null default 500
);
insert into public.sync_guard_config (id) values (true) on conflict do nothing;

create table if not exists public.sync_guard_allowed_tables (
  table_name text primary key
);
insert into public.sync_guard_allowed_tables (table_name)
select unnest(string_to_array(
  'activity_logs,app_settings,branches,brands,business_audit_events,car_wash_services,cash_ledger,categories,customer_debt_payments,customer_extra_phones,customers,debt_settings,expense_categories,expenses,installment_plans,installment_settings,installments,invoice_items,invoices,loyalty_ledger,loyalty_settings,oil_change_filter_catalog,oil_change_filter_kinds,oil_change_hydraulic_catalog,oil_change_oil_catalog,oil_change_services,oil_change_wa_outbox,parked_sales,pharmacy_batches,pharmacy_customers_ext,pharmacy_dosage_forms,pharmacy_drug_reference,pharmacy_manufacturers,pharmacy_product_profile,pharmacy_recalls,pharmacy_stock_policy,po_receipts,price_list_items,price_lists,print_settings,product_batches,product_colors,product_oil_grades,product_unit_variants,product_variants,products,purchase_order_items,purchase_orders,restaurant_floor_fixtures,restaurant_floors,restaurant_ingredient_reservations,restaurant_item_modifiers,restaurant_menu_categories,restaurant_menu_item_images,restaurant_menu_items,restaurant_menu_theme,restaurant_modifiers,restaurant_order_line_costs,restaurant_order_lines,restaurant_orders,restaurant_recipe_lines,restaurant_recipes,restaurant_sessions,restaurant_tables,role_permissions,service_order_items,service_orders,stock_voucher_items,stock_vouchers,stocktaking_items,stocktaking_sessions,supplier_bills,supplier_payouts,suppliers,tenants,unit_template_conversions,unit_templates,user_permissions,user_profiles,warehouses,work_shifts',
  ','))
on conflict do nothing;

create table if not exists public.sync_guard_violations (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  user_id uuid,
  kind text not null,
  detail jsonb
);
create index if not exists sync_guard_violations_at_idx on public.sync_guard_violations (at);

alter table public.sync_guard_config enable row level security;
alter table public.sync_guard_allowed_tables enable row level security;
alter table public.sync_guard_violations enable row level security;
revoke all on public.sync_guard_config, public.sync_guard_allowed_tables, public.sync_guard_violations
  from anon, authenticated;

-- يكتب المخالفة ويعيد true إن كان الوضع رفضاً. لا يُستدعى من التطبيق مباشرة.
create or replace function public.sync_guard_log(p_kind text, p_detail jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_mode text;
begin
  select mode into v_mode from public.sync_guard_config where id;
  insert into public.sync_guard_violations (user_id, kind, detail)
  values (auth.uid(), p_kind, p_detail);
  return coalesce(v_mode, 'log') = 'enforce';
end;
$$;
revoke all on function public.sync_guard_log(text, jsonb) from public, anon, authenticated;

-- فحص اللقطة قبل كتابتها. rpc_push_snapshot نفسها لا تتغير.
-- في BEFORE لم تُضغط القيمة بعد، فـ pg_column_size قريب من الحجم الفعلي.
create or replace function public.fn_guard_snapshot_payload()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg public.sync_guard_config%rowtype;
  v_size bigint;
  v_unknown text[];
begin
  if new.payload is null then return new; end if;
  if tg_op = 'UPDATE' and new.payload is not distinct from old.payload then return new; end if;
  select * into v_cfg from public.sync_guard_config where id;
  if not found then return new; end if;

  v_size := pg_column_size(new.payload);
  if v_size > v_cfg.max_payload_bytes then
    if public.sync_guard_log('payload_too_large', jsonb_build_object('bytes', v_size)) then
      raise exception 'sync_guard: payload too large (% bytes)', v_size using errcode = 'P0001';
    end if;
  end if;

  if jsonb_typeof(new.payload->'tables') = 'object' then
    select array_agg(k) into v_unknown
      from jsonb_object_keys(new.payload->'tables') k
     where not exists (select 1 from public.sync_guard_allowed_tables a where a.table_name = k);
    if v_unknown is not null then
      if public.sync_guard_log('unknown_tables', jsonb_build_object('tables', to_jsonb(v_unknown))) then
        raise exception 'sync_guard: unknown tables %', v_unknown using errcode = 'P0001';
      end if;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.fn_guard_snapshot_payload() from public, anon, authenticated;

drop trigger if exists trg_guard_snapshot_payload on public.app_snapshots;
create trigger trg_guard_snapshot_payload
  before insert or update of payload on public.app_snapshots
  for each row execute function public.fn_guard_snapshot_payload();

-- حد الدفعة في طابور المزامنة: نفس الدالة السابقة مع فحص الطول بعد حارس JWT.
create or replace function public.rpc_process_sync_queue(mutations_json jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
declare
  v_tenant_uuid text;
  mutation jsonb;
  v_claim text;
  v_mutation_id text;
  v_results jsonb := '[]'::jsonb;
  v_error text;
  v_len integer;
  v_max integer;
begin
  -- (أ) حارس JWT.
  v_tenant_uuid := public.app_current_tenant_id();
  if v_tenant_uuid is null or v_tenant_uuid = '' then
    raise exception 'tenant_unauthenticated: refusing sync without authenticated tenant'
      using errcode = 'P0001';
  end if;

  -- مصفوفة فارغة أو NULL ⇒ نُرجع [] فوراً.
  if mutations_json is null or jsonb_typeof(mutations_json) <> 'array' then
    return '[]'::jsonb;
  end if;

  -- البند 3.3: حد طول الدفعة (التطبيق يرسل 50).
  v_len := jsonb_array_length(mutations_json);
  select max_batch_mutations into v_max from public.sync_guard_config where id;
  if v_max is not null and v_len > v_max then
    if public.sync_guard_log('batch_too_long', jsonb_build_object('mutations', v_len)) then
      raise exception 'sync_guard: batch too long (% mutations)', v_len using errcode = 'P0001';
    end if;
  end if;

  -- (ب) فحص cross-tenant على كامل الباتش — أيّ تباين يُلغي الكلّ.
  for mutation in select * from jsonb_array_elements(mutations_json)
  loop
    v_claim := nullif(mutation->>'tenant_uuid', '');
    if v_claim is not null and v_claim is distinct from v_tenant_uuid then
      raise exception
        'tenant_mismatch: client claimed tenant_uuid=% but JWT yields %',
        v_claim, v_tenant_uuid
        using errcode = 'P0001';
    end if;
  end loop;

  -- (ج) معالجة لكلّ mutation: clock-skew guard ثم legacy.
  for mutation in select * from jsonb_array_elements(mutations_json)
  loop
    v_mutation_id := mutation->>'_mutation_id';

    begin
      perform public._reject_clock_skew(mutation);
      perform public._rpc_process_sync_queue_legacy(jsonb_build_array(mutation));

      v_results := v_results || jsonb_build_object(
        'mutation_id', v_mutation_id,
        'status',      'ok',
        'error',       null
      );
    exception when others then
      v_error := SQLERRM;
      v_results := v_results || jsonb_build_object(
        'mutation_id', v_mutation_id,
        'status',      'fail',
        'error',       v_error
      );
    end;
  end loop;

  return v_results;
end;
$function$;

-- حذف المخالفات الأقدم من 30 يوماً.
select cron.schedule('sync-guard-violations-cleanup', '15 21 * * *',
  $$delete from public.sync_guard_violations where at < now() - interval '30 days'$$);
