-- ============================================================================
-- Migration: 20260516_rpc_service_orders_sync.sql
-- Step 11 (RPC legacy extension) — دعم مزامنة service_order / service_order_item
-- عبر sync_queue (entity_type = service_order / service_order_item).
--
-- يُشغَّل يدوياً من Supabase Studio (SQL editor) كـ superuser.
-- المتطلبات المسبقة:
--   - 20260507_rls_tenant.sql (app_current_tenant_id)
--   - 20260508_rpc_per_mutation.sql (rpc_process_sync_queue returns jsonb)
--   - 20260514_rpc_product_variants_sync.sql (وجود legacy wrapper/base)
--   - 20260515_service_orders.sql (public.service_orders/service_order_items + RLS)
--
-- ملاحظة مهمة:
-- - SQLite المحلي يستخدم camelCase (customerNameSnapshot, deletedAt, orderGlobalId).
-- - Supabase يستخدم snake_case (customer_name_snapshot, deleted_at, order_global_id).
-- - هذا الـ RPC يتقبل الصيغتين معاً لتجنّب كسر أي عميل.
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
end $$;

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

    -- -----------------------------------------------------------------------
    -- 1) service_order (job ticket)
    -- -----------------------------------------------------------------------
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

    -- -----------------------------------------------------------------------
    -- 2) service_order_item (parts used)
    -- -----------------------------------------------------------------------
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

    -- -----------------------------------------------------------------------
    -- 3) Delegate to base for other entity types (including product_variant/color)
    -- -----------------------------------------------------------------------
    perform public._rpc_process_sync_queue_legacy_base(jsonb_build_array(mutation));
  end loop;
end;
$$;

comment on function public._rpc_process_sync_queue_legacy(jsonb) is
  'Extends legacy sync RPC to support service_order/service_order_item mutations, '
  'then delegates other entity types to _rpc_process_sync_queue_legacy_base.';

