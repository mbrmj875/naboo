-- ============================================================================
-- Migration: 20260507_rls_tenant.sql
-- Step 11 — Row Level Security متعدّد المستأجرين على Supabase.
--
-- يُشغَّل يدوياً من Supabase Studio (SQL editor) كـ superuser. لاحقاً سيُربط
-- بـ Supabase CLI في sprint منفصل لإدارة الترحيلات.
--
-- الفكرة الأمنية باختصار:
--   1) لا تثق أبداً بـ tenant المُرسَل من العميل (mutation->>'tenantId').
--   2) tenant الموثوق هو نتيجة دالة app_current_tenant_id() المبنيّة على
--      auth.jwt() / auth.uid() — يديرها Supabase Auth ولا يستطيع العميل
--      تزويرها بدون مفتاح service_role.
--   3) كل جدول مالي:
--        - يحصل على عمود tenant_uuid TEXT يُكتب من السيرفر فقط (Trigger).
--        - يُفعَّل عليه RLS مع 4 سياسات (SELECT/INSERT/UPDATE/DELETE) كلّها
--          تشترط: tenant_uuid = app_current_tenant_id().
--   4) دالة rpc_process_sync_queue تُغلَّف بحارس JWT يرفض أيّ مزامنة من جلسة
--      غير موثّقة، ويرفض أي mutation يدّعي tenant مختلف عن JWT.
--
-- ⚠️ هذا الملف idempotent — يمكن تشغيله أكثر من مرة دون خطأ.
-- ============================================================================


-- ============================================================================
-- 1) دالة app_current_tenant_id()
--    تعيد معرّف المستأجر الموثوق من جلسة Supabase. تُستعمَل في كل سياسات RLS
--    وفي الـ Trigger الذي يختم tenant_uuid على الـ INSERT.
--
--    أولوية القراءة:
--      - claim مخصّص في JWT اسمه 'tenant_id'  (للتشغيل المتعدّد المستأجرين).
--      - claim 'sub' (مَن المستخدم).
--      - 'local-' || auth.uid()  كآخر احتمال (للحالات التطويرية).
--    إذا لم تكن الجلسة مصادَقة فلا يوجد tenant → ترجع NULL وتُرفَض كل
--    العمليات تلقائياً عبر السياسات.
-- ============================================================================
create or replace function public.app_current_tenant_id()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(
    nullif(auth.jwt() ->> 'tenant_id', ''),
    nullif(auth.jwt() ->> 'sub', ''),
    case
      when auth.uid() is not null then 'local-' || auth.uid()::text
      else null
    end
  );
$$;

comment on function public.app_current_tenant_id() is
  'يعيد معرّف المستأجر للجلسة الحالية من JWT. يُستعمَل في كل سياسات RLS؛ '
  'لا يقرأ من العميل أبداً.';


-- ============================================================================
-- 2) دالة Trigger: set_tenant_uuid_from_jwt()
--    تُنفَّذ BEFORE INSERT على الجداول المالية. تختم tenant_uuid من JWT
--    وترفض أي إدراج بدون جلسة موثّقة. هذا يحرم العميل من حقن tenant_uuid
--    مزوّر حتى لو حاول.
-- ============================================================================
create or replace function public.set_tenant_uuid_from_jwt()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_tenant text;
begin
  v_tenant := public.app_current_tenant_id();

  if v_tenant is null or v_tenant = '' then
    raise exception 'tenant_uuid_missing: refusing insert without authenticated tenant'
      using errcode = 'P0001';
  end if;

  -- نختم tenant_uuid من السيرفر دائماً، حتى لو أرسل العميل قيمة أخرى.
  new.tenant_uuid := v_tenant;
  return new;
end;
$$;

comment on function public.set_tenant_uuid_from_jwt() is
  'BEFORE INSERT trigger: يختم tenant_uuid من JWT ويرفض الإدراج إذا لا توجد جلسة.';


