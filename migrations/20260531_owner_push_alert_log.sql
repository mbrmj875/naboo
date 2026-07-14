-- Owner Push cooldown log — يمنع إرسال نفس التنبيه كل 15 دقيقة
-- نفّذ بعد migrations/20260531_owner_alert_push.sql

create table if not exists public.owner_push_alert_log (
  user_id uuid not null references auth.users (id) on delete cascade,
  local_tenant_id integer not null check (local_tenant_id > 0),
  alert_id text not null,
  metric_count integer not null default 0,
  sent_at timestamptz not null default now(),
  primary key (user_id, local_tenant_id, alert_id)
);

create index if not exists idx_owner_push_alert_log_sent
  on public.owner_push_alert_log (sent_at desc);

alter table public.owner_push_alert_log enable row level security;

-- cron (service_role) يقرأ/يكتب — لا وصول للعميل.
comment on table public.owner_push_alert_log is
  'آخر Push مُرسَل per alert — Edge Function owner-alert-push-cron.';
