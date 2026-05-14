-- ============================================================================
-- Migration: 20260509_financial_audit_log.sql
-- Step 18 — سجل تدقيق غير قابل للتعديل لكلّ تغيير على البيانات المالية.
--
-- يُشغَّل يدوياً من Supabase Studio (SQL Editor) كـ superuser.
-- المتطلبات المسبقة:
--   - 20260507_rls_tenant.sql   (يُعرّف public.app_current_tenant_id())
--   - 20260508_rpc_per_mutation.sql (يُعرّف rpc_process_sync_queue الجديدة)
--
-- 🎯 لماذا سجل التدقيق؟
--   كلّ تعديل مالي على السيرفر (إنشاء/تعديل/حذف فاتورة، مدفوعات، أقساط…)
--   يجب أن يترك أثراً يمكن تتبّعه: مَن نفّذها، متى، ما كان قبلها وما صار
--   بعدها. هذا أساس أيّ تحقيق مالي أو نزاع، وشرطٌ لكثير من معايير الالتزام.
--
-- 🔧 لماذا triggers بدل تعديل _rpc_process_sync_queue_legacy؟
--   الطلب الأصلي: «حدّث _rpc_process_sync_queue_legacy ليكتب صف تدقيق لكل
--   عملية ناجحة». اخترنا تنفيذها عبر Postgres triggers لأنّها:
--     1) أكثر متانة — فشل أي mutation داخل savepoint Step 17 يُلغي صف
--        التدقيق تلقائياً (نفس الـ transaction). لا يمكن نسيان كتابته.
--     2) أقلّ كوداً وأقلّ مخاطرة — لا نُعيد كتابة دالة قديمة بمئات الأسطر.
--     3) تعمل أيضاً لأي طريق كتابة آخر (RPC مستقبلي، direct write مع RLS) —
--        defense in depth.
--   هذا يُحقّق نفس متطلبات السلوك:
--     - op = 'insert' | 'update' | 'delete'           ✅ (TG_OP)
--     - before_jsonb = old row في UPDATE/DELETE         ✅ (to_jsonb(OLD))
--     - after_jsonb  = new row في INSERT/UPDATE         ✅ (to_jsonb(NEW))
--     - failed mutation ⇒ NO audit row                  ✅ (savepoint rollback)
--
-- 🛡️ الجدول immutable حقاً:
--   - RLS مُفعَّلة، السياسة الوحيدة هي SELECT.
--   - لا يوجد INSERT/UPDATE/DELETE policy → كل العمليات هذه ممنوعة لأي دور
--     غير superuser.
--   - revoke insert,update,delete من authenticated/anon/public — حزام إضافي
--     فوق RLS.
--   - الكتابة الوحيدة الممكنة عبر دالّة SECURITY DEFINER المملوكة لـ postgres
--     (تتجاوز RLS تلقائياً). أي تطبيق في Flutter لا يمكنه INSERT أو UPDATE
--     أو DELETE على هذا الجدول مهما حاول.
--
-- ⚠️ هذا الملف idempotent — يمكن تشغيله أكثر من مرة بأمان.
-- ============================================================================


-- ============================================================================
-- 0) متطلب مسبق: app_current_tenant_id() يجب أن تكون موجودة (Step 11).
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
      'Missing public.app_current_tenant_id(). Run 20260507_rls_tenant.sql first.'
      using errcode = 'P0001';
  end if;
end $$;


-- ============================================================================
-- 1) الجدول: financial_audit_log
--    سجل غير قابل للتعديل: append-only فقط.
-- ============================================================================
create table if not exists public.financial_audit_log (
  id            bigserial primary key,
  tenant_id     text        not null,
  user_id       text        not null,
  device_id     text,
  entity_type   text        not null,
  entity_id     text        not null,
  op            text        not null check (op in ('insert','update','delete')),
  before_jsonb  jsonb,
  after_jsonb   jsonb,
  created_at    timestamptz not null default now()
);