-- ============================================================================
-- 3) ماكرو داخلي عبر DO $$ ... $$ — تطبيق نفس النمط على كل جدول مالي.
--
--    لكل جدول:
--      a) ADD COLUMN tenant_uuid TEXT (إن لم يكن موجوداً).
--      b) CREATE INDEX idx_<t>_tenant_uuid.
--      c) CREATE TRIGGER trg_<t>_set_tenant BEFORE INSERT.
--      d) ENABLE ROW LEVEL SECURITY.
--      e) 4 سياسات (select / insert / update / delete) كلّها تشترط:
--         tenant_uuid = app_current_tenant_id().
--
--    ملاحظة: نستعمل DROP POLICY IF EXISTS ثم CREATE حتى يكون الملف قابلاً
--    لإعادة التشغيل دون أخطاء.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1) cash_ledger
--      جدول قيود الصندوق — أهم جدول مالي. كل قيد يخصّ tenant واحد فقط.
-- ----------------------------------------------------------------------------
do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'cash_ledger'
      and column_name = 'tenant_uuid'
  ) then
    alter table public.cash_ledger add column tenant_uuid text;
  end if;
end $$;

create index if not exists idx_cash_ledger_tenant_uuid
  on public.cash_ledger(tenant_uuid);

drop trigger if exists trg_cash_ledger_set_tenant on public.cash_ledger;
create trigger trg_cash_ledger_set_tenant
  before insert on public.cash_ledger
  for each row execute function public.set_tenant_uuid_from_jwt();

alter table public.cash_ledger enable row level security;

-- سياسة قراءة: المستأجر يرى قيود صندوقه فقط.
drop policy if exists cash_ledger_select_own on public.cash_ledger;
create policy cash_ledger_select_own on public.cash_ledger
  for select
  using (tenant_uuid = public.app_current_tenant_id());

-- سياسة إدراج: لا يدخل قيد إلا إذا tenant_uuid يطابق JWT
-- (والـ trigger يضمن أن يكون كذلك).
drop policy if exists cash_ledger_insert_own on public.cash_ledger;
create policy cash_ledger_insert_own on public.cash_ledger
  for insert
  with check (tenant_uuid = public.app_current_tenant_id());

-- سياسة تحديث: لا يحدِّث المستأجر إلا قيوده، ولا يمكنه تغيير tenant_uuid
-- (WITH CHECK يُلزِمه بإبقاء tenant_uuid مساوياً لـ JWT).
drop policy if exists cash_ledger_update_own on public.cash_ledger;
create policy cash_ledger_update_own on public.cash_ledger
  for update
  using (tenant_uuid = public.app_current_tenant_id())
  with check (tenant_uuid = public.app_current_tenant_id());

-- سياسة حذف: لا يحذف المستأجر إلا قيوده.
drop policy if exists cash_ledger_delete_own on public.cash_ledger;
create policy cash_ledger_delete_own on public.cash_ledger
  for delete
  using (tenant_uuid = public.app_current_tenant_id());


-- ----------------------------------------------------------------------------
-- 3.2) work_shifts
--      جدول الورديات — كل وردية تخصّ tenant واحد.
-- ----------------------------------------------------------------------------
do $$ begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'work_shifts'
      and column_name = 'tenant_uuid'
  ) then
    alter table public.work_shifts add column tenant_uuid text;
  end if;
end $$;

create index if not exists idx_work_shifts_tenant_uuid
  on public.work_shifts(tenant_uuid);

drop trigger if exists trg_work_shifts_set_tenant on public.work_shifts;
create trigger trg_work_shifts_set_tenant
  before insert on public.work_shifts
  for each row execute function public.set_tenant_uuid_from_jwt();

alter table public.work_shifts enable row level security;

drop policy if exists work_shifts_select_own on public.work_shifts;
create policy work_shifts_select_own on public.work_shifts
  for select using (tenant_uuid = public.app_current_tenant_id());

