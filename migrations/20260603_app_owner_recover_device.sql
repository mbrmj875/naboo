-- استعادة جهاز صاحب العمل بعد التحقق من OTP البريد (على العميل).
-- يفعّل الجهاز الحالي ويفصل الأجهزة الأخرى اختيارياً.

create or replace function public.app_owner_recover_device(
  p_device_id text,
  p_revoke_other_devices boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_active int;
  v_updated int;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID' using errcode = 'P0001';
  end if;

  if p_revoke_other_devices then
    update public.account_devices
    set access_status = 'revoked'
    where user_id = v_uid
      and device_id <> p_device_id
      and coalesce(access_status, 'active') = 'active';
  end if;

  update public.account_devices
  set access_status = 'active',
      last_seen_at  = v_now
  where user_id = v_uid
    and device_id = p_device_id;

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'DEVICE_NOT_FOUND: no row for this device_id'
      using errcode = 'P0001';
  end if;

  select count(*)::int into v_active
  from public.account_devices d
  where d.user_id = v_uid
    and coalesce(d.access_status, 'active') = 'active';

  return jsonb_build_object(
    'access_status',  'active',
    'active_devices', v_active,
    'device_id',      p_device_id
  );
end;
$$;

revoke all on function public.app_owner_recover_device(text, boolean) from public;
grant execute on function public.app_owner_recover_device(text, boolean) to authenticated;
