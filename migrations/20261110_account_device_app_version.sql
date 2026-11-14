-- نسخة التطبيق لكل جهاز: لمعرفة أي جهاز ما زال على نسخة قديمة.
-- النسخة القديمة تغيّر كلمة Supabase الداخلية عند الدخول فتُخرج بقية أجهزة
-- الحساب، ولا نعرف اليوم من حدّث ومن لم يحدّث.
--
-- آمن على الأجهزة القديمة: عمودان يقبلان الفراغ ودالة جديدة. لا تتغير
-- app_register_device ولا أي سياسة. الجهاز القديم لا يستدعي الدالة فيبقى
-- عموده فارغاً، وهذا نفسه يدل على أنه قديم.
--
-- الرجوع:
--   drop function if exists public.app_report_device_version(text, text);
--   alter table public.account_devices
--     drop column if exists app_version,
--     drop column if exists app_version_reported_at;

alter table public.account_devices
  add column if not exists app_version text,
  add column if not exists app_version_reported_at timestamptz;

create or replace function public.app_report_device_version(
  p_device_id text,
  p_app_version text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_version text := trim(coalesce(p_app_version, ''));
begin
  if v_uid is null then
    raise exception 'tenant_unauthenticated' using errcode = 'P0001';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID' using errcode = 'P0001';
  end if;
  -- مثل 2.2.43+267. نرفض أي نص آخر حتى لا يُخزَّن محتوى عشوائي.
  if v_version !~ '^[0-9]{1,3}(\.[0-9]{1,4}){1,3}(\+[0-9]{1,7})?$' then
    raise exception 'INVALID_APP_VERSION' using errcode = 'P0001';
  end if;

  -- صف الجهاز نفسه فقط، ولا كتابة إن لم تتغير النسخة.
  update public.account_devices d
     set app_version = v_version,
         app_version_reported_at = now()
   where d.user_id = v_uid
     and d.device_id = p_device_id
     and d.app_version is distinct from v_version;
end;
$$;

revoke all on function public.app_report_device_version(text, text) from public;
revoke all on function public.app_report_device_version(text, text) from anon;
grant execute on function public.app_report_device_version(text, text) to authenticated;