drop policy if exists work_shifts_insert_own on public.work_shifts;
create policy work_shifts_insert_own on public.work_shifts
  for insert with check (tenant_uuid = public.app_current_tenant_id());

drop policy if exists work_shifts_update_own on public.work_shifts;
create policy work_shifts_update_own on public.work_shifts
  for update
  using (tenant_uuid = public.app_current_tenant_id())
  with check (tenant_uuid = public.app_current_tenant_id());

drop policy if exists work_shifts_delete_own on public.work_shifts;
create policy work_shifts_delete_own on public.work_shifts
  for delete using (tenant_uuid = public.app_current_tenant_id());


-- ----------------------------------------------------------------------------
-- 3.3) expenses
--      جدول المصاريف — حسّاس مالياً.
-- ----------------------------------------------------------------------------
do $$ begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'expenses') then

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'expenses'
        and column_name = 'tenant_uuid'
    ) then
      alter table public.expenses add column tenant_uuid text;
    end if;

    execute 'create index if not exists idx_expenses_tenant_uuid
             on public.expenses(tenant_uuid)';

    execute 'drop trigger if exists trg_expenses_set_tenant on public.expenses';
    execute 'create trigger trg_expenses_set_tenant
             before insert on public.expenses
             for each row execute function public.set_tenant_uuid_from_jwt()';

    execute 'alter table public.expenses enable row level security';

    execute 'drop policy if exists expenses_select_own on public.expenses';
    execute 'create policy expenses_select_own on public.expenses
             for select using (tenant_uuid = public.app_current_tenant_id())';

    execute 'drop policy if exists expenses_insert_own on public.expenses';
    execute 'create policy expenses_insert_own on public.expenses
             for insert with check (tenant_uuid = public.app_current_tenant_id())';

    execute 'drop policy if exists expenses_update_own on public.expenses';
    execute 'create policy expenses_update_own on public.expenses
             for update
             using (tenant_uuid = public.app_current_tenant_id())
             with check (tenant_uuid = public.app_current_tenant_id())';

    execute 'drop policy if exists expenses_delete_own on public.expenses';
    execute 'create policy expenses_delete_own on public.expenses
             for delete using (tenant_uuid = public.app_current_tenant_id())';
  end if;
end $$;


-- ----------------------------------------------------------------------------
-- 3.4) expense_categories
--      جدول فئات المصاريف — لا يقرأ tenant غيره فئاته.
-- ----------------------------------------------------------------------------
do $$ begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'expense_categories') then

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'expense_categories'
        and column_name = 'tenant_uuid'
    ) then
      alter table public.expense_categories add column tenant_uuid text;
    end if;

    execute 'create index if not exists idx_expense_categories_tenant_uuid
             on public.expense_categories(tenant_uuid)';

    execute 'drop trigger if exists trg_expense_categories_set_tenant on public.expense_categories';
    execute 'create trigger trg_expense_categories_set_tenant
             before insert on public.expense_categories
             for each row execute function public.set_tenant_uuid_from_jwt()';

    execute 'alter table public.expense_categories enable row level security';

    execute 'drop policy if exists expense_categories_select_own on public.expense_categories';
    execute 'create policy expense_categories_select_own on public.expense_categories
             for select using (tenant_uuid = public.app_current_tenant_id())';

    execute 'drop policy if exists expense_categories_insert_own on public.expense_categories';
    execute 'create policy expense_categories_insert_own on public.expense_categories
             for insert with check (tenant_uuid = public.app_current_tenant_id())';

    execute 'drop policy if exists expense_categories_update_own on public.expense_categories';
    execute 'create policy expense_categories_update_own on public.expense_categories
             for update
             using (tenant_uuid = public.app_current_tenant_id())
             with check (tenant_uuid = public.app_current_tenant_id())';

    execute 'drop policy if exists expense_categories_delete_own on public.expense_categories';
    execute 'create policy expense_categories_delete_own on public.expense_categories
             for delete using (tenant_uuid = public.app_current_tenant_id())';
  end if;
