-- Web device slot policy for app_register_device
-- Compatible with migrations/20260512_register_device_rpc.sql (returns jsonb, atomic).
-- Run in Supabase SQL Editor (or via supabase db query --linked).
--
-- Rules (must match lib/services/web_runtime_policy.dart):
-- - Reclaim inactive web device rows with last_seen_at older than 7 days
--   (same user, platform=web) by updating device_id to the new id.
-- - Else: at most 1 NEW web device registration per user per 24 hours.
-- - Non-web platforms: unchanged limit behavior (max_devices).
-- - Keeps JWT guard + advisory lock + FOR UPDATE from Step 23.

drop function if exists public.app_register_device(text, text, text);

create or replace function public.app_register_device(
  p_device_id text,
  p_device_name text,
  p_platform text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_tenant_id   text;
  v_uid         uuid := auth.uid();
  v_now         timestamptz := now();
  v_max         int;
  v_existing    record;
  v_active      int;
  v_was_known   boolean;
  v_platform    text := lower(trim(coalesce(p_platform, '')));
  v_stale_id    text;
  v_recent_web  int;
begin
  v_tenant_id := public.app_current_tenant_id();
  if v_tenant_id is null or length(trim(v_tenant_id)) = 0 then
    raise exception 'tenant_unauthenticated: refusing app_register_device without authenticated tenant'
      using errcode = 'P0001';
  end if;
  if v_uid is null then
    raise exception 'tenant_unauthenticated: missing auth.uid() under JWT-authenticated session'
      using errcode = 'P0001';
  end if;

  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID: p_device_id must be non-empty'
      using errcode = 'P0001';
  end if;

  perform pg_advisory_xact_lock(hashtext('register_device:' || v_tenant_id)::bigint);

  perform 1
  from public.account_devices d
  where d.user_id = v_uid
  for update;

  select d.access_status, d.device_id is not null as known
    into v_existing
  from public.account_devices d
  where d.user_id = v_uid and d.device_id = p_device_id
  limit 1;

  v_was_known := found;

  if v_was_known and lower(coalesce(v_existing.access_status, 'active')) = 'revoked' then
    select count(*)::int into v_active
    from public.account_devices d
    where d.user_id = v_uid
      and coalesce(d.access_status, 'active') = 'active';

    if v_active > 0 then
      return jsonb_build_object(
        'access_status',      'revoked',
        'is_over_limit',      false,
        'active_devices',     v_active,
        'max_devices',        coalesce(public.app_user_max_devices(), 0),
        'already_registered', true
      );
    end if;
  end if;

  v_max := coalesce(public.app_user_max_devices(), 0);

  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  -- جهاز جديد: سياسات الويب قبل حدّ الخطة.
  if not v_was_known then
    if v_platform = 'web' then
      -- استبدال slot ويب خامد (last_seen_at > 7 أيام) بدل استهلاك جهاز جديد.
      select d.device_id
        into v_stale_id
      from public.account_devices d
      where d.user_id = v_uid
        and lower(coalesce(d.platform, '')) = 'web'
        and coalesce(d.access_status, 'active') = 'active'
        and d.last_seen_at < (v_now - interval '7 days')
      order by d.last_seen_at asc nulls first
      limit 1;

      if v_stale_id is not null then
        update public.account_devices
           set device_id = p_device_id,
               device_name = coalesce(nullif(trim(p_device_name), ''), 'متصفح ويب'),
               platform = 'web',
               last_seen_at = v_now,
               access_status = 'active'
         where user_id = v_uid
           and device_id = v_stale_id;

        select count(*)::int into v_active
        from public.account_devices d
        where d.user_id = v_uid
          and coalesce(d.access_status, 'active') = 'active';

        return jsonb_build_object(
          'access_status',      'active',
          'is_over_limit',      case when v_max = 0 then false else (v_active > v_max) end,
          'active_devices',     v_active,
          'max_devices',        v_max,
          'already_registered', true
        );
      end if;

      -- حدّ أجهزة ويب جديدة: 1 لكل 24 ساعة.
      select count(*)::int into v_recent_web
      from public.account_devices d
      where d.user_id = v_uid
        and lower(coalesce(d.platform, '')) = 'web'
        and d.created_at >= (v_now - interval '24 hours');

      if v_recent_web >= 1 then
        raise exception 'WEB_DEVICE_RATE_LIMIT: at most 1 new web device per 24 hours'
          using errcode = 'P0001';
      end if;
    end if;

    if v_max <> 0 and v_active >= v_max then
      raise exception 'DEVICE_LIMIT_REACHED: tenant=% has % active devices (limit=%)',
        v_tenant_id, v_active, v_max
        using errcode = 'P0001';
    end if;
  end if;

  insert into public.account_devices (
    user_id, device_id, device_name, platform, last_seen_at, created_at, access_status
  ) values (
    v_uid,
    p_device_id,
    coalesce(nullif(trim(p_device_name), ''), 'جهاز غير معروف'),
    nullif(trim(p_platform), ''),
    v_now,
    v_now,
    'active'
  )
  on conflict (user_id, device_id)
  do update set
    device_name   = excluded.device_name,
    platform      = excluded.platform,
    last_seen_at  = excluded.last_seen_at,
    access_status = 'active';

  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  return jsonb_build_object(
    'access_status',      'active',
    'is_over_limit',      case when v_max = 0 then false else (v_active > v_max) end,
    'active_devices',     v_active,
    'max_devices',        v_max,
    'already_registered', v_was_known
  );
end;
$$;

comment on function public.app_register_device(text, text, text) is
  'Atomic device register (JWT + advisory lock + FOR UPDATE) + web slot policy '
  '(reclaim web last_seen>7d; max 1 new web device / 24h). Returns jsonb.';

revoke all on function public.app_register_device(text, text, text) from public;
grant execute on function public.app_register_device(text, text, text) to authenticated;
