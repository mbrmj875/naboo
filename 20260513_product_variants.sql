-- ============================================================================
-- Migration: 20260513_product_variants.sql
-- Step X — product_colors + product_variants (Variants للملابس)
--
-- يُشغَّل يدوياً من Supabase Studio (SQL Editor) كـ superuser.
-- المتطلبات المسبقة:
--   - 20260507_rls_tenant.sql (app_current_tenant_id() + set_tenant_uuid_from_jwt())
--
-- الهدف:
--   - ألوان داخل المنتج + Variants (لون + مقاس) مع مخزون مستقل
--   - RLS: tenant isolation (SELECT/INSERT/UPDATE/DELETE داخل نفس tenant فقط)
--   - Unique barcode داخل نفس tenant فقط (مع السماح بـ NULL)
--   - Soft-delete عبر deleted_at (بدون hard delete فعلياً من التطبيق)
--
-- ⚠️ Idempotent قدر الإمكان.
-- ============================================================================

-- ============================================================================
-- 0) تحقق من المتطلبات المسبقة.
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
-- 1) product_colors
-- ============================================================================
create table if not exists public.product_colors (
  id          uuid primary key default gen_random_uuid(),
  tenant_uuid text not null,
  product_id  text not null,
  name        text not null,
  hex_code    text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

comment on table public.product_colors is
  'ألوان داخل المنتج (لكل tenant). تُستخدم لإنشاء Variants (لون + مقاس).';

create index if not exists idx_product_colors_tenant
  on public.product_colors(tenant_uuid);

create index if not exists idx_product_colors_product
  on public.product_colors(tenant_uuid, product_id);

-- Unique اسم اللون داخل المنتج (مع مراعاة soft delete عبر index جزئي)
create unique index if not exists uq_product_colors_product_name_alive
  on public.product_colors(tenant_uuid, product_id, lower(trim(name)))
  where deleted_at is null;

-- Trigger: set tenant_uuid from JWT
drop trigger if exists trg_product_colors_set_tenant on public.product_colors;
create trigger trg_product_colors_set_tenant
  before insert on public.product_colors
  for each row
  execute function public.set_tenant_uuid_from_jwt();

-- RLS
alter table public.product_colors enable row level security;
alter table public.product_colors force row level security;

drop policy if exists product_colors_select_own on public.product_colors;
create policy product_colors_select_own
  on public.product_colors for select
  using (tenant_uuid = public.app_current_tenant_id());

drop policy if exists product_colors_insert_own on public.product_colors;
create policy product_colors_insert_own
  on public.product_colors for insert
  with check (tenant_uuid = public.app_current_tenant_id());

drop policy if exists product_colors_update_own on public.product_colors;
create policy product_colors_update_own
  on public.product_colors for update
  using (tenant_uuid = public.app_current_tenant_id())
  with check (tenant_uuid = public.app_current_tenant_id());

drop policy if exists product_colors_delete_own on public.product_colors;
create policy product_colors_delete_own
  on public.product_colors for delete
  using (tenant_uuid = public.app_current_tenant_id());

-- ============================================================================
-- 2) product_variants
-- ============================================================================
create table if not exists public.product_variants (
  id          uuid primary key default gen_random_uuid(),
  tenant_uuid text not null,
  product_id  text not null,
  color_id    uuid not null,
  size        text not null,
  quantity    integer not null default 0,
  barcode     text,
  sku         text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  constraint fk_product_variants_color
    foreign key(color_id) references public.product_colors(id)
    on delete restrict
);

comment on table public.product_variants is
  'Variants (لون + مقاس) مع مخزون مستقل. barcode فريد داخل tenant عند إدخاله.';

create index if not exists idx_product_variants_tenant
  on public.product_variants(tenant_uuid);

create index if not exists idx_product_variants_product
  on public.product_variants(tenant_uuid, product_id);

create index if not exists idx_product_variants_color
  on public.product_variants(tenant_uuid, color_id);

-- منع تكرار المقاس داخل نفس اللون (مع مراعاة soft delete)
create unique index if not exists uq_product_variants_color_size_alive
  on public.product_variants(tenant_uuid, color_id, lower(trim(size)))
  where deleted_at is null;

-- barcode unique داخل tenant فقط (NULL/blank مسموح)
create unique index if not exists uq_product_variants_barcode_tenant_alive
  on public.product_variants(tenant_uuid, upper(trim(barcode)))
  where barcode is not null and trim(barcode) <> '' and deleted_at is null;

-- Trigger: set tenant_uuid from JWT
drop trigger if exists trg_product_variants_set_tenant on public.product_variants;
create trigger trg_product_variants_set_tenant
  before insert on public.product_variants
  for each row
  execute function public.set_tenant_uuid_from_jwt();

-- RLS
alter table public.product_variants enable row level security;
alter table public.product_variants force row level security;

drop policy if exists product_variants_select_own on public.product_variants;
create policy product_variants_select_own
  on public.product_variants for select
  using (tenant_uuid = public.app_current_tenant_id());

drop policy if exists product_variants_insert_own on public.product_variants;
create policy product_variants_insert_own
  on public.product_variants for insert
  with check (tenant_uuid = public.app_current_tenant_id());

drop policy if exists product_variants_update_own on public.product_variants;
create policy product_variants_update_own
  on public.product_variants for update
  using (tenant_uuid = public.app_current_tenant_id())
  with check (tenant_uuid = public.app_current_tenant_id());

drop policy if exists product_variants_delete_own on public.product_variants;
create policy product_variants_delete_own
  on public.product_variants for delete
  using (tenant_uuid = public.app_current_tenant_id());

-- ============================================================================
-- ROLLBACK (طارئ)
-- ============================================================================
-- drop policy if exists product_variants_delete_own on public.product_variants;
-- drop policy if exists product_variants_update_own on public.product_variants;
-- drop policy if exists product_variants_insert_own on public.product_variants;
-- drop policy if exists product_variants_select_own on public.product_variants;
-- drop trigger if exists trg_product_variants_set_tenant on public.product_variants;
-- drop table if exists public.product_variants;
--
-- drop policy if exists product_colors_delete_own on public.product_colors;
-- drop policy if exists product_colors_update_own on public.product_colors;
-- drop policy if exists product_colors_insert_own on public.product_colors;
-- drop policy if exists product_colors_select_own on public.product_colors;
-- drop trigger if exists trg_product_colors_set_tenant on public.product_colors;
-- drop table if exists public.product_colors;
