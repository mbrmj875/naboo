-- ============================================================================
-- Migration: 20260512_register_device_rpc.sql
-- Step 23 — atomic app_register_device (FOR UPDATE + advisory lock + JWT guard).
--
-- يُشغَّل يدوياً من Supabase Studio (SQL Editor) كـ superuser.
-- المتطلبات المسبقة:
--   - 20260507_rls_tenant.sql            (Step 11 — app_current_tenant_id)
--   - admin-web/supabase/device_limit_functions.sql
--                                        (account_devices + app_user_max_devices)
--
-- 🎯 الخطر:
--   النسخة السابقة من app_register_device تعمل بنمط "count then insert":
--     SELECT count(*) FROM account_devices WHERE user_id = ... AND active;
--     IF count >= max THEN raise exception ...;
--     INSERT INTO account_devices ...
--   مكالمتان متزامنتان من نفس الـ tenant قد تصلان إلى SELECT في نفس اللحظة،
--   تريان نفس العداد، ثم تُدخلان كلتاهما ⇒ active = max + 1 ⇒ تجاوز الحدّ.
--   هذا ضعيف خصوصاً عند تشغيل التطبيق على عدّة أجهزة في نفس الثانية بعد
--   استرجاع كاش/تحديث subscription.
--
-- 🛡️ الحلّ:
--   1) JWT guard:
--        - app_current_tenant_id() ⇒ tenant_unauthenticated إن غاب.
--        - auth.uid() للتوافق مع account_devices.user_id (يُساوي sub claim).
--   2) Advisory transaction lock مفتاحه hashtext('register_device:' || tenant):
--        - يُسلسل كلّ مكالمات app_register_device لنفس الـ tenant.
--        - يُحرَّر تلقائياً عند انتهاء الـ transaction (commit/rollback).
--        - مكالمات tenants مختلفة لا تتنافس (مفتاح مختلف).
--   3) FOR UPDATE على صفوف الجهاز الموجودة لنفس tenant:
--        - يُسلسل ضدّ admin يحاول revoke أثناء التسجيل.
--        - يُجبر القارئ التالي على رؤية النسخة المُحدّثة.
--   4) Idempotent عبر INSERT ... ON CONFLICT (user_id, device_id) DO UPDATE:
--        - نفس الجهاز يُستدعى مرّتين ⇒ تحديث، لا duplicate.
--
-- 🔒 السرية الصارمة:
--   - SECURITY DEFINER + locked search_path.
--   - tenant_id من JWT فقط (app_current_tenant_id) — لا يُؤخذ من العميل.
--   - REVOKE من public + GRANT execute لـ authenticated فقط.
--
-- 🧱 تغيير نوع الإرجاع: من TABLE إلى jsonb.
--   لذلك نستعمل DROP IF EXISTS قبل CREATE — Postgres لا يسمح بتغيير return type
--   عبر CREATE OR REPLACE وحده.
--
-- ⚠️ idempotent — يمكن إعادة تشغيله بأمان.
-- ============================================================================


-- ============================================================================
-- 0) متطلبات مسبقة.
-- ============================================================================
do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'app_current_tenant_id'
  ) then
    raise exception 'Missing app_current_tenant_id(). Run 20260507_rls_tenant.sql first.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'account_devices'
  ) then
    raise exception 'Missing public.account_devices table. Run device_limit_functions.sql first.'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'app_user_max_devices'
  ) then
    raise exception 'Missing app_user_max_devices(). Run device_limit_functions.sql first.'
      using errcode = 'P0001';
  end if;
end $$;


-- ============================================================================
-- 1) إعادة بناء app_register_device:
--    - DROP أولاً لأنّ نوع الإرجاع تغيّر (TABLE → jsonb).
--    - CREATE الجديد بالحراسة + القفل + idempotency.
-- ============================================================================
drop function if exists public.app_register_device(text, text, text);

