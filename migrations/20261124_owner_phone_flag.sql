-- خطة الإشعارات، المرحلة 1، البند 5ب: علامة «هاتف المالك».
-- docs/specs/notifications_master_plan_ar.md (خامسا، البند 8).
--
-- فوق الموجود، بلا جداول جديدة:
--   - عمود owner_notify على account_devices.
--   - دالة واحدة app_set_owner_notify_device (على نمط app_report_device_version).
--   - حارس: لا يتغير العمود إلا من هذه الدالة (نفس أسلوب app.device_source).
--   - فصل الجهاز يُسقط العلامة.
--   - كل تغيير يُسجَّل في account_device_events.
--   - فهرس صغير على الأجهزة المعلَّمة.
--
-- التحقق من رمز المالك يجري في التطبيق (verifyOwnerConfirmationCredential) قبل استدعاء الدالة.
-- النسخ القديمة من التطبيق لا تعرف العمود: لا ترسله، فلا تتأثر.

alter table public.account_devices
  add column if not exists owner_notify boolean not null default false,
  add column if not exists owner_notify_at timestamptz;

create index if not exists account_devices_owner_notify_idx
  on public.account_devices (user_id)
  where owner_notify;

-- ─── الحارس ────────────────────────────────────────────────────────────────
create or replace function public.guard_account_device_owner_notify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- الجهاز المفصول لا يبقى هاتف مالك، أيا كان مصدر الفصل.
  if lower(coalesce(new.access_status, 'active')) = 'revoked' then
    new.owner_notify := false;
    if tg_op = 'INSERT' or old.owner_notify then
      new.owner_notify_at := now();
    end if;
    return new;
  end if;

  -- الخادم (service_role) ولوحة الإدارة بلا هوية مستخدم: بلا قيد.
  if coalesce(auth.role(), '') not in ('anon', 'authenticated') or auth.uid() is null then
    return new;
  end if;

  if coalesce(current_setting('app.device_source', true), '') = 'rpc:owner_notify' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.owner_notify then
      raise exception 'OWNER_NOTIFY_RPC_ONLY' using errcode = 'P0001';
    end if;
  elsif new.owner_notify is distinct from old.owner_notify
     or new.owner_notify_at is distinct from old.owner_notify_at then
    raise exception 'OWNER_NOTIFY_RPC_ONLY' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_account_device_owner_notify on public.account_devices;
create trigger trg_guard_account_device_owner_notify
  before insert or update on public.account_devices
  for each row execute function public.guard_account_device_owner_notify();

-- ─── الدالة ────────────────────────────────────────────────────────────────
-- تشغيل العلامة يكون من الجهاز نفسه (البطاقة أو المفتاح)، وإزالتها من أي جهاز
-- في قائمة الأجهزة. الخادم لا يعرف أي جهاز يستدعي، فيقبل الحالتين لأجهزة الحساب نفسه.
create or replace function public.app_set_owner_notify_device(
  p_device_id text,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_status text;
  v_old boolean;
begin
  if v_uid is null then
    raise exception 'tenant_unauthenticated' using errcode = 'P0001';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID' using errcode = 'P0001';
  end if;
  if p_enabled is null then
    raise exception 'INVALID_ENABLED' using errcode = 'P0001';
  end if;

  select d.access_status, d.owner_notify
    into v_status, v_old
    from public.account_devices d
   where d.user_id = v_uid and d.device_id = p_device_id
   for update;

  if not found then
    raise exception 'DEVICE_NOT_FOUND' using errcode = 'P0001';
  end if;
  if p_enabled and lower(coalesce(v_status, 'active')) = 'revoked' then
    raise exception 'DEVICE_REVOKED' using errcode = 'P0001';
  end if;
  if v_old = p_enabled then
    return;
  end if;

  perform set_config('app.device_source', 'rpc:owner_notify', true);

  update public.account_devices d
     set owner_notify = p_enabled,
         owner_notify_at = now()
   where d.user_id = v_uid and d.device_id = p_device_id;

  insert into public.account_device_events
    (user_id, device_id, event_type, old_status, new_status,
     source, actor_uid, actor_role, actor_session_id)
  values
    (v_uid, p_device_id,
     case when p_enabled then 'owner_notify_on' else 'owner_notify_off' end,
     v_status, v_status,
     'rpc:owner_notify', v_uid, auth.role(),
     nullif(auth.jwt() ->> 'session_id', ''));

  perform set_config('app.device_source', '', true);
end;
$$;

revoke all on function public.app_set_owner_notify_device(text, boolean) from public, anon;
grant execute on function public.app_set_owner_notify_device(text, boolean) to authenticated;

-- للخادم: هل للحساب هاتف مالك واحد على الأقل؟ (قاعدة الحجب في notify-dispatch)
create or replace function public.account_has_owner_phone(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.account_devices d
     where d.user_id = p_user_id
       and d.owner_notify
       and d.access_status = 'active'
  );
$$;

revoke all on function public.account_has_owner_phone(uuid) from public, anon, authenticated;
grant execute on function public.account_has_owner_phone(uuid) to service_role;
