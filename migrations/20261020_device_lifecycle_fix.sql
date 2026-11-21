/*
  20261020 — إصلاح دورة حياة الأجهزة (account_devices)

  المشكلة: جهاز "مفصول" لا يستطيع العودة ما دام أي جهاز آخر نشطاً (حتى لو العدد
  أقل من حدّ الخطة)، والمخرج الوحيد (استعادة المالك بـ OTP) يفصل كل الأجهزة
  الأخرى ⇒ حلقة ping-pong بين الأجهزة. التفاصيل: docs/device_lifecycle_incident_2026-10-20.md

  ما يفعله هذا الملف (كله server-side، متوافق مع نسخ التطبيق الحالية):
    1) جدول تدقيق account_device_events + trigger يسجّل كل تغيير في access_status
       (من فصل من، عبر أي مسار، ومن أي جلسة auth).
    2) app_register_device: الجهاز المفصول يعود active إذا كان هناك مكان ضمن الحد.
       (نافذة سماح 30 ثانية بعد الفصل حتى لا يُلغي heartbeat عالق فصلاً يدوياً.)
    3) app_owner_recover_device: لا يفصل "الكل" — يفصل فقط الأقدم نشاطاً وبالقدر
       اللازم لإفساح مكان، وعند وجود مكان لا يفصل أحداً.
    4) prevent_device_self_unrevoke: يسمح بإلغاء الفصل عندما يوجد مكان ضمن الحد
       (يعمل زر "السماح من جهاز نشط")، ويرفضه عند الامتلاء.

  ما لا يفعله:
    - لا يعدّل أي صف في account_devices ⇒ لا أحداث Realtime ⇒ لا يُطرد أحد.
    - لا يضيف أعمدة إلى account_devices (لا ALTER عليه).
    - لا يعالج الـ dedupe الذي يتم داخل التطبيق (يحتاج نسخة تطبيق).

  التطبيق: شغّله كدفعة واحدة. أي فشل ⇒ rollback كامل تلقائياً (معاملة واحدة).
  التراجع: 20261020_device_lifecycle_fix.rollback.sql
*/

begin;

-- لا ننتظر قفلاً أكثر من 3 ثوانٍ (أجهزة شغّالة تستدعي app_register_device الآن).
set local lock_timeout = '3s';
set local statement_timeout = '30s';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) جدول التدقيق (append-only)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.account_device_events (
  id               bigint generated always as identity primary key,
  user_id          uuid        not null,           -- بلا FK عمداً: يبقى السجل بعد حذف المستخدم/الجهاز
  device_id        text        not null,
  event_type       text        not null,           -- insert | status_change | delete
  old_status       text,
  new_status       text,
  source           text        not null default 'direct',  -- rpc:<fn> أو direct (UPDATE مباشر من التطبيق)
  actor_uid        uuid,
  actor_role       text,
  actor_session_id text,                           -- auth.jwt()->>'session_id' ⇒ ربط مع auth.sessions.user_agent
  created_at       timestamptz not null default now()
);

create index if not exists idx_account_device_events_user_device_time
  on public.account_device_events (user_id, device_id, created_at desc);
create index if not exists idx_account_device_events_user_time
  on public.account_device_events (user_id, created_at desc);

alter table public.account_device_events enable row level security;

drop policy if exists device_events_own_select on public.account_device_events;
create policy device_events_own_select
  on public.account_device_events
  for select
  using (auth.uid() = user_id);

-- قراءة فقط للمستخدم؛ الكتابة حصراً عبر trigger (security definer).
revoke all on public.account_device_events from anon, authenticated;
grant select on public.account_device_events to authenticated;

create or replace function public.log_account_device_change()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_source text := coalesce(nullif(current_setting('app.device_source', true), ''), 'direct');
  v_session text;
