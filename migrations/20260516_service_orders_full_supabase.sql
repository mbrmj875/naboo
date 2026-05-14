-- ============================================================================
-- Unified apply file (Supabase Studio)
-- 20260516_service_orders_full_supabase.sql
--
-- Contains:
--   1) service_orders + service_order_items tables (+ indexes + trigger + RLS)
--   2) RPC legacy extension to support:
--        entity_type = service_order / service_order_item
--      (delegates other types to _rpc_process_sync_queue_legacy_base)
--
-- Run as: Supabase Studio → SQL Editor → (superuser)
-- ============================================================================

-- ============================================================================
-- 0) Preconditions (hard fail with clear messages)
-- ============================================================================
do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'app_current_tenant_id'
  ) then
    raise exception
      'Missing app_current_tenant_id(). Run 20260507_rls_tenant.sql first.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'set_tenant_uuid_from_jwt'
  ) then
    raise exception
      'Missing set_tenant_uuid_from_jwt(). Run 20260507_rls_tenant.sql first.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_process_sync_queue'
  ) then
    raise exception
      'Missing rpc_process_sync_queue(jsonb). Run 20260508_rpc_per_mutation.sql first.'
      using errcode = 'P0001';
  end if;
end $$;

-- ============================================================================
-- 1) Tables: service_orders + service_order_items (snake_case)
-- ============================================================================

create table if not exists public.service_orders (
  id                     uuid primary key default gen_random_uuid(),
  tenant_uuid            text not null,
  customer_id            text,
  customer_name_snapshot text not null,
  device_name            text not null,
  device_serial          text,
  service_id             text, -- products.id (is_service=1)
  estimated_price_fils   integer not null default 0,
  agreed_price_fils      integer,
  advance_payment_fils   integer not null default 0,
  status                 text not null default 'pending'
                         check(status in ('pending','in_progress','completed','delivered','cancelled')),
  technician_id          text,
  technician_name        text,
  issue_description      text,
  completion_notes       text,
  invoice_id             text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  deleted_at             timestamptz
);

create index if not exists idx_service_orders_lookup
  on public.service_orders(tenant_uuid, deleted_at, status);

create index if not exists idx_service_orders_customer_lookup
  on public.service_orders(tenant_uuid, deleted_at, customer_id);

create index if not exists idx_service_orders_invoice_lookup
  on public.service_orders(tenant_uuid, invoice_id);

drop trigger if exists trg_service_orders_set_tenant on public.service_orders;
create trigger trg_service_orders_set_tenant
  before insert on public.service_orders
  for each row
  execute function public.set_tenant_uuid_from_jwt();

alter table public.service_orders enable row level security;
alter table public.service_orders force row level security;

drop policy if exists service_orders_select_own on public.service_orders;
create policy service_orders_select_own
  on public.service_orders for select
  using (tenant_uuid = public.app_current_tenant_id());

drop policy if exists service_orders_insert_own on public.service_orders;
create policy service_orders_insert_own
  on public.service_orders for insert
  with check (tenant_uuid = public.app_current_tenant_id());

drop policy if exists service_orders_update_own on public.service_orders;
create policy service_orders_update_own
  on public.service_orders for update
  using (tenant_uuid = public.app_current_tenant_id())
  with check (tenant_uuid = public.app_current_tenant_id());

drop policy if exists service_orders_delete_own on public.service_orders;
create policy service_orders_delete_own
  on public.service_orders for delete
  using (tenant_uuid = public.app_current_tenant_id());

-- ────────────────────────────────────────────────────────────────────────────

