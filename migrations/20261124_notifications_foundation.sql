-- خطة الإشعارات، المرحلة 1، البند 1: الجداول الأربعة.
-- docs/specs/notifications_master_plan_ar.md (خامسا، البند 2).
--
-- مبدأ واحد: كل إشعار من أي مصدر يُكتب أولا صفا في notifications، ثم يُرسل.
-- الإرسال نفسه في دالة notify-dispatch، ويستدعيها مشغّل عند إدراج صف حان موعده.
--
-- الجداول القديمة (owner_fcm_tokens، owner_alert_preferences، marketplace_merchant_fcm_tokens)
-- تبقى كما هي حتى تختفي النسخ القديمة من التطبيق.
--
-- يعتمد على 20261124_owner_phone_flag.sql (account_has_owner_phone).

-- ─── 1. push_devices: رمز الإرسال لكل جهاز ─────────────────────────────────
create table if not exists public.push_devices (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  fcm_token text not null,
  platform text not null,
  app_version text,
  -- من الداخل على الجهاز الآن (يُمسح عند خروج الموظف). المرحلة 5 تستعمله.
  staff_global_id text,
  role_key text,
  permission_keys text[] not null default '{}',
  local_tenant_id integer,
  enabled boolean not null default true,
  invalid_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (user_id, device_id)
);

create index if not exists push_devices_token_idx on public.push_devices (fcm_token);

alter table public.push_devices enable row level security;
drop policy if exists push_devices_own_select on public.push_devices;
create policy push_devices_own_select on public.push_devices
  for select to authenticated using (auth.uid() = user_id);
-- لا كتابة مباشرة: التسجيل عبر app_register_push_device فقط.

-- ─── 2. notification_events: أحداث الأجهزة (المرحلة 2) ────────────────────
create table if not exists public.notification_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_tenant_id integer not null default 1,
  event_key text not null,
  type text not null,
  -- أرقام ومعرّفات فقط، بلا نصوص. الخادم هو من يكتب نص الإشعار.
  payload jsonb not null default '{}',
  occurred_at timestamptz not null,
  device_id text,
  staff_global_id text,
  created_at timestamptz not null default now(),
  unique (user_id, event_key)
);

alter table public.notification_events enable row level security;
drop policy if exists notification_events_own_select on public.notification_events;
create policy notification_events_own_select on public.notification_events
  for select to authenticated using (auth.uid() = user_id);
drop policy if exists notification_events_own_insert on public.notification_events;
create policy notification_events_own_insert on public.notification_events
  for insert to authenticated with check (auth.uid() = user_id);

-- ─── 3. notifications: السجل الموحد ───────────────────────────────────────
create table if not exists public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  local_tenant_id integer not null default 1,
  -- business | shop_event | naboo_ads | naboo_account | summary | orders
  category text not null,
  type text not null,
  -- critical | high | normal | low
  priority text not null default 'normal',
  title_ar text not null,
  body_ar text not null,
  route text,
  entity_id text,
  -- owner_phone (مالي، لهاتف المالك فقط) | owner (أي جهاز دخل عليه المالك)
  -- | perm:<مفتاح صلاحية> | device:<device_id>
  audience text not null default 'owner_phone',
  -- الجهاز الذي صدر منه الحدث: لا يستلم إشعاره.
  source_device_id text,
  dedupe_key text not null,
  deliver_after timestamptz not null default now(),
  -- pending | sent | held_no_owner_phone | gated | no_devices | quiet_deferred
  -- | disabled_by_user | rate_limited | failed
  status text not null default 'pending',
  attempts integer not null default 0,
  sent_count integer not null default 0,
  sent_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, dedupe_key),
  check (priority in ('critical', 'high', 'normal', 'low')),
  check (category in ('business', 'shop_event', 'naboo_ads', 'naboo_account', 'summary', 'orders'))
);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);
create index if not exists notifications_due_idx
  on public.notifications (deliver_after)
  where status in ('pending', 'quiet_deferred', 'failed');

alter table public.notifications enable row level security;
drop policy if exists notifications_own_select on public.notifications;
create policy notifications_own_select on public.notifications
  for select to authenticated using (auth.uid() = user_id);
-- الكتابة للخادم وحده. «مقروء» عبر app_mark_notifications_read.

-- ─── 4. notification_preferences ─────────────────────────────────────────
create table if not exists public.notification_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  local_tenant_id integer not null default 1,
  disabled_types text[] not null default '{}',
  -- يبقى صفرا افتراضيا (قرارك: لا حد للمبلغ).
  amount_min numeric not null default 0,
  quiet_start time not null default '23:00',
  quiet_end time not null default '07:00',
  summary_time time not null default '21:00',
  hide_lock_details boolean not null default false,
  muted_branch_ids integer[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (user_id, local_tenant_id)
);