create or replace function public.app_register_device(
  p_device_id text,
  p_device_name text,
  p_platform text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_tenant_id  text;
  v_uid        uuid := auth.uid();
  v_now        timestamptz := now();
  v_max        int;
  v_existing   record;
  v_active     int;
  v_was_known  boolean;
begin
  -- (أ) JWT guard — مصدر هويّة الـ tenant واحد فقط: الـ JWT على الخادم.
  v_tenant_id := public.app_current_tenant_id();
  if v_tenant_id is null or length(trim(v_tenant_id)) = 0 then
    raise exception 'tenant_unauthenticated: refusing app_register_device without authenticated tenant'
      using errcode = 'P0001';
  end if;
  -- التوافق مع account_devices.user_id: نتأكّد أن auth.uid() متوفّرة
  -- (ستكون كذلك لأي جلسة Supabase Auth صحيحة).
  if v_uid is null then
    raise exception 'tenant_unauthenticated: missing auth.uid() under JWT-authenticated session'
      using errcode = 'P0001';
  end if;

  -- (ب) تحقّق المدخلات.
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID: p_device_id must be non-empty'
      using errcode = 'P0001';
  end if;

  -- (ج) Advisory transaction lock مفتاحه tenant — يُسلسل كلّ مكالمات
  --     app_register_device لنفس الـ tenant داخل الـ transaction. هذا هو
  --     السطر الذي يمنع race condition للـ INSERT (FOR UPDATE وحدها لا تكفي
  --     ضدّ INSERT جديد لأنه لا توجد صفوف لقفلها بعد).
  perform pg_advisory_xact_lock(hashtext('register_device:' || v_tenant_id)::bigint);

  -- (د) قفل صفوف الجهاز الموجودة لهذا الـ tenant — يُسلسل ضدّ admin يقوم بـ
  --     revoke في نفس اللحظة (UPDATE). بعد القفل، نقرأ الحالة الفعلية
  --     من السطر الموجود إن وُجد.
  perform 1
  from public.account_devices d
  where d.user_id = v_uid
  for update;

  -- جلب صفّ هذا الجهاز إن كان موجوداً.
  select d.access_status, d.device_id is not null as known
    into v_existing
  from public.account_devices d
  where d.user_id = v_uid and d.device_id = p_device_id
  limit 1;

  v_was_known := found;

  -- (هـ) إذا كان الصف موجوداً ومُلغى ⇒ نُبقيه ملغى ولا نحاول إعادة تنشيطه
  --      من العميل. الإعادة تتمّ من الإدارة فقط.
  if v_was_known and lower(coalesce(v_existing.access_status, 'active')) = 'revoked' then
    return jsonb_build_object(
      'access_status',     'revoked',
      'is_over_limit',     false,
      'active_devices',    0,
      'max_devices',       coalesce(public.app_user_max_devices(), 0),
      'already_registered', true
    );
  end if;

  -- (و) حساب الحدّ والـ active بعد القفل (قراءة قطعيّة).
  v_max := coalesce(public.app_user_max_devices(), 0);

  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  -- (ز) قبول/رفض جهاز جديد:
  --     جهاز موجود (idempotent) ⇒ يمر دائماً (لا يزيد active).
  --     جهاز جديد ⇒ يخضع للحدّ.
  if not v_was_known then
    if v_max <> 0 and v_active >= v_max then
      raise exception 'DEVICE_LIMIT_REACHED: tenant=% has % active devices (limit=%)',
        v_tenant_id, v_active, v_max
        using errcode = 'P0001';
    end if;
  end if;

  -- (ح) Upsert idempotent.
  insert into public.account_devices (
    user_id, device_id, device_name, platform, last_seen_at, created_at, access_status
  ) values (
    v_uid,
    p_device_id,
    coalesce(nullif(trim(p_device_name), ''), 'جهاز غير معروف'),
    nullif(trim(p_platform), ''),
    v_now,
    v_now,
    'active'
  )
  on conflict (user_id, device_id)
  do update set
    device_name   = excluded.device_name,
    platform      = excluded.platform,
    last_seen_at  = excluded.last_seen_at,
    access_status = 'active';

  -- (ط) إعادة الحساب بعد الـ upsert لإرجاع نتيجة دقيقة.
  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  return jsonb_build_object(
    'access_status',      'active',
    'is_over_limit',      case when v_max = 0 then false else (v_active > v_max) end,
    'active_devices',     v_active,
    'max_devices',        v_max,
    'already_registered', v_was_known
  );
end;
$$;

comment on function public.app_register_device(text, text, text) is
  'Step 23 — تسجيل جهاز ذرّي مع JWT guard + advisory lock + FOR UPDATE + idempotent. '
  'يُرجع jsonb: {access_status, is_over_limit, active_devices, max_devices, already_registered}.';


-- ============================================================================
-- 2) صلاحيات: SECURITY DEFINER ⇒ نقصر الـ EXECUTE على authenticated.
-- ============================================================================
revoke all     on function public.app_register_device(text, text, text) from public;
grant  execute on function public.app_register_device(text, text, text) to authenticated;


-- ============================================================================
-- 3) فحص نهائي + إشعار.
-- ============================================================================
do $$
declare
  v_returns_jsonb boolean;
begin
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'app_register_device'
      and pg_catalog.format_type(p.prorettype, null) = 'jsonb'
  ) into v_returns_jsonb;

  if not v_returns_jsonb then
    raise exception 'app_register_device did not get rebuilt with jsonb return type';
  end if;

  raise notice 'Step 23 applied. app_register_device is now atomic '
               '(JWT + advisory lock + FOR UPDATE + idempotent, returns jsonb).';
end $$;


-- =============================================================================
-- ROLLBACK (للاستعمال الطارئ — يُعيد النسخة القديمة من device_limit_functions.sql).
-- =============================================================================
-- ⚠️ النسخة القديمة فيها race condition. لا تستعملها إلا لو تطلّب ذلك توافقاً
--    مع كود قديم لم يُحدَّث للتعامل مع jsonb.
--
-- 1) أسقط النسخة الجديدة:
--    drop function if exists public.app_register_device(text, text, text);
--
-- 2) أعد تثبيت النسخة من admin-web/supabase/device_limit_functions.sql
--    (انسخ كتلة CREATE OR REPLACE FUNCTION app_register_device من ذلك الملف).
-- =============================================================================
-- نهاية الترحيل.
-- =============================================================================