create table if not exists public.service_order_items (
  id              uuid primary key default gen_random_uuid(),
  tenant_uuid     text not null,
  order_global_id uuid not null,
  product_id      text not null, -- products.id
  product_name    text not null,
  quantity        integer not null default 1,
  price_fils      integer not null default 0,
  total_fils      integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

create index if not exists idx_service_order_items_lookup
  on public.service_order_items(tenant_uuid, deleted_at, order_global_id);

create index if not exists idx_service_order_items_product_stats
  on public.service_order_items(tenant_uuid, deleted_at, product_id);

drop trigger if exists trg_service_order_items_set_tenant on public.service_order_items;
create trigger trg_service_order_items_set_tenant
  before insert on public.service_order_items
  for each row
  execute function public.set_tenant_uuid_from_jwt();

alter table public.service_order_items enable row level security;
alter table public.service_order_items force row level security;

drop policy if exists service_order_items_select_own on public.service_order_items;
create policy service_order_items_select_own
  on public.service_order_items for select
  using (tenant_uuid = public.app_current_tenant_id());

drop policy if exists service_order_items_insert_own on public.service_order_items;
create policy service_order_items_insert_own
  on public.service_order_items for insert
  with check (
    tenant_uuid = public.app_current_tenant_id()
    and exists (
      select 1
      from public.service_orders o
      where o.tenant_uuid = public.app_current_tenant_id()
        and o.id = service_order_items.order_global_id
        and o.deleted_at is null
    )
  );

drop policy if exists service_order_items_update_own on public.service_order_items;
create policy service_order_items_update_own
  on public.service_order_items for update
  using (tenant_uuid = public.app_current_tenant_id())
  with check (
    tenant_uuid = public.app_current_tenant_id()
    and exists (
      select 1
      from public.service_orders o
      where o.tenant_uuid = public.app_current_tenant_id()
        and o.id = service_order_items.order_global_id
        and o.deleted_at is null
    )
  );

drop policy if exists service_order_items_delete_own on public.service_order_items;
create policy service_order_items_delete_own
  on public.service_order_items for delete
  using (tenant_uuid = public.app_current_tenant_id());

-- ============================================================================
-- 2) Extend legacy RPC to support service_order/service_order_item
-- ============================================================================

-- Ensure we have a base legacy function to delegate to.
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = '_rpc_process_sync_queue_legacy'
  )
  and not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = '_rpc_process_sync_queue_legacy_base'
  ) then
    execute 'alter function public._rpc_process_sync_queue_legacy(jsonb)
             rename to _rpc_process_sync_queue_legacy_base';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = '_rpc_process_sync_queue_legacy_base'
  ) then
    raise exception
      'Missing _rpc_process_sync_queue_legacy_base(jsonb). Run 20260514_rpc_product_variants_sync.sql (or equivalent legacy wrapper) first.'
      using errcode = 'P0001';
  end if;
end $$;

create or replace function public._rpc_process_sync_queue_legacy(mutations_json jsonb)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_tenant_uuid text;
  mutation jsonb;
  e_type text;
  op text;