end $$;


-- ----------------------------------------------------------------------------
-- 3.5) customer_debt_payments
--      دفعات ديون العملاء — لا يجب أن يرى tenant آخر مدفوعات عملائنا.
-- ----------------------------------------------------------------------------
do $$ begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public' and table_name = 'customer_debt_payments') then

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'customer_debt_payments'
        and column_name = 'tenant_uuid'
    ) then
      alter table public.customer_debt_payments add column tenant_uuid text;
    end if;

    execute 'create index if not exists idx_customer_debt_payments_tenant_uuid
             on public.customer_debt_payments(tenant_uuid)';

    execute 'drop trigger if exists trg_customer_debt_payments_set_tenant on public.customer_debt_payments';
    execute 'create trigger trg_customer_debt_payments_set_tenant
             before insert on public.customer_debt_payments
             for each row execute function public.set_tenant_uuid_from_jwt()';

    execute 'alter table public.customer_debt_payments enable row level security';

    execute 'drop policy if exists customer_debt_payments_select_own on public.customer_debt_payments';
    execute 'create policy customer_debt_payments_select_own on public.customer_debt_payments
             for select using (tenant_uuid = public.app_current_tenant_id())';

    execute 'drop policy if exists customer_debt_payments_insert_own on public.customer_debt_payments';
    execute 'create policy customer_debt_payments_insert_own on public.customer_debt_payments
             for insert with check (tenant_uuid = public.app_current_tenant_id())';

    execute 'drop policy if exists customer_debt_payments_update_own on public.customer_debt_payments';
    execute 'create policy customer_debt_payments_update_own on public.customer_debt_payments
             for update
             using (tenant_uuid = public.app_current_tenant_id())
             with check (tenant_uuid = public.app_current_tenant_id())';

    execute 'drop policy if exists customer_debt_payments_delete_own on public.customer_debt_payments';
    execute 'create policy customer_debt_payments_delete_own on public.customer_debt_payments
             for delete using (tenant_uuid = public.app_current_tenant_id())';
  end if;
end $$;


-- ----------------------------------------------------------------------------
-- 3.6) supplier_bills + supplier_payouts
--      فواتير ودفعات الموردين — معلومات تجارية حسّاسة.
-- ----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['supplier_bills', 'supplier_payouts'] loop
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = t) then

      if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = t and column_name = 'tenant_uuid'
      ) then
        execute format('alter table public.%I add column tenant_uuid text', t);
      end if;

      execute format(
        'create index if not exists %I on public.%I(tenant_uuid)',
        'idx_' || t || '_tenant_uuid', t
      );

      execute format('drop trigger if exists %I on public.%I',
                     'trg_' || t || '_set_tenant', t);
      execute format(
        'create trigger %I before insert on public.%I '
        'for each row execute function public.set_tenant_uuid_from_jwt()',
        'trg_' || t || '_set_tenant', t
      );

      execute format('alter table public.%I enable row level security', t);

      execute format('drop policy if exists %I on public.%I',
                     t || '_select_own', t);
      execute format(
        'create policy %I on public.%I for select '
        'using (tenant_uuid = public.app_current_tenant_id())',
        t || '_select_own', t
      );

      execute format('drop policy if exists %I on public.%I',
                     t || '_insert_own', t);
      execute format(
        'create policy %I on public.%I for insert '
        'with check (tenant_uuid = public.app_current_tenant_id())',
        t || '_insert_own', t
      );

      execute format('drop policy if exists %I on public.%I',
                     t || '_update_own', t);
      execute format(
        'create policy %I on public.%I for update '
        'using (tenant_uuid = public.app_current_tenant_id()) '
        'with check (tenant_uuid = public.app_current_tenant_id())',
        t || '_update_own', t
      );

      execute format('drop policy if exists %I on public.%I',
                     t || '_delete_own', t);
      execute format(
        'create policy %I on public.%I for delete '
        'using (tenant_uuid = public.app_current_tenant_id())',
        t || '_delete_own', t
      );
    end if;
  end loop;
