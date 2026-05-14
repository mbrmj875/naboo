-- ============================================================================
-- Migration: 20260515_service_orders.sql
-- Step X — Service Orders (Job Tickets) + Items (Parts used)
--
-- يُشغَّل يدوياً من Supabase Studio (SQL Editor) كـ superuser.
-- المتطلبات المسبقة:
--   - 20260507_rls_tenant.sql (app_current_tenant_id() + set_tenant_uuid_from_jwt())
--
-- ملاحظات تصميم:
-- - أسماء الأعمدة في Supabase = snake_case
-- - tenant_uuid يُختم من JWT (Trigger) + RLS سياسات العزل
-- - Soft delete عبر deleted_at (بدون hard delete من التطبيق)
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
end $$;

-- ============================================================================
-- 1) service_orders
-- ============================================================================
create table if not exists public.service_orders (
  id                    uuid primary key default gen_random_uuid(),
  tenant_uuid           text not null,
  customer_id           text,
  customer_name_snapshot text not null,
  device_name           text not null,
  device_serial         text,
  service_id            text, -- products.id (is_service=1)
  estimated_price_fils  integer not null default 0,
  agreed_price_fils     integer,
  advance_payment_fils  integer not null default 0,
  status                text not null default 'pending'
                        check(status in ('pending','in_progress','completed','delivered','cancelled')),
  technician_id         text,
  technician_name       text,
  issue_description     text,
  completion_notes      text,
  invoice_id            text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz
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

-- ============================================================================
-- 2) service_order_items
--
-- الربط: order_global_id (UUID للتذكرة الأم) بدلاً من order_id المحلي.
-- ============================================================================
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

