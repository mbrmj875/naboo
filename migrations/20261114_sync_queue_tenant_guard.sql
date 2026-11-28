-- المرحلة 1 (جزء الخادم): حارس الحساب في طابور المزامنة (14 نوفمبر 2026).
--
-- المشكلة (مثبتة من تعريفات الخادم):
--   _rpc_process_sync_queue_legacy_base يملكها postgres وتعمل SECURITY DEFINER،
--   فتتجاوز سياسات RLS. تحذف وتحدّث cash_ledger وwork_shifts بـ global_id فقط:
--     DELETE FROM cash_ledger WHERE global_id = ...
--     ON CONFLICT (global_id) DO UPDATE SET tenant_id = ..., amount = ...
--   فحساب يعرف global_id لسطر حساب آخر يستطيع حذفه أو تغييره. المعرّف عشوائي
--   طويل، فالخطر منخفض، لكنه يكسر عزل الحسابات.
--   الإدراج سليم: trg_*_set_tenant يختم tenant_uuid من JWT دائماً.
--   جدول expenses غير موجود على الخادم، فحذف المصروف يفشل ويُتراجع عنه كاملاً.
--
-- الحل: مشغّل قبل التحديث والحذف على الجدولين يطبق نفس شرط سياسات RLS
-- الموجودة (tenant_uuid = app_current_tenant_id()) على طلبات التطبيق
-- (anon/authenticated) حتى داخل الدوال المالكة:
--   * سطر حساب آخر: يُتخطى بصمت (return null). الطابور يرد "تم" كعادته،
--     فلا يعيد الجهاز المحاولة إلى ما لا نهاية.
--   * التحديث لا يغيّر tenant_uuid أبداً.
--   * طلبات الخادم والإدارة (service_role/postgres) لا تتأثر.
-- لا يغيّر دالة الطابور ولا التطبيق. الطابور هو الكاتب الوحيد لهذين الجدولين
-- (بحث في دوال الخادم وlib وadmin-web وsupabase/functions).
--
-- الرجوع: 20261114_sync_queue_tenant_guard.rollback.sql

create or replace function public.fn_guard_tenant_row_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant text;
begin
  if coalesce(auth.role(), '') not in ('anon', 'authenticated') then
    return coalesce(new, old);
  end if;
  v_tenant := public.app_current_tenant_id();
  if v_tenant is null or old.tenant_uuid is distinct from v_tenant then
    return null;
  end if;
  if tg_op = 'UPDATE' then
    new.tenant_uuid := old.tenant_uuid;
    return new;
  end if;
  return old;
end;
$$;
revoke all on function public.fn_guard_tenant_row_write() from public, anon, authenticated;

drop trigger if exists trg_guard_tenant_row_write on public.cash_ledger;
create trigger trg_guard_tenant_row_write
before update or delete on public.cash_ledger
for each row execute function public.fn_guard_tenant_row_write();

drop trigger if exists trg_guard_tenant_row_write on public.work_shifts;
create trigger trg_guard_tenant_row_write
before update or delete on public.work_shifts
for each row execute function public.fn_guard_tenant_row_write();
