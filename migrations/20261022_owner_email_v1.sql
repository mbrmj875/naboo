-- ترحيب صاحب الحساب: علامة مرة واحدة + أثر الحذف قبل مسح profiles.

alter table public.profiles
  add column if not exists welcome_email_sent_at timestamptz;

create table if not exists public.account_deletion_traces (
  id bigint generated always as identity primary key,
  email text not null,
  previous_trial_started_at timestamptz,
  deleted_at timestamptz not null default now()
);

create index if not exists account_deletion_traces_email_idx
  on public.account_deletion_traces (lower(email));

alter table public.account_deletion_traces enable row level security;

revoke all on table public.account_deletion_traces from anon, authenticated;
