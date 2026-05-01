-- Security audit logs (minimal, no sensitive payloads)
--
-- Run in Supabase SQL Editor.
--
-- Table columns follow the spec:
-- event, tenant_id, device_id, timestamp, app_version, platform, was_offline, context
--
-- Notes:
-- - tenant_id here is treated as the Auth user id (uuid) for now.
--   Later, if you add true multi-tenant orgs, migrate this column accordingly.
-- - Insert is allowed for authenticated users for their own tenant_id only.
-- - Read is denied by default (admin-web should use service_role).
-- - Retention follows the spec:
--   - routine: 30 days
--   - security: 365 days
--   - critical: permanent (no auto-delete)

create table if not exists public.security_audit_logs (
  id bigserial primary key,
  tenant_id uuid not null,
  user_id uuid not null,
  device_id text not null,
  event text not null,
  event_tier text not null default 'security',
  app_version text not null,
  platform text not null,
  was_offline boolean not null default false,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'security_audit_logs'
      and column_name = 'event_tier'
  ) then
    alter table public.security_audit_logs
      add column event_tier text not null default 'security';
  end if;
exception when others then null;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'security_audit_logs_event_tier_check'
  ) then
    alter table public.security_audit_logs
      add constraint security_audit_logs_event_tier_check
      check (event_tier in ('routine','security','critical'));
  end if;
exception when others then null;
end $$;

create index if not exists idx_security_audit_logs_tenant_created
  on public.security_audit_logs(tenant_id, created_at desc);

alter table public.security_audit_logs enable row level security;

-- Allow insert only for own tenant_id/user_id.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'security_audit_logs'
      and policyname = 'security_audit_logs_insert_own'
  ) then
    create policy security_audit_logs_insert_own
      on public.security_audit_logs
      for insert
      to authenticated
      with check (
        user_id = auth.uid()
        and tenant_id = auth.uid()
      );
  end if;
exception when others then null;
end $$;

-- Explicitly deny select/update/delete for authenticated clients (server/admin only).
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'security_audit_logs'
      and policyname = 'security_audit_logs_no_read'
  ) then
    create policy security_audit_logs_no_read
      on public.security_audit_logs
      for select
      to authenticated
      using (false);
  end if;
exception when others then null;
end $$;

-- Retention (configure via pg_cron or Supabase scheduled job).
-- Example (requires pg_cron enabled) — deletes routine/security only:
-- select cron.schedule(
--   'security_audit_logs_retention',
--   '0 4 * * *',
--   $$
--   delete from public.security_audit_logs
--   where
--     (event_tier = 'routine' and created_at < now() - interval '30 days')
--     or
--     (event_tier = 'security' and created_at < now() - interval '365 days');
--   $$
-- );

