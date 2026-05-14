-- ============================================================================
-- Migration: 20260511_tenant_access.sql
-- Step 20 — جدول tenant_access (Kill Switch + valid_until) للتحكّم بالاشتراكات.
--
-- يُشغَّل يدوياً من Supabase Studio (SQL Editor) كـ superuser.
-- المتطلبات المسبقة:
--   - 20260507_rls_tenant.sql            (Step 11 — app_current_tenant_id())
--
-- 🎯 الهدف:
--   مصدر حقيقة واحد على الخادم لحالة اشتراك كلّ tenant. الجهاز يقرأ ولا يكتب.
--   تُستعمل لاحقاً (Step التالي) لإغلاق التطبيق محلياً عندما:
--     kill_switch = true  OR  valid_until <= now()
--
--   مع `grace_until` تتمكّن من منح فترة سماح بعد انتهاء الاشتراك (مثل 7 أيام
--   للقراءة فقط) قبل تطبيق `revoked` كامل.
--
-- 🔒 السرية الصارمة:
--   - SELECT فقط لصاحب الـ tenant (RLS).
--   - INSERT/UPDATE/DELETE: لا توجد سياسة لأيّ role غير service_role
--     (الذي يتجاوز RLS أصلاً). دفاع متعدّد الطبقات: REVOKE صريح من
--     authenticated و anon و public لمنع كتابة عرضية إن غُفلت RLS.
--   - الإدارة تتمّ من Supabase Studio أو من خلفية موثوقة تستعمل service_role
--     فقط — لا توجد client-side write path أصلاً.
--
-- ⚠️ idempotent — يمكن تشغيله أكثر من مرة بأمان.
-- ============================================================================


-- ============================================================================
-- 0) متطلب مسبق: app_current_tenant_id() من Step 11.
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


-- ============================================================================
-- 1) جدول tenant_access.
--    - tenant_id: مفتاح أساسي (نصّي ليتطابق مع نتيجة app_current_tenant_id()).
--    - access_status: حالة وصف للحالة الحالية (للقراءة من العميل).
--    - kill_switch:   إيقاف فوري بغضّ النظر عن أيّ حقل آخر.
--    - grace_until:   انتهاء فترة السماح (بعد valid_until وقبل revoke كامل).
--    - valid_until:   آخر لحظة يكون فيها الاشتراك نشطاً (لا قيمة سابقة لها).
--    - notes:         ملاحظات إدارية (سبب الإيقاف، رقم تذكرة، إلخ).
--    - updated_at:    آخر تحديث (يتمّ تحديثه يدوياً من قبل الإدارة).
-- ============================================================================
create table if not exists public.tenant_access (
  tenant_id     text         primary key,
  access_status text         not null default 'active'
                check (access_status in ('active','suspended','revoked','grace')),
  kill_switch   boolean      not null default false,
  grace_until   timestamptz,
  valid_until   timestamptz  not null,
  notes         text,
  updated_at    timestamptz  not null default now()
);

comment on table  public.tenant_access            is 'Step 20 — مصدر الحقيقة لحالة اشتراك كلّ tenant. لا يكتب فيها العميل.';
comment on column public.tenant_access.tenant_id     is 'يطابق app_current_tenant_id() (sub claim من JWT).';
comment on column public.tenant_access.access_status is 'وصف الحالة: active / suspended / revoked / grace.';
comment on column public.tenant_access.kill_switch   is 'إيقاف فوري — له الأسبقية على أيّ حقل آخر.';
comment on column public.tenant_access.grace_until   is 'فترة سماح بعد valid_until (قراءة فقط مثلاً).';
comment on column public.tenant_access.valid_until   is 'آخر لحظة نشطة — > now() = اشتراك ساري.';
comment on column public.tenant_access.notes         is 'ملاحظات إدارية حرة.';
comment on column public.tenant_access.updated_at    is 'آخر تحديث للسجلّ (يُحدَّث يدوياً من قبل الإدارة).';


-- ============================================================================
-- 2) فهارس مساعدة (لاستعلامات الإدارة فقط — العميل يقرأ صفّاً واحداً).
-- ============================================================================
create index if not exists tenant_access_status_idx
  on public.tenant_access (access_status);

create index if not exists tenant_access_valid_until_idx
  on public.tenant_access (valid_until);

