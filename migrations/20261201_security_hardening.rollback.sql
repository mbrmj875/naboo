-- الرجوع عن 20261201_security_hardening.sql (يعيد الحال كما كانت يوم 2026-11-27).
-- تحذير: يعيد فتح الثغرات المذكورة في الهجرة. لا يُستعمل إلا إذا انكسر شيء.

begin;

-- 0 و7) صلاحيات العرض والجدول كما كانت (افتراضيات Supabase).
grant all on table public.marketplace_stores_public to anon, authenticated;
alter view public.marketplace_stores_public set (security_invoker = false);
grant all on table public.marketplace_stores to anon;

-- 1) النسخة السابقة من إنشاء المتجر.
create or replace function public.marketplace_provision_store(p_name text, p_slug text default null)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_id uuid; v_slug text; v_name text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select id into v_id from marketplace_stores where tenant_uuid = auth.uid() limit 1;
  if v_id is not null then return v_id; end if;
  v_name := nullif(trim(p_name), '');
  if v_name is null then raise exception 'store name required'; end if;
  v_slug := nullif(trim(p_slug), '');
  if v_slug is null then v_slug := 'store-' || left(replace(auth.uid()::text, '-', ''), 12); end if;
  insert into marketplace_stores (tenant_uuid, name, slug, description, neighborhood_label, location_type,
    is_published, is_pickup_point, commission_rate_bps, pilot_started_at)
  values (auth.uid(), v_name, v_slug, v_name, 'العشار', 'commercial', true, false, 0, current_date)
  on conflict (slug) do update set tenant_uuid = excluded.tenant_uuid, name = excluded.name,
    is_published = true, updated_at = now()
  returning id into v_id;
  return v_id;
end;
$function$;

-- 2) النسخة السابقة من طلب التصنيف.
create or replace function public.marketplace_enqueue_classification(p_product_global_id text)
returns uuid language plpgsql security definer set search_path to 'public'
as $function$
declare v_product_id uuid; v_queue_id uuid;
begin
  select id into v_product_id from marketplace_products where product_global_id = p_product_global_id limit 1;
  if not exists (select 1 from marketplace_classification_queue
                 where product_global_id = p_product_global_id and status in ('pending', 'processing')) then
    insert into marketplace_classification_queue (product_global_id, product_id, status, source)
    values (p_product_global_id, v_product_id, 'pending', 'erp_sync') returning id into v_queue_id;
  else
    select id into v_queue_id from marketplace_classification_queue
    where product_global_id = p_product_global_id and status in ('pending', 'processing') limit 1;
  end if;
  update marketplace_products set classification_status = 'pending', updated_at = now()
  where product_global_id = p_product_global_id;
  return v_queue_id;
end;
$function$;

-- 3) النسخة السابقة من ربط المتجر.
create or replace function public.marketplace_claim_store(p_store_id uuid)
returns void language plpgsql security definer set search_path to 'public'
as $function$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update marketplace_stores set tenant_uuid = auth.uid(), is_published = true, updated_at = now()
  where id = p_store_id and tenant_uuid is null and is_published = true;
  if not found then raise exception 'store not claimable'; end if;
end;
$function$;

-- 4) دوال المزامنة الداخلية.
grant execute on function public._rpc_process_sync_queue_legacy(jsonb) to authenticated;
grant execute on function public._rpc_process_sync_queue_legacy_base(jsonb) to authenticated;

-- 5) دوال المشغّلات التي كانت مفتوحة.
do $$
declare f text;
begin
  foreach f in array array[
    '_audit_financial_change()', 'add_loyalty_points()', 'disable_push_on_device_revoke()',
    'fn_archive_app_snapshot_before_update()', 'guard_account_device_owner_notify()',
    'handle_new_user_profile()', 'marketplace_validate_order_item_stock()',
    'mp_refresh_product_rating()', 'mp_refresh_store_rating()', 'notifications_kick_dispatch()',
    'notify_new_order()', 'prevent_device_self_unrevoke()', 'protect_profiles_privileged_cols()',
    'set_assistant_tenant_id_from_jwt()', 'set_tenant_uuid_from_jwt()'
  ] loop
    execute format('grant execute on function public.%s to public, anon, authenticated', f);
  end loop;
end $$;

-- 6) إزالة المسار المثبَّت عن الدوال التي لم يكن لها مسار.
do $$
declare f text;
begin
  foreach f in array array[
    '_parse_client_ts(jsonb)', '_reject_clock_skew(jsonb)', '_rpc_process_sync_queue_legacy_base(jsonb)',
    'add_loyalty_points()', 'app_device_limit_status()', 'app_my_license_jwt()', 'app_user_max_devices()',
    'fn_bump_snapshot_version()', 'fn_init_snapshot_version()', 'handle_new_user_profile()',
    'increment_coupon_uses(text)', 'notify_new_order()', 'restaurant_order_invoice_matches_session()',
    'rpc_push_snapshot(bigint,jsonb,integer,text,text,text)', 'update_stock_status()',
    'update_store_rating()', 'update_variant_stock_status()',
    'wa_followup_compute_due_at(timestamp with time zone,integer,text,boolean)'
  ] loop
    execute format('alter function public.%s reset search_path', f);
  end loop;
end $$;

-- 8) سياسات التخزين السابقة.
drop policy if exists "Merchants read own store images" on storage.objects;
create policy "Public read store images" on storage.objects
  for select to public using (bucket_id = 'marketplace-store-images');
create policy "naboo_public_read" on storage.objects
  for select to public using (bucket_id = 'naboo-public');

commit;