begin
  -- التدقيق لا يجوز أن يكسر تسجيل الجهاز أبداً.
  begin
    v_session := nullif(auth.jwt() ->> 'session_id', '');

    if tg_op = 'INSERT' then
      insert into public.account_device_events
        (user_id, device_id, event_type, old_status, new_status,
         source, actor_uid, actor_role, actor_session_id)
      values
        (new.user_id, new.device_id, 'insert', null, new.access_status,
         v_source, auth.uid(), auth.role(), v_session);

    elsif tg_op = 'UPDATE' then
      if old.access_status is distinct from new.access_status then
        insert into public.account_device_events
          (user_id, device_id, event_type, old_status, new_status,
           source, actor_uid, actor_role, actor_session_id)
        values
          (new.user_id, new.device_id, 'status_change', old.access_status, new.access_status,
           v_source, auth.uid(), auth.role(), v_session);
      end if;

    elsif tg_op = 'DELETE' then
      insert into public.account_device_events
        (user_id, device_id, event_type, old_status, new_status,
         source, actor_uid, actor_role, actor_session_id)
      values
        (old.user_id, old.device_id, 'delete', old.access_status, null,
         v_source, auth.uid(), auth.role(), v_session);
    end if;
  exception when others then
    null;
  end;
  return null; -- AFTER trigger
end;
$function$;

revoke all on function public.log_account_device_change() from public, anon, authenticated;

drop trigger if exists trg_log_account_device_change on public.account_devices;
create trigger trg_log_account_device_change
  after insert or update of access_status or delete
  on public.account_devices
  for each row execute function public.log_account_device_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) trigger: السماح بإلغاء الفصل عندما يوجد مكان ضمن الحد
--    (كان يمنعه دائماً ما دام أي جهاز آخر نشطاً ⇒ زر "السماح" لا ينجح أبداً)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.prevent_device_self_unrevoke()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_max    int;
  v_active int;
begin
  if coalesce(auth.role(), '') = 'service_role' then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and lower(coalesce(old.access_status, 'active')) = 'revoked'
     and lower(coalesce(new.access_status, 'active')) is distinct from 'revoked' then

    -- SQL المباشر بدون هوية مستخدم (لوحة الإدارة): لا قيد.
    if auth.uid() is null then
      return new;
    end if;

    v_max := coalesce(public.app_user_max_devices(), 0);
    if v_max <> 0 then
      select count(*)::int into v_active
      from public.account_devices d
      where d.user_id = new.user_id
        and d.device_id is distinct from new.device_id
        and lower(coalesce(d.access_status, 'active')) <> 'revoked';

      if v_active >= v_max then
        raise exception 'cannot_unrevoke_device_limit_reached: active=% max=%', v_active, v_max;
      end if;
    end if;
  end if;
  return new;