end $$;


-- ----------------------------------------------------------------------------
-- 3.7) installment_plans + installments
--      خطط الأقساط والأقساط نفسها.
-- ----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['installment_plans', 'installments'] loop
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = t) then

      if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = t and column_name = 'tenant_uuid'
      ) then
        execute format('alter table public.%I add column tenant_uuid text', t);
      end if;

      execute format(
        'create index if not exists %I on public.%I(tenant_uuid)',
        'idx_' || t || '_tenant_uuid', t
      );

      execute format('drop trigger if exists %I on public.%I',
                     'trg_' || t || '_set_tenant', t);
      execute format(
        'create trigger %I before insert on public.%I '
        'for each row execute function public.set_tenant_uuid_from_jwt()',
        'trg_' || t || '_set_tenant', t
      );

      execute format('alter table public.%I enable row level security', t);

      execute format('drop policy if exists %I on public.%I',
                     t || '_select_own', t);
      execute format(
        'create policy %I on public.%I for select '
        'using (tenant_uuid = public.app_current_tenant_id())',
        t || '_select_own', t
      );

      execute format('drop policy if exists %I on public.%I',
                     t || '_insert_own', t);
      execute format(
        'create policy %I on public.%I for insert '
        'with check (tenant_uuid = public.app_current_tenant_id())',
        t || '_insert_own', t
      );

      execute format('drop policy if exists %I on public.%I',
                     t || '_update_own', t);
      execute format(
        'create policy %I on public.%I for update '
        'using (tenant_uuid = public.app_current_tenant_id()) '
        'with check (tenant_uuid = public.app_current_tenant_id())',
        t || '_update_own', t
      );

      execute format('drop policy if exists %I on public.%I',
                     t || '_delete_own', t);
      execute format(
        'create policy %I on public.%I for delete '
        'using (tenant_uuid = public.app_current_tenant_id())',
        t || '_delete_own', t
      );
    end if;
  end loop;
end $$;


-- ----------------------------------------------------------------------------
-- 3.8) customers + suppliers (إن وُجدت كجداول على Supabase)
--      البيانات المرجعية للعملاء والموردين.
-- ----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['customers', 'suppliers'] loop
    if exists (select 1 from information_schema.tables
               where table_schema = 'public' and table_name = t) then

      if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = t and column_name = 'tenant_uuid'
      ) then
        execute format('alter table public.%I add column tenant_uuid text', t);
      end if;

      execute format(
        'create index if not exists %I on public.%I(tenant_uuid)',
        'idx_' || t || '_tenant_uuid', t
      );

      execute format('drop trigger if exists %I on public.%I',
                     'trg_' || t || '_set_tenant', t);
      execute format(
        'create trigger %I before insert on public.%I '
        'for each row execute function public.set_tenant_uuid_from_jwt()',
        'trg_' || t || '_set_tenant', t
      );

      execute format('alter table public.%I enable row level security', t);

      execute format('drop policy if exists %I on public.%I',
                     t || '_select_own', t);
      execute format(
        'create policy %I on public.%I for select '
        'using (tenant_uuid = public.app_current_tenant_id())',
        t || '_select_own', t
      );

      execute format('drop policy if exists %I on public.%I',
                     t || '_insert_own', t);
      execute format(
        'create policy %I on public.%I for insert '
        'with check (tenant_uuid = public.app_current_tenant_id())',
        t || '_insert_own', t
      );

      execute format('drop policy if exists %I on public.%I',
                     t || '_update_own', t);
      execute format(
        'create policy %I on public.%I for update '
        'using (tenant_uuid = public.app_current_tenant_id()) '
        'with check (tenant_uuid = public.app_current_tenant_id())',
        t || '_update_own', t
      );

      execute format('drop policy if exists %I on public.%I',
                     t || '_delete_own', t);
      execute format(
        'create policy %I on public.%I for delete '
        'using (tenant_uuid = public.app_current_tenant_id())',
        t || '_delete_own', t
      );
    end if;
  end loop;
