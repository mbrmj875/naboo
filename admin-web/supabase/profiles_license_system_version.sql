-- نظام الترخيص لكل ملف شخصي: v1 (مفتاح الجدول التقليدي) أو v2 (JWT موقّع).
-- الإيقاف الطارئ (kill switch): ضبط المستخدم على v1 من لوحة الإدارة.

alter table public.profiles
  add column if not exists license_system_version text not null default 'v1';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_license_system_version_check'
  ) then
    alter table public.profiles
      add constraint profiles_license_system_version_check
      check (license_system_version in ('v1', 'v2'));
  end if;
end $$;

comment on column public.profiles.license_system_version is
  'v1 = legacy license_key flow; v2 = signed JWT + device UUID. Admin kill switch: set v1.';
