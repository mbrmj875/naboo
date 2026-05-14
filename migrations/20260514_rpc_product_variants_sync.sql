-- ============================================================================
-- Migration: 20260514_rpc_product_variants_sync.sql
-- Step 11 (RPC legacy extension) — دعم مزامنة product_variants / product_colors
-- عبر sync_queue (entity_type = product_variant / product_color).
--
-- يُشغَّل يدوياً من Supabase Studio (SQL editor) كـ superuser.
-- المتطلبات المسبقة:
--   - 20260507_rls_tenant.sql (app_current_tenant_id)
--   - 20260508_rpc_per_mutation.sql (rpc_process_sync_queue returns jsonb)
--   - 20260513_product_variants.sql (public.product_colors/product_variants + RLS)
--
-- الفكرة:
--   - لا نُعيد كتابة منطق legacy القديم لباقي الكيانات.
--   - نُعيد تسمية legacy الحالي إلى _rpc_process_sync_queue_legacy_base
--     ثم ننشئ wrapper جديد بنفس الاسم يلتقط product_variant/product_color
--     ويُفوّض باقي الكيانات للنسخة الأساسية.
-- ============================================================================

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

    if e_type = 'product_variant' then
      if op not in ('INSERT','UPDATE') then
        continue;
      end if;

      insert into public.product_variants(
        id,
        tenant_uuid,
        product_id,
        color_id,
        size,
        quantity,
        barcode,
        sku,
        updated_at,
        deleted_at
      ) values (
        (mutation->>'id')::uuid,
        v_tenant_uuid,
        mutation->>'product_id',
        (mutation->>'color_id')::uuid,
        coalesce(nullif(trim(mutation->>'size'), ''), 'SIZE'),
        coalesce((mutation->>'quantity')::int, 0),
        nullif(trim(mutation->>'barcode'), ''),
        nullif(trim(mutation->>'sku'), ''),
        now(),
        null
      )
      on conflict (id) do update set
        product_id = excluded.product_id,
        color_id = excluded.color_id,
        size = excluded.size,
        quantity = excluded.quantity,
        barcode = excluded.barcode,
        sku = excluded.sku,
        updated_at = now(),
        deleted_at = null
      where public.product_variants.tenant_uuid = v_tenant_uuid;

      continue;
    end if;

    if e_type = 'product_color' then
      if op not in ('INSERT','UPDATE') then
        continue;
      end if;

      insert into public.product_colors(
        id,
        tenant_uuid,
        product_id,
        name,
        hex_code,
        updated_at,
        deleted_at
      ) values (
        (mutation->>'id')::uuid,
        v_tenant_uuid,
        mutation->>'product_id',
        coalesce(nullif(trim(mutation->>'name'), ''), 'لون'),
        nullif(trim(mutation->>'hex_code'), ''),
        now(),
        null
      )
      on conflict (id) do update set
        product_id = excluded.product_id,
        name = excluded.name,
        hex_code = excluded.hex_code,
        updated_at = now(),
        deleted_at = null
      where public.product_colors.tenant_uuid = v_tenant_uuid;

      continue;
    end if;

    -- باقي الكيانات: فوّض إلى النسخة الأساسية.
    perform public._rpc_process_sync_queue_legacy_base(jsonb_build_array(mutation));
  end loop;
end;
$$;

comment on function public._rpc_process_sync_queue_legacy(jsonb) is
  'Extends legacy sync RPC to support product_variant/product_color mutations, '
  'then delegates other entity types to _rpc_process_sync_queue_legacy_base.';

