-- نظام الترخيص المعتمد لكل ملف شخصي: v2 (JWT موقّع) دائماً.

alter table public.profiles
  add column if not exists license_system_version text not null default 'v2';

alter table public.profiles
  alter column license_system_version set default 'v2';

update public.profiles
set license_system_version = 'v2'
where license_system_version is distinct from 'v2';

do $$
begin
  alter table public.profiles
    drop constraint if exists profiles_license_system_version_check;
  alter table public.profiles
    add constraint profiles_license_system_version_check
    check (license_system_version = 'v2');
end $$;

comment on column public.profiles.license_system_version is
  'v2 only: signed JWT + device UUID.';
