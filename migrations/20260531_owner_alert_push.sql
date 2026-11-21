-- Owner Command Center v3.3 — تفضيلات Push + توكنات FCM
-- نفّذ في Supabase SQL Editor قبل Edge Function cron.

create table if not exists public.owner_alert_preferences (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  local_tenant_id integer not null check (local_tenant_id > 0),
  vertical text not null default 'supermarket',
  thresholds jsonb not null default '{}'::jsonb,
  push_alert_ids jsonb not null default '[]'::jsonb,
  feature_flags jsonb not null default '{"enableDebts":true,"enableInstallments":true}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (user_id, local_tenant_id)
);

create table if not exists public.owner_fcm_tokens (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  local_tenant_id integer not null check (local_tenant_id > 0),
  platform text not null default 'android',
  token text not null,
  updated_at timestamptz not null default now(),
  unique (user_id, local_tenant_id, platform)
);

create index if not exists idx_owner_alert_prefs_user
  on public.owner_alert_preferences (user_id, local_tenant_id);

create index if not exists idx_owner_fcm_tokens_user
  on public.owner_fcm_tokens (user_id, local_tenant_id);

alter table public.owner_alert_preferences enable row level security;
alter table public.owner_fcm_tokens enable row level security;

-- المستخدم يرفع/يقرأ تفضيلاته فقط.
create policy owner_alert_preferences_own
  on public.owner_alert_preferences
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy owner_fcm_tokens_own
  on public.owner_fcm_tokens
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- cron يستخدم service_role — لا policy للقراءة العامة.

comment on table public.owner_alert_preferences is
  'عتبات وقنوات Push لمركز قيادة المالk — يقرأها Edge Function cron.';

comment on table public.owner_fcm_tokens is
  'توكنات FCM للمالkين — يُرسل إليها cron فقط.';