end $$;


-- ============================================================================
-- 4) تحصين rpc_process_sync_queue
--    استخدام app_current_tenant_id() بدلاً من (mutation->>'tenantId')::text.
--
--    الحل: نجعل الإصدار العمومي rpc_process_sync_queue حارساً (Guard) يفحص
--    JWT أوّلاً ثم يفوّض المعالجة إلى نسخة داخلية باسم
--    _rpc_process_sync_queue_legacy (تحتوي المنطق نفسه القديم).
--
--    أي محاولة من العميل لإرسال tenantId يخالف JWT تُرفَض بـ raise قبل تنفيذ
--    أي INSERT أو UPDATE — أي قبل وصول البيانات إلى الجداول.
-- ============================================================================
do $$
begin
  -- إعادة تسمية الإصدار القديم مرة واحدة فقط (idempotent).
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_process_sync_queue'
  )
  and not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = '_rpc_process_sync_queue_legacy'
  ) then
    execute 'alter function public.rpc_process_sync_queue(jsonb)
             rename to _rpc_process_sync_queue_legacy';
  end if;
end $$;

-- الواجهة العمومية: حارس JWT.
--
-- ⚠️ ملاحظة توافقيّة (مُضافة في Step 17):
--    Step 17 (20260508_rpc_per_mutation.sql) يبدّل نوع الإرجاع لهذه الدالّة
--    من `void` إلى `jsonb` لإرجاع نتائج per-mutation. لو طُبّق Step 17 ثم
--    أعدنا تشغيل Step 11، فإن `create or replace function ... returns void`
--    سيفشل بـ ERROR 42P13: «cannot change return type of existing function».
--
--    لذلك نلفّ كامل القسم في DO block يكتشف هذا الوضع ويتخطّى الإنشاء بأمان
--    (Step 17 هو المالك الفعلي للدالّة بعد تطبيقه — لا نريد إعادتها إلى void).
do $step11_section4$
declare
  v_returns_jsonb boolean;
begin
  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_process_sync_queue'
      and pg_catalog.format_type(p.prorettype, null) = 'jsonb'
  ) into v_returns_jsonb;

  if v_returns_jsonb then
    raise notice 'Step 17 already applied (rpc_process_sync_queue returns jsonb). '
                 'Skipping Step 11 section 4 to avoid downgrading return type.';
    return;
  end if;

  execute $exec_create$
    create or replace function public.rpc_process_sync_queue(mutations_json jsonb)
    returns void
    language plpgsql
    security definer
    set search_path = public, auth
    as $body$
    declare
      v_tenant_uuid text;
      mutation jsonb;
      v_claim text;
    begin
      -- 1) لا نقبل أي مزامنة من جلسة غير موثَّقة.
      v_tenant_uuid := public.app_current_tenant_id();
      if v_tenant_uuid is null or v_tenant_uuid = '' then
        raise exception 'tenant_unauthenticated: refusing sync without authenticated tenant'
          using errcode = 'P0001';
      end if;

      -- 2) لا نقبل أي mutation يدّعي tenant مختلف عن JWT.
      for mutation in select * from jsonb_array_elements(mutations_json)
      loop
        v_claim := nullif(mutation->>'tenant_uuid', '');
        if v_claim is not null and v_claim is distinct from v_tenant_uuid then
          raise exception
            'tenant_mismatch: client claimed tenant_uuid=% but JWT yields %',
            v_claim, v_tenant_uuid
            using errcode = 'P0001';
        end if;
      end loop;

      -- 3) كل الفحوص نجحت → نفوّض إلى المنطق القديم.
      perform public._rpc_process_sync_queue_legacy(mutations_json);
    end;
    $body$;
  $exec_create$;

  execute $exec_comment$
    comment on function public.rpc_process_sync_queue(jsonb) is
      'Step 11 — حارس JWT لـ rpc_process_sync_queue: يرفض الجلسات غير الموثَّقة '
      'وأي mutation يدّعي tenant مختلف عن JWT، ثم يفوّض إلى '
      '_rpc_process_sync_queue_legacy.';
  $exec_comment$;
