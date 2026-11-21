-- Owner alert preferences — feature flags (Feature Gate mirror)
-- نفّذ بعد migrations/20260531_owner_alert_push.sql

alter table public.owner_alert_preferences
  add column if not exists feature_flags jsonb not null default '{
    "enableDebts": true,
    "enableInstallments": true
  }'::jsonb;

comment on column public.owner_alert_preferences.feature_flags is
  'مرآة Feature Gate — cron لا يُقيّم أقساط/ديون إذا false.';
