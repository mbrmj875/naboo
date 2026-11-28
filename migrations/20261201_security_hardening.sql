-- تقوية أمان قاعدة naboo-lic بعد الفحص الكامل (2026-11-27).
-- كل خطوة هنا لا تغيّر سلوك التطبيق الصحيح، وإنما تسد طريقاً على من يسيء.
-- الرجوع: 20261201_security_hardening.rollback.sql

begin;

-- ─────────────────────────────────────────────────────────────────────────
-- 0) أخطرها: العرض العام للمتاجر كان قابلاً للكتابة.
--    العرض بسيط فيقبل INSERT/UPDATE/DELETE تلقائياً، والزائر (anon) يملك
--    صلاحية الكتابة عليه، والعرض يعمل بصلاحية مالكه فيتخطى RLS.
--    أي حامل للمفتاح العام كان يستطيع تعديل أو حذف أي متجر منشور.
-- ─────────────────────────────────────────────────────────────────────────
revoke all on table public.marketplace_stores_public from anon, authenticated, public;
grant select on table public.marketplace_stores_public to anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 1) منع الاستيلاء على متجر محل آخر عبر الاسم المختصر (slug).
--    كان ON CONFLICT (slug) DO UPDATE ينقل ملكية المتجر لمن يطلب الاسم نفسه.
--    الآن: إن كان الاسم محجوزاً نضيف لاحقة من حساب الطالب، ولا نلمس متجر غيره.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.marketplace_provision_store(p_name text, p_slug text default null)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_uid  uuid := auth.uid();
  v_id   uuid;
  v_slug text;
  v_name text;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select id into v_id from marketplace_stores where tenant_uuid = v_uid limit 1;
  if v_id is not null then
    return v_id;
  end if;

  v_name := nullif(trim(p_name), '');
  if v_name is null then
    raise exception 'store name required';
  end if;

  v_slug := nullif(trim(p_slug), '');
  if v_slug is null then
    v_slug := 'store-' || left(replace(v_uid::text, '-', ''), 12);
  end if;

  insert into marketplace_stores (
    tenant_uuid, name, slug, description, neighborhood_label, location_type,
    is_published, is_pickup_point, commission_rate_bps, pilot_started_at
  ) values (
    v_uid, v_name, v_slug, v_name, 'العشار', 'commercial', true, false, 0, current_date
  )
  on conflict (slug) do nothing
  returning id into v_id;

  if v_id is null then
    -- الاسم محجوز لمتجر آخر: نصنع اسماً فريداً لهذا الحساب بدل أخذ متجر غيره.
    v_slug := left(v_slug, 48) || '-' || left(replace(v_uid::text, '-', ''), 8);
    insert into marketplace_stores (
      tenant_uuid, name, slug, description, neighborhood_label, location_type,
      is_published, is_pickup_point, commission_rate_bps, pilot_started_at
    ) values (
      v_uid, v_name, v_slug, v_name, 'العشار', 'commercial', true, false, 0, current_date
    )
    on conflict (slug) do nothing
    returning id into v_id;
  end if;

  if v_id is null then
    raise exception 'STORE_SLUG_TAKEN';
  end if;
  return v_id;
end;
$function$;