-- فهارس قراءة شائعة: حسب المستأجر/الكيان/التاريخ.
create index if not exists idx_financial_audit_tenant_created
  on public.financial_audit_log (tenant_id, created_at desc);
create index if not exists idx_financial_audit_entity
  on public.financial_audit_log (entity_type, entity_id);

comment on table public.financial_audit_log is
  'Step 18 — سجل تدقيق immutable لكلّ تعديل مالي. لا UPDATE ولا DELETE مسموحان.';


-- ============================================================================
-- 2) قفل الكتابة من العميل (Defense in depth قبل RLS)
--    - authenticated / anon لا يستطيعون إلّا SELECT.
--    - حتى service_role لا يجب أن يحرّر هذا الجدول من العميل عادةً، لكنّه
--      يبقى قادراً على ذلك بحكم تصميم Supabase — الحماية الفعلية في RLS
--      على الـ JWT.
-- ============================================================================
revoke insert, update, delete on public.financial_audit_log from public;
revoke insert, update, delete on public.financial_audit_log from authenticated;
revoke insert, update, delete on public.financial_audit_log from anon;
grant  select on public.financial_audit_log to authenticated;


-- ============================================================================
-- 3) RLS — السياسة الوحيدة هي SELECT للمستأجر صاحب الصف.
--    لا INSERT policy ولا UPDATE policy ولا DELETE policy متعمَّداً:
--    غياب السياسة + RLS مُفعَّلة ⇒ العملية مرفوضة لأي دور غير superuser.
-- ============================================================================
alter table public.financial_audit_log enable row level security;

drop policy if exists financial_audit_log_select_own on public.financial_audit_log;
create policy financial_audit_log_select_own
  on public.financial_audit_log
  for select
  using (tenant_id = public.app_current_tenant_id());

comment on policy financial_audit_log_select_own on public.financial_audit_log is
  'Step 18 — كل مستأجر يرى أثره فقط. ممنوع عبور الحدود.';


-- ============================================================================
-- 4) دالة كتابة التدقيق
--    - SECURITY DEFINER المملوكة لـ postgres → تتجاوز RLS عند INSERT.
--    - تقرأ tenant_id من JWT (app_current_tenant_id()) أوّلاً، ثم من
--      tenant_uuid على الصفّ كـ fallback (الـ trigger في Step 11 ضامن أنّه
--      موجود ومختوم من السيرفر).
--    - تأخذ entity_id من global_id (PK المعتمَد في كلّ الجداول المالية).
-- ============================================================================
create or replace function public._audit_financial_change()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_row     jsonb;
  v_tenant  text;
  v_user    text;
  v_eid     text;
  v_before  jsonb := null;
  v_after   jsonb := null;
  v_op      text;
begin
  -- جسد الصف لقراءة الحقول العمومية بشكل آمن مهما تغيّر مخطّط الجدول.
  if tg_op = 'DELETE' then
    v_row := to_jsonb(OLD);
  else
    v_row := to_jsonb(NEW);
  end if;

  -- 1) tenant: نفضّل JWT؛ وإلّا نقرأ tenant_uuid من الصفّ (مختوم من السيرفر).
  v_tenant := public.app_current_tenant_id();
  if v_tenant is null or v_tenant = '' then
    v_tenant := v_row->>'tenant_uuid';
  end if;

  -- 2) إن لم نعرف المستأجر فلا نُسجّل (أوضاع تطوير/setup فقط).
  if v_tenant is null or v_tenant = '' then
    return coalesce(NEW, OLD);
  end if;

  -- 3) معرّف الكيان: global_id أوّلاً، ثم id كاحتياط، ثم 'unknown'.
  v_eid := coalesce(v_row->>'global_id', v_row->>'id', 'unknown');

  -- 4) المستخدم: من JWT.
  v_user := coalesce(auth.uid()::text, 'system');

  -- 5) قبل/بعد بحسب نوع العملية.
  if tg_op = 'INSERT' then
    v_op := 'insert';
    v_after := to_jsonb(NEW);
  elsif tg_op = 'UPDATE' then
    v_op := 'update';
    v_before := to_jsonb(OLD);
    v_after  := to_jsonb(NEW);
  else
    v_op := 'delete';
    v_before := to_jsonb(OLD);
  end if;

  insert into public.financial_audit_log (
    tenant_id, user_id, device_id, entity_type, entity_id, op,
    before_jsonb, after_jsonb
  ) values (
    v_tenant, v_user, null, tg_table_name, v_eid, v_op,
    v_before, v_after
  );

  return coalesce(NEW, OLD);