end $step11_section4$;


-- ============================================================================
-- نهاية الترحيل.
-- ============================================================================
--
-- =============================================================================
-- ROLLBACK (لإلغاء كل ما سبق — للاستعمال الطارئ فقط)
-- =============================================================================
-- ⚠️ تنفيذ هذا القسم يعطّل RLS كاملاً على الجداول المالية. لا تشغّله إلا
--    في حالة طارئة وبعد اتخاذ قرار صريح.
--
-- 1) إعادة الدالة العمومية للسلوك القديم بدون حارس.
-- do $$
-- begin
--   if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--              where n.nspname = 'public' and p.proname = '_rpc_process_sync_queue_legacy') then
--     drop function if exists public.rpc_process_sync_queue(jsonb);
--     alter function public._rpc_process_sync_queue_legacy(jsonb)
--       rename to rpc_process_sync_queue;
--   end if;
-- end $$;
--
-- 2) إسقاط كل السياسات (تتولّد ديناميكياً، فأمر DROP POLICY لكل اسم):
--    drop policy if exists cash_ledger_select_own  on public.cash_ledger;
--    drop policy if exists cash_ledger_insert_own  on public.cash_ledger;
--    drop policy if exists cash_ledger_update_own  on public.cash_ledger;
--    drop policy if exists cash_ledger_delete_own  on public.cash_ledger;
--    -- … وهكذا لباقي الجداول.
--
-- 3) تعطيل RLS:
--    alter table public.cash_ledger             disable row level security;
--    alter table public.work_shifts             disable row level security;
--    alter table public.expenses                disable row level security;
--    alter table public.expense_categories      disable row level security;
--    alter table public.customer_debt_payments  disable row level security;
--    alter table public.supplier_bills          disable row level security;
--    alter table public.supplier_payouts        disable row level security;
--    alter table public.installment_plans       disable row level security;
--    alter table public.installments            disable row level security;
--    alter table public.customers               disable row level security;
--    alter table public.suppliers               disable row level security;
--
-- 4) إسقاط الـ triggers:
--    drop trigger if exists trg_cash_ledger_set_tenant            on public.cash_ledger;
--    drop trigger if exists trg_work_shifts_set_tenant            on public.work_shifts;
--    drop trigger if exists trg_expenses_set_tenant               on public.expenses;
--    drop trigger if exists trg_expense_categories_set_tenant     on public.expense_categories;
--    drop trigger if exists trg_customer_debt_payments_set_tenant on public.customer_debt_payments;
--    drop trigger if exists trg_supplier_bills_set_tenant         on public.supplier_bills;
--    drop trigger if exists trg_supplier_payouts_set_tenant       on public.supplier_payouts;
--    drop trigger if exists trg_installment_plans_set_tenant      on public.installment_plans;
--    drop trigger if exists trg_installments_set_tenant           on public.installments;
--    drop trigger if exists trg_customers_set_tenant              on public.customers;
--    drop trigger if exists trg_suppliers_set_tenant              on public.suppliers;
--
-- 5) إسقاط الدوال:
--    drop function if exists public.set_tenant_uuid_from_jwt();
--    drop function if exists public.app_current_tenant_id();
--
-- 6) (اختياري) إسقاط عمود tenant_uuid من كل جدول:
--    alter table public.cash_ledger drop column if exists tenant_uuid;
--    -- … وهكذا.
-- =============================================================================