alter table public.notification_preferences enable row level security;
drop policy if exists notification_preferences_own on public.notification_preferences;
create policy notification_preferences_own on public.notification_preferences
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ─── دوال التطبيق ─────────────────────────────────────────────────────────
-- تسجيل رمز الجهاز: الجهاز يجب أن يكون نشطا في account_devices.
create or replace function public.app_register_push_device(
  p_device_id text,
  p_fcm_token text,
  p_platform text,
  p_app_version text default null,
  p_local_tenant_id integer default null,
  p_role_key text default null,
  p_staff_global_id text default null,
  p_permission_keys text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'tenant_unauthenticated' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_device_id), '') = '' or coalesce(trim(p_fcm_token), '') = '' then
    raise exception 'INVALID_ARGUMENT' using errcode = 'P0001';
  end if;
  if not exists (
    select 1 from public.account_devices d
     where d.user_id = v_uid and d.device_id = p_device_id and d.access_status = 'active'
  ) then
    raise exception 'DEVICE_NOT_ACTIVE' using errcode = 'P0001';
  end if;

  -- الرمز نفسه لا يبقى على جهاز آخر في الحساب (إعادة تثبيت، تبديل معرّف).
  delete from public.push_devices
   where user_id = v_uid and fcm_token = trim(p_fcm_token) and device_id <> p_device_id;

  insert into public.push_devices as p
    (user_id, device_id, fcm_token, platform, app_version, local_tenant_id,
     role_key, staff_global_id, permission_keys, enabled, invalid_at, updated_at)
  values
    (v_uid, p_device_id, trim(p_fcm_token), lower(coalesce(p_platform, '')), p_app_version,
     p_local_tenant_id, p_role_key, p_staff_global_id, coalesce(p_permission_keys, '{}'),
     true, null, now())
  on conflict (user_id, device_id) do update
    set fcm_token = excluded.fcm_token,
        platform = excluded.platform,
        app_version = excluded.app_version,
        local_tenant_id = excluded.local_tenant_id,
        role_key = excluded.role_key,
        staff_global_id = excluded.staff_global_id,
        permission_keys = excluded.permission_keys,
        enabled = true,
        invalid_at = null,
        updated_at = now();
end;
$$;

-- الخروج من الحساب: الجهاز يتوقف عن الاستلام.
create or replace function public.app_unregister_push_device(p_device_id text)
returns void
language sql
security definer
set search_path = public, auth
as $$
  delete from public.push_devices
   where user_id = auth.uid() and device_id = p_device_id;
$$;

create or replace function public.app_mark_notifications_read(p_ids bigint[])
returns void
language sql
security definer
set search_path = public, auth
as $$
  update public.notifications
     set read_at = now()
   where user_id = auth.uid() and id = any(p_ids) and read_at is null;
$$;

revoke all on function public.app_register_push_device(text, text, text, text, integer, text, text, text[]) from public, anon;
revoke all on function public.app_unregister_push_device(text) from public, anon;
revoke all on function public.app_mark_notifications_read(bigint[]) from public, anon;
grant execute on function public.app_register_push_device(text, text, text, text, integer, text, text, text[]) to authenticated;
grant execute on function public.app_unregister_push_device(text) to authenticated;
grant execute on function public.app_mark_notifications_read(bigint[]) to authenticated;

-- فصل الجهاز في account_devices يوقف إرساله فورا (درس حادثة المحاكي 2026-11-23).
create or replace function public.disable_push_on_device_revoke()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.access_status = 'revoked' and old.access_status is distinct from 'revoked' then
    update public.push_devices
       set enabled = false, updated_at = now()
     where user_id = new.user_id and device_id = new.device_id;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_disable_push_on_device_revoke on public.account_devices;
create trigger trg_disable_push_on_device_revoke
  after update of access_status on public.account_devices
  for each row execute function public.disable_push_on_device_revoke();

-- ─── الإرسال عند الإدراج ─────────────────────────────────────────────────
insert into public.ops_edge_cron_config (key, value)
values ('notify_dispatch_url', 'https://rkofqwcuvbzrnmelvxhz.supabase.co/functions/v1/notify-dispatch')
on conflict (key) do update set value = excluded.value;

-- استدعاء واحد لكل جملة إدراج (لا لكل صف): الدالة تأخذ ما حان من الصفوف.
create or replace function public.notifications_kick_dispatch()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from new_rows n where n.status = 'pending' and n.deliver_after <= now()) then
    begin
      perform net.http_post(
        url := (select value from public.ops_edge_cron_config where key = 'notify_dispatch_url'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (select value from public.ops_edge_cron_config where key = 'cron_bearer')
        ),
        body := jsonb_build_object('ids', (select jsonb_agg(n.id) from new_rows n where n.status = 'pending')),
        timeout_milliseconds := 30000
      );
    exception when others then
      -- الإرسال لا يكسر الإدراج أبدا. المهمة المجدولة تلتقط ما فات.
      null;
    end;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_notifications_kick_dispatch on public.notifications;
create trigger trg_notifications_kick_dispatch
  after insert on public.notifications
  referencing new table as new_rows
  for each statement execute function public.notifications_kick_dispatch();

-- ─── المؤجل والفاشل: كل 15 دقيقة، ولا استدعاء إن لم يحن شيء ─────────────
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'notify-dispatch-due';
  perform cron.schedule(
    'notify-dispatch-due',
    '*/15 * * * *',
    $cron$
    select net.http_post(
      url := (select value from public.ops_edge_cron_config where key = 'notify_dispatch_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select value from public.ops_edge_cron_config where key = 'cron_bearer')
      ),
      body := '{"source":"pg_cron"}'::jsonb,
      timeout_milliseconds := 55000
    )
    where exists (
      select 1 from public.notifications
       where status in ('pending', 'quiet_deferred', 'failed')
         and attempts < 5
         and deliver_after <= now()
    );
    $cron$
  );
end $$;

-- ─── التنظيف: ما عمره فوق 30 يوما ─────────────────────────────────────────
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'cleanup-notifications';
  perform cron.schedule(
    'cleanup-notifications',
    '40 3 * * *',
    $cron$
    delete from public.notifications where created_at < now() - interval '30 days';
    delete from public.notification_events where created_at < now() - interval '30 days';
    $cron$
  );
end $$;