end;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) app_register_device: عودة الجهاز المفصول عند وجود مكان
--    التغيير الوحيد عن النسخة المنشورة: كتلة "known + revoked" + تسجيل المصدر.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.app_register_device(
  p_device_id text,
  p_device_name text,
  p_platform text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
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
  v_revoked_at  timestamptz;
  v_result      jsonb;
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

  perform set_config('app.device_source', 'rpc:app_register_device', true);

  select d.access_status, d.device_id is not null as known
    into v_existing
  from public.account_devices d
  where d.user_id = v_uid and d.device_id = p_device_id
  limit 1;

  v_was_known := found;

  if v_was_known and lower(coalesce(v_existing.access_status, 'active')) = 'revoked' then
    v_max := coalesce(public.app_user_max_devices(), 0);

    select count(*)::int into v_active
    from public.account_devices d
    where d.user_id = v_uid
      and coalesce(d.access_status, 'active') = 'active';

    -- (أ) نافذة سماح 30 ثانية بعد الفصل: heartbeat عالق من الجهاز المفصول للتوّ
    --     يجب ألا يُلغي الفصل (Realtime يطرد الجهاز خلال ثوانٍ).
    select max(e.created_at) into v_revoked_at
    from public.account_device_events e
    where e.user_id = v_uid
      and e.device_id = p_device_id
      and e.new_status = 'revoked';

    if v_revoked_at is not null and v_revoked_at > v_now - interval '30 seconds' then
      v_result := jsonb_build_object(
        'access_status',      'revoked',
        'is_over_limit',      false,
        'active_devices',     v_active,
        'max_devices',        v_max,
        'already_registered', true,
        'reason',             'recently_revoked'
      );
      perform set_config('app.device_source', '', true);
      return v_result;
    end if;

    -- (ب) لا مكان ضمن الحد ⇒ يبقى مفصولاً.
    if v_max <> 0 and v_active >= v_max then
      v_result := jsonb_build_object(
        'access_status',      'revoked',
        'is_over_limit',      false,
        'active_devices',     v_active,
        'max_devices',        v_max,
        'already_registered', true,
        'reason',             'device_limit_reached'
      );
      perform set_config('app.device_source', '', true);
      return v_result;
    end if;
    -- (ج) يوجد مكان ⇒ نكمل ونُعيد تفعيله عبر upsert أدناه.
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

        v_result := jsonb_build_object(
          'access_status',      'active',
          'is_over_limit',      case when v_max = 0 then false else (v_active > v_max) end,
          'active_devices',     v_active,
          'max_devices',        v_max,
          'already_registered', true
        );
        perform set_config('app.device_source', '', true);
        return v_result;
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

  v_result := jsonb_build_object(
    'access_status',      'active',
    'is_over_limit',      case when v_max = 0 then false else (v_active > v_max) end,
    'active_devices',     v_active,
    'max_devices',        v_max,
    'already_registered', v_was_known
  );
  perform set_config('app.device_source', '', true);
  return v_result;
end;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) app_owner_recover_device: إفساح مكان فقط، لا فصل شامل
--    التوقيع كما هو (p_revoke_other_devices default true) ⇒ التطبيق الحالي يعمل.
--    القيمة true لم تعد تعني "افصل الكل" بل "يُسمح بفصل الأقدم لإفساح مكان".
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.app_owner_recover_device(
  p_device_id text,
  p_revoke_other_devices boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
declare
  v_uid       uuid := auth.uid();
  v_tenant_id text;
  v_now       timestamptz := now();
  v_max       int;
  v_others    int;
  v_free      int;
  v_evicted   int := 0;
  v_active    int;
  v_updated   int;
  v_result    jsonb;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;
  if p_device_id is null or length(trim(p_device_id)) = 0 then
    raise exception 'INVALID_DEVICE_ID' using errcode = 'P0001';
  end if;

  -- نفس ترتيب الأقفال في app_register_device (advisory ثم الصفوف) لتفادي deadlock.
  v_tenant_id := public.app_current_tenant_id();
  if v_tenant_id is null or length(trim(v_tenant_id)) = 0 then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('register_device:' || v_tenant_id)::bigint);

  perform 1
  from public.account_devices d
  where d.user_id = v_uid
  for update;

  perform set_config('app.device_source', 'rpc:app_owner_recover_device', true);

  if not exists (
    select 1 from public.account_devices d
    where d.user_id = v_uid and d.device_id = p_device_id
  ) then
    raise exception 'DEVICE_NOT_FOUND: no row for this device_id'
      using errcode = 'P0001';
  end if;

  v_max := coalesce(public.app_user_max_devices(), 0);

  select count(*)::int into v_others
  from public.account_devices d
  where d.user_id = v_uid
    and d.device_id <> p_device_id
    and coalesce(d.access_status, 'active') = 'active';

  if v_max <> 0 and v_others >= v_max then
    if not coalesce(p_revoke_other_devices, false) then
      raise exception 'DEVICE_LIMIT_REACHED: % active devices (limit=%)', v_others, v_max
        using errcode = 'P0001';
    end if;

    -- عدد الأجهزة الواجب فصلها ليتّسع هذا الجهاز: others - (max - 1).
    v_free := v_others - (v_max - 1);

    with victims as (
      select d.id
      from public.account_devices d
      where d.user_id = v_uid
        and d.device_id <> p_device_id
        and coalesce(d.access_status, 'active') = 'active'
      order by d.last_seen_at asc nulls first, d.id asc
      limit v_free
    )
    update public.account_devices a
       set access_status = 'revoked'
      from victims v
     where a.id = v.id;

    get diagnostics v_evicted = row_count;
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

  v_result := jsonb_build_object(
    'access_status',  'active',
    'active_devices', v_active,
    'device_id',      p_device_id,
    'max_devices',    v_max,
    'revoked_others', v_evicted
  );
  perform set_config('app.device_source', '', true);
  return v_result;
end;
$function$;

commit;
