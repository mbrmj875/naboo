-- WhatsApp Ops Analyst (AIOps + RAG-RCA + monitor reliability)
-- نفّذ في Supabase SQL Editor قبل نشر whatsapp-ops-analyst وربط facts في whatsapp-events.
-- بصمة الحادث: sha256(rule_id|session_name|pattern_key|severity) — user_id عمود مفهرس فقط (ليس في الـ hash).

-- ─── حقائق موحّدة ─────────────────────────────────────────────
create table if not exists public.whatsapp_ops_facts (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  session_name text not null,
  fact_type text not null,
  code text,
  phone_fingerprint text,
  raw_ref text,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_whatsapp_ops_facts_user_created
  on public.whatsapp_ops_facts (user_id, created_at desc);

create index if not exists idx_whatsapp_ops_facts_session_created
  on public.whatsapp_ops_facts (session_name, created_at desc);

create index if not exists idx_whatsapp_ops_facts_type_created
  on public.whatsapp_ops_facts (fact_type, created_at desc);

comment on table public.whatsapp_ops_facts is
  'حقائق واتساب موحّدة للمحلّل — مصدرها whatsapp-events / diagnostics / gateway.';

-- ─── مرشّحو استمرار الشرط (بوابة 5 دقائق) ─────────────────────
create table if not exists public.whatsapp_ops_condition_candidates (
  fingerprint text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  session_name text not null,
  condition_key text not null,
  severity_intent text not null
    check (severity_intent in ('P1', 'P2', 'P3')),
  pattern_key text not null,
  playbook_step_id text not null,
  rule_id text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists idx_whatsapp_ops_candidates_user
  on public.whatsapp_ops_condition_candidates (user_id);

create index if not exists idx_whatsapp_ops_candidates_last_seen
  on public.whatsapp_ops_condition_candidates (last_seen_at);

comment on table public.whatsapp_ops_condition_candidates is
  'شروط غير فورية تنتظر استمرار X=5د قبل فتح حادث.';

-- ─── حوادث ────────────────────────────────────────────────────
create table if not exists public.whatsapp_ops_incidents (
  id uuid primary key default gen_random_uuid(),
  fingerprint text not null,
  user_id uuid not null references auth.users (id) on delete cascade,
  session_name text not null,
  severity text not null check (severity in ('P1', 'P2', 'P3')),
  pattern_key text not null,
  playbook_step_id text not null,
  rule_id text not null,
  status text not null default 'open'
    check (status in ('open', 'resolved', 'suppressed')),
  opened_at timestamptz not null default now(),
  sla_deadline_at timestamptz,
  escalated_at timestamptz,
  resolved_at timestamptz,
  stable_since timestamptz,
  times_seen int not null default 1,
  last_seen_at timestamptz not null default now(),
  report_ar text,
  enrichment_ar text,
  enrichment_at timestamptz,
  lesson_ids uuid[] not null default '{}',
  meta jsonb not null default '{}'::jsonb
);

create unique index if not exists uq_whatsapp_ops_incidents_open_fingerprint
  on public.whatsapp_ops_incidents (fingerprint)
  where status = 'open';

create index if not exists idx_whatsapp_ops_incidents_user_status
  on public.whatsapp_ops_incidents (user_id, status, opened_at desc);

create index if not exists idx_whatsapp_ops_incidents_session_status
  on public.whatsapp_ops_incidents (session_name, status);

create index if not exists idx_whatsapp_ops_incidents_pattern
  on public.whatsapp_ops_incidents (pattern_key, opened_at desc);

comment on table public.whatsapp_ops_incidents is
  'حوادث واتساب — severity من المصنّف الحتمي فقط؛ AI يُثري report/enrichment.';

-- ─── تنبيهات (قنوات) ─────────────────────────────────────────
create table if not exists public.whatsapp_ops_alerts (
  id bigserial primary key,
  incident_id uuid not null references public.whatsapp_ops_incidents (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  channel text not null check (channel in ('email', 'telegram', 'fcm')),
  alert_kind text not null
    check (alert_kind in ('open', 'escalate', 'resolved', 'flapping')),
  ok boolean not null default false,
  detail text,
  created_at timestamptz not null default now()
);

create index if not exists idx_whatsapp_ops_alerts_incident
  on public.whatsapp_ops_alerts (incident_id, created_at desc);

create index if not exists idx_whatsapp_ops_alerts_user
  on public.whatsapp_ops_alerts (user_id, created_at desc);

-- ─── دروس RAG ─────────────────────────────────────────────────
create table if not exists public.whatsapp_ops_lessons (
  id uuid primary key default gen_random_uuid(),
  pattern_key text not null,
  severity text not null check (severity in ('P1', 'P2', 'P3')),
  title_ar text not null,
  summary_ar text not null,
  root_cause_ar text,
  resolution_ar text,
  playbook_step_id text,
  eval_fixture_id text,
  times_confirmed int not null default 1,
  last_confirmed_at timestamptz not null default now(),
  source_incident_id uuid references public.whatsapp_ops_incidents (id) on delete set null,
  meta jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists uq_whatsapp_ops_lessons_pattern_severity
  on public.whatsapp_ops_lessons (pattern_key, severity);

create index if not exists idx_whatsapp_ops_lessons_eval
  on public.whatsapp_ops_lessons (eval_fixture_id)
  where eval_fixture_id is not null;

-- ─── ملف مستأجر (dossier) ─────────────────────────────────────
create table if not exists public.whatsapp_tenant_dossier (
  user_id uuid primary key references auth.users (id) on delete cascade,
  session_name text,
  live_status text,
  repair_needed boolean not null default false,
  flap_count_1h int not null default 0,
  sends_accepted_24h int not null default 0,
  delivery_acks_24h int not null default 0,
  send_failures_24h int not null default 0,
  delivery_health text not null default 'unknown'
    check (delivery_health in ('unknown', 'healthy', 'degraded', 'silent_fail')),
  report_ar text,
  last_analyst_at timestamptz,
  meta jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- ─── إحصاءات تسليم نوافذ ─────────────────────────────────────
create table if not exists public.whatsapp_ops_delivery_stats (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  session_name text not null,
  window_start timestamptz not null,
  window_end timestamptz not null,
  send_accepted int not null default 0,
  delivery_ack int not null default 0,
  send_failed int not null default 0,
  silent_undelivered int not null default 0,
  created_at timestamptz not null default now(),
  unique (user_id, session_name, window_start, window_end)
);

create index if not exists idx_whatsapp_ops_delivery_stats_user
  on public.whatsapp_ops_delivery_stats (user_id, window_end desc);

-- ─── تدقيق تشغيل المحلّل + Dead Man's Switch ─────────────────
create table if not exists public.whatsapp_ops_monitor_runs (
  id bigserial primary key,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  ok boolean,
  error text,
  heartbeat_pinged boolean not null default false,
  stats jsonb not null default '{}'::jsonb
);

create index if not exists idx_whatsapp_ops_monitor_runs_started
  on public.whatsapp_ops_monitor_runs (started_at desc);

-- ─── RLS: service_role يتجاوز؛ authenticated قراءة محدودة للمالك ──
alter table public.whatsapp_ops_facts enable row level security;
alter table public.whatsapp_ops_condition_candidates enable row level security;
alter table public.whatsapp_ops_incidents enable row level security;
alter table public.whatsapp_ops_alerts enable row level security;
alter table public.whatsapp_ops_lessons enable row level security;
alter table public.whatsapp_tenant_dossier enable row level security;
alter table public.whatsapp_ops_delivery_stats enable row level security;
alter table public.whatsapp_ops_monitor_runs enable row level security;

-- دروس عامة للقراءة (مشاركة عبر المستأجرين للـ RAG) — authenticated select
drop policy if exists whatsapp_ops_lessons_read on public.whatsapp_ops_lessons;
create policy whatsapp_ops_lessons_read
  on public.whatsapp_ops_lessons
  for select
  to authenticated
  using (true);

drop policy if exists whatsapp_ops_incidents_own on public.whatsapp_ops_incidents;
create policy whatsapp_ops_incidents_own
  on public.whatsapp_ops_incidents
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists whatsapp_ops_alerts_own on public.whatsapp_ops_alerts;
create policy whatsapp_ops_alerts_own
  on public.whatsapp_ops_alerts
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists whatsapp_ops_facts_own on public.whatsapp_ops_facts;
create policy whatsapp_ops_facts_own
  on public.whatsapp_ops_facts
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists whatsapp_tenant_dossier_own on public.whatsapp_tenant_dossier;
create policy whatsapp_tenant_dossier_own
  on public.whatsapp_tenant_dossier
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists whatsapp_ops_delivery_stats_own on public.whatsapp_ops_delivery_stats;
create policy whatsapp_ops_delivery_stats_own
  on public.whatsapp_ops_delivery_stats
  for select
  to authenticated
  using (user_id = auth.uid());

-- candidates / monitor_runs: لا policies للمستخدم — service_role فقط
