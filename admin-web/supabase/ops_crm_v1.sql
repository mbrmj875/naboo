-- Naboo Ops CRM v1 — يشغَّل مرة من Supabase SQL Editor (service role / dashboard).
-- هوية موحّدة + ملاحظات/مهام + رسائل قنوات + اقتراحات AI.
-- الوصول عبر service role من admin-web فقط (لا سياسات عامة للمستأجرين).

create extension if not exists pgcrypto;

-- ——— هوية موحّدة (هاتف = مفتاح) ———
create table if not exists public.ops_contacts (
  id uuid primary key default gen_random_uuid(),
  phone_e164 text not null,
  display_name text,
  auth_user_id uuid references auth.users (id) on delete set null,
  lifecycle text not null default 'lead'
    check (lifecycle in (
      'lead', 'trial', 'active', 'expiring', 'expired', 'churned', 'winback'
    )),
  whatsapp_id text,
  facebook_psid text,
  instagram_id text,
  telegram_id text,
  tiktok_id text,
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ops_contacts_phone_unique unique (phone_e164)
);

create index if not exists ops_contacts_auth_user_idx
  on public.ops_contacts (auth_user_id)
  where auth_user_id is not null;

create index if not exists ops_contacts_lifecycle_idx
  on public.ops_contacts (lifecycle);

-- ——— ميتا CRM ———
create table if not exists public.ops_crm_meta (
  account_user_id uuid primary key references auth.users (id) on delete cascade,
  owner text,
  tags text[] not null default '{}',
  next_followup_at timestamptz,
  notes_summary text,
  updated_at timestamptz not null default now()
);

-- ——— ملاحظات ———
create table if not exists public.ops_crm_notes (
  id uuid primary key default gen_random_uuid(),
  account_user_id uuid not null references auth.users (id) on delete cascade,
  body text not null,
  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists ops_crm_notes_account_created_idx
  on public.ops_crm_notes (account_user_id, created_at desc);

-- ——— مهام ———
create table if not exists public.ops_crm_tasks (
  id uuid primary key default gen_random_uuid(),
  account_user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null default 'followup'
    check (kind in (
      'followup', 'renewal', 'onboarding', 'support', 'winback', 'other'
    )),
  title text not null,
  due_at timestamptz,
  status text not null default 'open'
    check (status in ('open', 'done', 'cancelled')),
  assignee text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists ops_crm_tasks_open_due_idx
  on public.ops_crm_tasks (status, due_at)
  where status = 'open';

create index if not exists ops_crm_tasks_account_idx
  on public.ops_crm_tasks (account_user_id, created_at desc);

-- ——— رسائل القنوات ———
create table if not exists public.ops_messages (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references public.ops_contacts (id) on delete cascade,
  channel text not null
    check (channel in (
      'whatsapp', 'facebook', 'instagram', 'telegram', 'tiktok', 'email', 'sms'
    )),
  direction text not null check (direction in ('inbound', 'outbound')),
  sender text not null check (sender in ('customer', 'human', 'ai', 'system')),
  body text not null,
  external_id text,
  raw jsonb,
  created_at timestamptz not null default now()
);

create unique index if not exists ops_messages_channel_external_uidx
  on public.ops_messages (channel, external_id)
  where external_id is not null;

create index if not exists ops_messages_contact_created_idx
  on public.ops_messages (contact_id, created_at desc);

-- ——— اقتراحات / ردود AI ———
create table if not exists public.ops_ai_suggestions (
  id uuid primary key default gen_random_uuid(),
  contact_id uuid not null references public.ops_contacts (id) on delete cascade,
  message_id uuid references public.ops_messages (id) on delete set null,
  response_text text not null,
  confidence real,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'sent', 'edited')),
  manual_edit text,
  created_by text,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);

create index if not exists ops_ai_suggestions_contact_pending_idx
  on public.ops_ai_suggestions (contact_id, created_at desc)
  where status = 'pending';

comment on table public.ops_contacts is 'هوية موحّدة لتجّار/مهتمّي نابو عبر القنوات';
comment on table public.ops_messages is 'رسائل Inbox المنصة (واتساب أولاً ثم قنوات أخرى)';
comment on table public.ops_crm_tasks is 'مهام متابعة فريق إدارة نابو';

-- ——— عزل: service_role فقط (admin-web) — لا وصول لـ anon/authenticated ———
alter table public.ops_contacts enable row level security;
alter table public.ops_crm_meta enable row level security;
alter table public.ops_crm_notes enable row level security;
alter table public.ops_crm_tasks enable row level security;
alter table public.ops_messages enable row level security;
alter table public.ops_ai_suggestions enable row level security;

revoke all on table public.ops_contacts from public, anon, authenticated;
revoke all on table public.ops_crm_meta from public, anon, authenticated;
revoke all on table public.ops_crm_notes from public, anon, authenticated;
revoke all on table public.ops_crm_tasks from public, anon, authenticated;
revoke all on table public.ops_messages from public, anon, authenticated;
revoke all on table public.ops_ai_suggestions from public, anon, authenticated;

grant all on table public.ops_contacts to service_role;
grant all on table public.ops_crm_meta to service_role;
grant all on table public.ops_crm_notes to service_role;
grant all on table public.ops_crm_tasks to service_role;
grant all on table public.ops_messages to service_role;
grant all on table public.ops_ai_suggestions to service_role;