create index if not exists tenant_access_killswitch_idx
  on public.tenant_access (kill_switch)
  where kill_switch = true;


-- ============================================================================
-- 3) صلاحيات صريحة — defense-in-depth.
--    حتى لو حدث ثقب في RLS، لن تستطيع authenticated/anon الكتابة لأن
--    GRANT الأساسي مسحوب.
-- ============================================================================
revoke all      on public.tenant_access from public;
revoke all      on public.tenant_access from authenticated;
revoke all      on public.tenant_access from anon;
grant  select   on public.tenant_access to authenticated;
-- ملاحظة: لا نمنح أي شيء لـ anon (لا يُفترض أن يقرأ tenant_access).


-- ============================================================================
-- 4) تفعيل RLS.
-- ============================================================================
alter table public.tenant_access enable row level security;
alter table public.tenant_access force  row level security;


-- ============================================================================
-- 5) سياسات RLS — SELECT فقط لصاحب الـ tenant.
--    لا توجد سياسات INSERT/UPDATE/DELETE نهائياً ⇒ كلّ الكتابات من authenticated
--    سترفض حتى لو امتلك المستخدم GRANT (وهو لا يمتلكه أصلاً بعد الـ REVOKE).
-- ============================================================================
drop policy if exists "tenant_access_self_select" on public.tenant_access;
create policy "tenant_access_self_select"
  on public.tenant_access
  for select
  using (tenant_id = public.app_current_tenant_id());

comment on policy "tenant_access_self_select" on public.tenant_access is
  'Step 20 — كلّ tenant يرى صفّه فقط. الإدارة تستعمل service_role (يتجاوز RLS).';


-- ============================================================================
-- 6) دالّة app_tenant_access_status()
--    تُرجع صفّ الـ tenant الحالي (composite type = tenant_access).
--    SECURITY DEFINER لتفادي أيّ مفاجآت في search_path أو RLS عند استدعاء
--    من الـ wrappers — لكنّها تُصفّي على app_current_tenant_id() من JWT
--    فقط، لا تتلقّى أيّ tenant_id من العميل.
-- ============================================================================
create or replace function public.app_tenant_access_status()
returns public.tenant_access
language sql
stable
security definer
set search_path = public, auth
as $$
  select *
  from public.tenant_access
  where tenant_id = public.app_current_tenant_id()
  limit 1;
$$;

comment on function public.app_tenant_access_status() is
  'Step 20 — يُعيد صفّ tenant_access للـ tenant الحالي (من JWT). '
  'SECURITY DEFINER + STABLE. لا يتلقّى tenant_id من العميل.';

revoke all     on function public.app_tenant_access_status() from public;
grant  execute on function public.app_tenant_access_status() to authenticated;


-- ============================================================================
-- 7) فحص نهائي + إشعار في log الـ SQL Editor.
-- ============================================================================
do $$
begin
  -- التأكد من وجود الجدول
  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'tenant_access'
  ) then
    raise exception 'tenant_access table was not created';
  end if;

  -- التأكد من تفعيل RLS
  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'tenant_access'
      and c.relrowsecurity = true
  ) then
    raise exception 'RLS not enabled on tenant_access';
  end if;

  -- التأكد من عدم وجود سياسات write
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'tenant_access'
      and cmd in ('INSERT','UPDATE','DELETE')
  ) then
    raise exception 'Unexpected write policy on tenant_access — table must be SELECT-only for clients';
  end if;

  raise notice 'Step 20 applied. tenant_access table created with RLS (SELECT-only). '
               'Admin writes via service_role only.';
end $$;


-- =============================================================================
-- ROLLBACK (للاستعمال الطارئ — يُسقط الجدول والدالّة).
-- =============================================================================
-- ⚠️ لا تشغّل إلّا مع نسخة احتياطية. إسقاط tenant_access يعني فقدان كلّ سجلّات
--    الاشتراكات والإيقافات الإدارية.
--
-- drop function if exists public.app_tenant_access_status();
-- drop policy   if exists "tenant_access_self_select" on public.tenant_access;
-- drop index    if exists public.tenant_access_killswitch_idx;
-- drop index    if exists public.tenant_access_valid_until_idx;
-- drop index    if exists public.tenant_access_status_idx;
-- drop table    if exists public.tenant_access;
-- =============================================================================
-- نهاية الترحيل.
-- =============================================================================
