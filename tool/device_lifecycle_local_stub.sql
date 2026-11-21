/*
  نسخة محلية مصغّرة (stub) لمخطط Supabase اللازم لاختبار
  migrations/20261020_device_lifecycle_fix.sql بدون لمس الإنتاج.

  الاستخدام (PostgreSQL 14+ محلي):
    createdb naboo_devtest
    psql naboo_devtest -v ON_ERROR_STOP=1 -f tool/device_lifecycle_local_stub.sql
    # حالة الإنتاج الحالية = الدوال القديمة (من ملف التراجع):
    psql naboo_devtest -v ON_ERROR_STOP=1 -f migrations/20261020_device_lifecycle_fix.rollback.sql
    psql naboo_devtest -f migrations/20261020_device_lifecycle_fix.sql
    psql naboo_devtest -f migrations/20261020_device_lifecycle_fix.test.sql
    # المتوقع: ERROR:  TEST_PASSED_AND_ROLLED_BACK: A1 A2 ...

  هذا stub لسلوك auth.uid()/auth.jwt()/auth.role() فقط، وليس نسخة من Supabase.
*/

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon')          then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role')  then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;

create table if not exists auth.users (id uuid primary key);

create or replace function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$$;
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid;
$$;
create or replace function auth.role() returns text language sql stable as $$
  select nullif(auth.jwt() ->> 'role', '');
$$;

grant usage on schema public to anon, authenticated, service_role;

create table if not exists public.licenses (
  id               bigserial primary key,
  license_key      text not null unique,
  status           text not null default 'trial',
  plan             text not null default 'basic',
  max_devices      int  not null default 2,
  assigned_user_id uuid references auth.users(id) on delete set null
);

create table if not exists public.account_devices (
  id            bigserial primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  device_id     text not null,
  device_name   text not null,
  platform      text,
  last_seen_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  access_status text not null default 'active',
  constraint account_devices_user_id_device_id_key unique (user_id, device_id),
  constraint account_devices_access_status_check check (access_status in ('active','revoked'))
);
create index if not exists idx_account_devices_user_last_seen on public.account_devices (user_id, last_seen_at desc);
create index if not exists idx_account_devices_user_status on public.account_devices (user_id, access_status);

alter table public.account_devices enable row level security;
drop policy if exists devices_own_select on public.account_devices;
drop policy if exists devices_own_write  on public.account_devices;
create policy devices_own_select on public.account_devices for select using (auth.uid() = user_id);
create policy devices_own_write  on public.account_devices for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
grant select, insert, update, delete on public.account_devices to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- كما في الإنتاج (pg_get_functiondef بتاريخ 2026-10-20)
create or replace function public.app_current_tenant_id()
returns text language sql stable security definer set search_path to 'public', 'auth' as $function$
  select coalesce(
    nullif(auth.jwt() ->> 'tenant_id', ''),
    nullif(auth.jwt() ->> 'sub', ''),
    case when auth.uid() is not null then 'local-' || auth.uid()::text else null end
  );
$function$;

create or replace function public.app_user_max_devices()
returns integer language sql stable as $function$
  select coalesce(
    (
      select l.max_devices
      from public.licenses l
      where l.assigned_user_id = auth.uid()
        and lower(coalesce(l.status, '')) in ('active', 'trial')
      order by
        case lower(coalesce(l.plan, '')) when 'lifetime' then 0 when 'annual' then 1 when 'monthly' then 2 else 9 end,
        coalesce(l.max_devices, 0) desc,
        case lower(coalesce(l.status, '')) when 'active' then 0 when 'trial' then 1 else 9 end,
        l.id desc
      limit 1
    ),
    2
  )::int;
$function$;

-- trigger الإنتاج الحالي (الدوال تُنشأ من ملف التراجع الذي يحمل نسخ الإنتاج)
create or replace function public.prevent_device_self_unrevoke() returns trigger language plpgsql as $f$ begin return new; end $f$;
drop trigger if exists trg_prevent_device_self_unrevoke on public.account_devices;
create trigger trg_prevent_device_self_unrevoke
  before update on public.account_devices
  for each row execute function public.prevent_device_self_unrevoke();
