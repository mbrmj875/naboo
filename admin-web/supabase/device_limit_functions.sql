-- Device limit enforcement (server-side) + over-limit status RPC
--
-- Run in Supabase SQL Editor.
-- Requirements:
-- - Table public.account_devices exists with columns:
--   user_id (uuid), device_id (text), device_name (text), platform (text),
--   last_seen_at (timestamptz), created_at (timestamptz), access_status (text)
-- - Licenses table contains assigned_user_id (uuid), max_devices (int), status (text)
--   (this repo already uses licenses.assigned_user_id in admin-web).
--
-- Notes:
-- - max_devices == 0 means unlimited.
-- - is_over_limit is computed on the server only.
-- - New device registration is rejected on the server if the limit is reached.

create or replace function public.app_user_max_devices()
returns int
language sql
stable
as $$
  select
    coalesce(
      (
        select l.max_devices
        from public.licenses l
        where l.assigned_user_id = auth.uid()
          and lower(coalesce(l.status, '')) in ('active', 'trial')
        order by
          case lower(coalesce(l.status,'')) when 'active' then 0 when 'trial' then 1 else 9 end,
          l.id desc
        limit 1
      ),
      2
    )::int;
$$;

create or replace function public.app_device_limit_status()
returns table (
  is_over_limit boolean,
  active_devices int,
  max_devices int
)
language sql
stable
as $$
  with lim as (
    select public.app_user_max_devices()::int as max_devices
  ),
  dev as (
    select count(*)::int as active_devices
    from public.account_devices d
    where d.user_id = auth.uid()
      and coalesce(d.access_status, 'active') = 'active'
  )
  select
    case
      when lim.max_devices = 0 then false
      when dev.active_devices > lim.max_devices then true
      else false
    end as is_over_limit,
    dev.active_devices,
    lim.max_devices
  from lim, dev;
$$;

create or replace function public.app_register_device(
  p_device_id text,
  p_device_name text,
  p_platform text
)
returns table (
  access_status text,
  is_over_limit boolean,
  active_devices int,
  max_devices int,
  already_registered boolean
)
language plpgsql
security definer
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_max int := public.app_user_max_devices();
  v_existing record;
  v_active int;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID';
  end if;

  -- Fetch existing row (if any).
  select d.access_status
    into v_existing
  from public.account_devices d
  where d.user_id = v_uid and d.device_id = p_device_id
  limit 1;

  -- If revoked, keep revoked.
  if found and lower(coalesce(v_existing.access_status,'active')) = 'revoked' then
    return query
      select 'revoked'::text,
             false::boolean,
             0::int,
             v_max::int,
             true::boolean;
    return;
  end if;

  -- Count active devices (server truth).
  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  -- New device registration is rejected if limit reached.
  if not found then
    if v_max <> 0 and v_active >= v_max then
      raise exception 'DEVICE_LIMIT_REACHED';
    end if;
  end if;

  -- Upsert device row.
  insert into public.account_devices (
    user_id, device_id, device_name, platform, last_seen_at, created_at, access_status
  ) values (
    v_uid, p_device_id, coalesce(nullif(trim(p_device_name),''),'جهاز غير معروف'),
    nullif(trim(p_platform),''),
    v_now, v_now, 'active'
  )
  on conflict (user_id, device_id)
  do update set
    device_name = excluded.device_name,
    platform = excluded.platform,
    last_seen_at = excluded.last_seen_at,
    access_status = 'active';

  -- Recount after upsert.
  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  return query
    select 'active'::text,
           case when v_max = 0 then false else (v_active > v_max) end as is_over_limit,
           v_active::int,
           v_max::int,
           true::boolean;
end;
$$;

-- Restrict SECURITY DEFINER privileges to authenticated only.
revoke all on function public.app_register_device(text,text,text) from public;
grant execute on function public.app_register_device(text,text,text) to authenticated;

