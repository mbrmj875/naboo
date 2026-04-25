-- إعدادات سحابية يقرأها التطبيق (صيانة، إيقاف مزامنة، إجبار تحديث).
-- نفّذ مرة واحدة في SQL Editor لمشروع Supabase.

create table if not exists public.app_remote_config (
  id smallint primary key default 1,
  constraint app_remote_config_singleton check (id = 1),
  updated_at timestamptz not null default now(),
  config jsonb not null default '{}'::jsonb
);

comment on table public.app_remote_config is
  'إعدادات عامة للتطبيق: maintenance، sync pause، إصدارات. صف واحد id=1.';

insert into public.app_remote_config (id, config)
values (
  1,
  '{
    "maintenance_mode": false,
    "maintenance_message_ar": "",
    "sync_paused_globally": false,
    "sync_paused_message_ar": "المزامنة موقوفة مؤقتاً من الخادم.",
    "min_supported_version": "1.0.0",
    "latest_version": "2.0.1",
    "update_message_ar": "",
    "force_update": false,
    "update_download_url": "",
    "announcement_title_ar": "",
    "announcement_body_ar": "",
    "announcement_url": ""
  }'::jsonb
)
on conflict (id) do nothing;

alter table public.app_remote_config enable row level security;

drop policy if exists "app_remote_config_public_read" on public.app_remote_config;
create policy "app_remote_config_public_read"
on public.app_remote_config
for select
to anon, authenticated
using (true);

-- الكتابة: service_role فقط (لوحة الإدارة أو SQL)