begin
  v_tenant_uuid := public.app_current_tenant_id();
  if v_tenant_uuid is null or v_tenant_uuid = '' then
    raise exception 'tenant_unauthenticated' using errcode = 'P0001';
  end if;

  if mutations_json is null or jsonb_typeof(mutations_json) <> 'array' then
    return;
  end if;

  for mutation in select * from jsonb_array_elements(mutations_json)
  loop
    e_type := lower(coalesce(mutation->>'_entity_type', ''));
    op := upper(coalesce(mutation->>'_operation', ''));

    -- ── service_order ──────────────────────────────────────────────────────
    if e_type = 'service_order' then
      if op not in ('INSERT','UPDATE','DELETE') then
        continue;
      end if;

      insert into public.service_orders(
        id,
        tenant_uuid,
        customer_id,
        customer_name_snapshot,
        device_name,
        device_serial,
        service_id,
        estimated_price_fils,
        agreed_price_fils,
        advance_payment_fils,
        status,
        technician_id,
        technician_name,
        issue_description,
        completion_notes,
        invoice_id,
        updated_at,
        deleted_at
      ) values (
        (mutation->>'id')::uuid,
        v_tenant_uuid,
        nullif(trim(coalesce(mutation->>'customer_id', mutation->>'customerId')), ''),
        coalesce(
          nullif(trim(coalesce(mutation->>'customer_name_snapshot', mutation->>'customerNameSnapshot')), ''),
          'عميل'
        ),
        coalesce(
          nullif(trim(coalesce(mutation->>'device_name', mutation->>'deviceName')), ''),
          'جهاز'
        ),
        nullif(trim(coalesce(mutation->>'device_serial', mutation->>'deviceSerial')), ''),
        nullif(trim(coalesce(mutation->>'service_id', mutation->>'serviceId')), ''),
        coalesce((coalesce(mutation->>'estimated_price_fils', mutation->>'estimatedPriceFils'))::int, 0),
        nullif(coalesce(mutation->>'agreed_price_fils', mutation->>'agreedPriceFils'), '')::int,
        coalesce((coalesce(mutation->>'advance_payment_fils', mutation->>'advancePaymentFils'))::int, 0),
        coalesce(nullif(trim(mutation->>'status'), ''), 'pending'),
        nullif(trim(coalesce(mutation->>'technician_id', mutation->>'technicianId')), ''),
        nullif(trim(coalesce(mutation->>'technician_name', mutation->>'technicianName')), ''),
        nullif(trim(coalesce(mutation->>'issue_description', mutation->>'issueDescription')), ''),
        nullif(trim(coalesce(mutation->>'completion_notes', mutation->>'completionNotes')), ''),
        nullif(trim(coalesce(mutation->>'invoice_id', mutation->>'invoiceId')), ''),
        now(),
        case when op = 'DELETE' then now() else null end
      )
      on conflict (id) do update set
        customer_id = excluded.customer_id,
        customer_name_snapshot = excluded.customer_name_snapshot,
        device_name = excluded.device_name,
        device_serial = excluded.device_serial,
        service_id = excluded.service_id,
        estimated_price_fils = excluded.estimated_price_fils,
        agreed_price_fils = excluded.agreed_price_fils,
        advance_payment_fils = excluded.advance_payment_fils,
        status = excluded.status,
        technician_id = excluded.technician_id,
        technician_name = excluded.technician_name,
        issue_description = excluded.issue_description,
        completion_notes = excluded.completion_notes,
        invoice_id = excluded.invoice_id,
        updated_at = now(),
        deleted_at = case when op = 'DELETE' then now() else null end
      where public.service_orders.tenant_uuid = v_tenant_uuid;

      continue;
    end if;

    -- ── service_order_item ─────────────────────────────────────────────────
    if e_type = 'service_order_item' then
      if op not in ('INSERT','UPDATE','DELETE') then
        continue;
      end if;

      insert into public.service_order_items(
        id,
        tenant_uuid,
        order_global_id,
        product_id,
        product_name,
        quantity,
        price_fils,
        total_fils,
        updated_at,
        deleted_at
      ) values (
        (mutation->>'id')::uuid,
        v_tenant_uuid,
        (coalesce(mutation->>'order_global_id', mutation->>'orderGlobalId'))::uuid,
        coalesce(mutation->>'product_id', mutation->>'productId'),
        coalesce(
          nullif(trim(coalesce(mutation->>'product_name', mutation->>'productName')), ''),
          'منتج'
        ),
        coalesce((coalesce(mutation->>'quantity', '1'))::int, 1),
        coalesce((coalesce(mutation->>'price_fils', mutation->>'priceFils'))::int, 0),
        coalesce((coalesce(mutation->>'total_fils', mutation->>'totalFils'))::int, 0),
        now(),
        case when op = 'DELETE' then now() else null end
      )
      on conflict (id) do update set
        order_global_id = excluded.order_global_id,
        product_id = excluded.product_id,
        product_name = excluded.product_name,
        quantity = excluded.quantity,
        price_fils = excluded.price_fils,
        total_fils = excluded.total_fils,
        updated_at = now(),
        deleted_at = case when op = 'DELETE' then now() else null end
      where public.service_order_items.tenant_uuid = v_tenant_uuid;

      continue;
    end if;

    -- باقي الكيانات: فوّض إلى النسخة الأساسية.
    perform public._rpc_process_sync_queue_legacy_base(jsonb_build_array(mutation));
  end loop;
end;
$$;

comment on function public._rpc_process_sync_queue_legacy(jsonb) is
  'Extends legacy sync RPC to support service_order/service_order_item mutations, '
  'then delegates other entity types to _rpc_process_sync_queue_legacy_base.';