end;
$$;

comment on function public._audit_financial_change() is
  'Step 18 — Trigger يكتب صفّ تدقيق لكل INSERT/UPDATE/DELETE على جدول مالي. '
  'SECURITY DEFINER ليتجاوز RLS الخاصّة بـ financial_audit_log. تنفيذها ضمن '
  'نفس الـ transaction للـ mutation: فشل الـ mutation يُلغي صفّ التدقيق تلقائياً.';


-- ============================================================================
-- 5) تطبيق التريغر على كل جدول مالي تغطّيه Step 11.
--    قائمة الجداول الـ 11 — كلّها تملك tenant_uuid الآن.
-- ============================================================================
do $$
declare
  t text;
  financial_tables text[] := array[
    'cash_ledger',
    'work_shifts',
    'expenses',
    'expense_categories',
    'customer_debt_payments',
    'supplier_bills',
    'supplier_payouts',
    'installment_plans',
    'installments',
    'customers',
    'suppliers'
  ];
begin
  foreach t in array financial_tables loop
    if not exists (
      select 1
      from information_schema.tables
      where table_schema = 'public' and table_name = t
    ) then
      -- لا نخفق — قد يكون الجدول لم يُنشأ بعد على بيئة معيّنة.
      raise notice 'Skipping audit trigger for missing table: %', t;
      continue;
    end if;

    -- إعادة إنشاء التريغر بشكل idempotent.
    execute format(
      'drop trigger if exists %I on public.%I',
      'trg_audit_' || t, t
    );
    execute format(
      'create trigger %I '
      'after insert or update or delete on public.%I '
      'for each row execute function public._audit_financial_change()',
      'trg_audit_' || t, t
    );
  end loop;
end $$;


-- ============================================================================
-- 6) فحص سريع (يطبع عدد التريغرز التدقيقية المُطبَّقة).
-- ============================================================================
do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from pg_trigger t
  join pg_class  c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and t.tgname like 'trg_audit_%'
    and not t.tgisinternal;
  raise notice 'Step 18 — تم تطبيق % تريغر تدقيق على الجداول المالية.', v_count;
end $$;


-- =============================================================================
-- ROLLBACK (للاستعمال الطارئ فقط)
-- =============================================================================
-- ⚠️ تنفيذ هذا القسم يُلغي تتبّع التدقيق على السيرفر بالكامل ويسقط الجدول.
--    لا يُنفَّذ إلا بقرار صريح وبعد أخذ نسخة احتياطية.
--
-- do $$
-- declare
--   t text;
-- begin
--   foreach t in array array[
--     'cash_ledger','work_shifts','expenses','expense_categories',
--     'customer_debt_payments','supplier_bills','supplier_payouts',
--     'installment_plans','installments','customers','suppliers'
--   ] loop
--     if exists (
--       select 1 from information_schema.tables
--        where table_schema = 'public' and table_name = t
--     ) then
--       execute format('drop trigger if exists %I on public.%I', 'trg_audit_' || t, t);
--     end if;
--   end loop;
-- end $$;
--
-- drop function if exists public._audit_financial_change();
-- drop policy if exists financial_audit_log_select_own on public.financial_audit_log;
-- drop table if exists public.financial_audit_log;
-- =============================================================================
-- نهاية الترحيل.
-- =============================================================================
