-- قفل عمليات / حد معدل / سجل تدقيق لبوابة واتساب المحل
-- نفّذ في Supabase SQL Editor ثم أعد نشر whatsapp-gateway.

alter table public.tenant_whatsapp_gateways
  add column if not exists operation_lock_until timestamptz,
  add column if not exists last_hard_reset_at timestamptz,
  add column if not exists last_reset_reason text,
  add column if not exists last_reset_source text;

comment on column public.tenant_whatsapp_gateways.operation_lock_until is
  'قفل مؤقت لمنع logout/QR متزامن على نفس الحساب';
comment on column public.tenant_whatsapp_gateways.last_hard_reset_at is
  'آخر hardReset (logout+restart) — لحد المعدل';
comment on column public.tenant_whatsapp_gateways.last_reset_reason is
  'سبب آخر hardReset';
comment on column public.tenant_whatsapp_gateways.last_reset_source is
  'مصدر آخر hardReset: user_disconnect | user_force_reset | server_qr_fallback';

create table if not exists public.whatsapp_gateway_audit (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  instance_name text not null,
  action text not null,
  source text not null,
  detail text,
  meta jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_whatsapp_gateway_audit_user_created
  on public.whatsapp_gateway_audit (user_id, created_at desc);

alter table public.whatsapp_gateway_audit enable row level security;

drop policy if exists whatsapp_gateway_audit_own_select on public.whatsapp_gateway_audit;
create policy whatsapp_gateway_audit_own_select
  on public.whatsapp_gateway_audit
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists whatsapp_gateway_audit_own_insert on public.whatsapp_gateway_audit;
create policy whatsapp_gateway_audit_own_insert
  on public.whatsapp_gateway_audit
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- قفل ذري لحساب المستخدم الحالي (من JWT).
create or replace function public.acquire_whatsapp_gateway_lock(
  p_ttl_seconds integer default 45
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  updated integer := 0;
  lock_until timestamptz;
  instance_name text;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  instance_name := 'shop_' || replace(uid::text, '-', '_');
  lock_until := now() + make_interval(secs => greatest(5, least(coalesce(p_ttl_seconds, 45), 120)));

  insert into public.tenant_whatsapp_gateways as t (
    user_id,
    evolution_instance_name,
    status,
    operation_lock_until,
    updated_at
  ) values (
    uid,
    instance_name,
    'unknown',
    lock_until,
    now()
  )
  on conflict (user_id) do update
  set
    operation_lock_until = excluded.operation_lock_until,
    updated_at = now()
  where
    t.operation_lock_until is null
    or t.operation_lock_until < now();

  get diagnostics updated = row_count;

  if updated = 0 then
    return jsonb_build_object(
      'ok', false,
      'error', 'locked',
      'operation_lock_until', (
        select operation_lock_until
        from public.tenant_whatsapp_gateways
        where user_id = uid
      )
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'operation_lock_until', lock_until,
    'instance_name', instance_name
  );
end;
$$;

revoke all on function public.acquire_whatsapp_gateway_lock(integer) from public;
grant execute on function public.acquire_whatsapp_gateway_lock(integer) to authenticated;

create or replace function public.release_whatsapp_gateway_lock()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  update public.tenant_whatsapp_gateways
  set operation_lock_until = null, updated_at = now()
  where user_id = uid;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.release_whatsapp_gateway_lock() from public;
grant execute on function public.release_whatsapp_gateway_lock() to authenticated;