-- ─────────────────────────────────────────────────────────────────────────
-- 2) طلب التصنيف لمنتجات المحل نفسه فقط.
--    كانت الدالة تقبل أي منتج لأي محل، وتعيد حالته إلى «بانتظار التصنيف».
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.marketplace_enqueue_classification(p_product_global_id text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_uid        uuid := auth.uid();
  v_product_id uuid;
  v_queue_id   uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  select p.id into v_product_id
  from marketplace_products p
  join marketplace_stores s on s.id = p.store_id
  where p.product_global_id = p_product_global_id
    and s.tenant_uuid = v_uid
  limit 1;

  -- ليس منتج هذا المحل (أو لم يُرفع بعد): لا شيء.
  if v_product_id is null then
    return null;
  end if;

  select id into v_queue_id
  from marketplace_classification_queue
  where product_global_id = p_product_global_id
    and status in ('pending', 'processing')
  limit 1;

  if v_queue_id is null then
    insert into marketplace_classification_queue (product_global_id, product_id, status, source)
    values (p_product_global_id, v_product_id, 'pending', 'erp_sync')
    returning id into v_queue_id;
  end if;

  update marketplace_products p
  set classification_status = 'pending', updated_at = now()
  from marketplace_stores s
  where s.id = p.store_id
    and s.tenant_uuid = v_uid
    and p.product_global_id = p_product_global_id;

  return v_queue_id;
end;
$function$;

-- ─────────────────────────────────────────────────────────────────────────
-- 3) ربط متجر غير مملوك: مرة واحدة لكل حساب.
--    حساب لديه متجر لا يستطيع جمع متاجر الآخرين غير المربوطة.
-- ─────────────────────────────────────────────────────────────────────────
create or replace function public.marketplace_claim_store(p_store_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;

  if exists (select 1 from marketplace_stores where tenant_uuid = v_uid) then
    raise exception 'ALREADY_HAS_STORE';
  end if;

  update marketplace_stores
  set tenant_uuid = v_uid, is_published = true, updated_at = now()
  where id = p_store_id
    and tenant_uuid is null
    and is_published = true;

  if not found then
    raise exception 'store not claimable';
  end if;
end;
$function$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4) دوال المزامنة الداخلية لا تُستدعى إلا من rpc_process_sync_queue.
--    الاستدعاء المباشر كان يتخطى حد الدفعة وفحص الساعة.
-- ─────────────────────────────────────────────────────────────────────────
revoke execute on function public._rpc_process_sync_queue_legacy(jsonb) from public, anon, authenticated;
revoke execute on function public._rpc_process_sync_queue_legacy_base(jsonb) from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 5) دوال المشغّلات (triggers) لا يحتاج أحد استدعاءها مباشرة.
--    المشغّل يعمل كما هو؛ صلاحية EXECUTE تُفحص عند إنشائه فقط.
-- ─────────────────────────────────────────────────────────────────────────
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prorettype = 'trigger'::regtype
      and p.prosecdef
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.f);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 6) تثبيت مسار البحث للدوال التي بلا مسار (search_path).
-- ─────────────────────────────────────────────────────────────────────────
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  loop
    execute format('alter function %s set search_path = public, extensions, pg_temp', r.f);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 7) الزائر (anon) يرى من المتجر الأعمدة العامة فقط.
--    العنوان الداخلي ونسبة العمولة وتاريخ التجربة لا تخص الزبون.
-- ─────────────────────────────────────────────────────────────────────────
revoke all on table public.marketplace_stores from anon;
grant select (
  id, tenant_uuid, name, slug, description, logo_url, neighborhood_label,
  location_type, pickup_address, pickup_latitude, pickup_longitude,
  is_published, is_pickup_point, pickup_hours, created_at, updated_at,
  delivery_fee_fils, cover_url, gallery, rating_avg, rating_count
) on public.marketplace_stores to anon;

-- العرض العام يعمل بصلاحية القارئ (تبقى سياسات RLS سارية).
alter view public.marketplace_stores_public set (security_invoker = true);

-- ─────────────────────────────────────────────────────────────────────────
-- 8) صور المتاجر: الروابط العامة تعمل بلا سياسة، فلا داعي لكشف قائمة الملفات.
--    التاجر يقرأ ملفات مجلد متجره فقط (يحتاجها الرفع مع الاستبدال).
-- ─────────────────────────────────────────────────────────────────────────
drop policy if exists "Public read store images" on storage.objects;
create policy "Merchants read own store images" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'marketplace-store-images'
    and (storage.foldername(name))[1] in (
      select ms.id::text from public.marketplace_stores ms where ms.tenant_uuid = auth.uid()
    )
  );
drop policy if exists "naboo_public_read" on storage.objects;

commit;
