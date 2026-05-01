-- Run this in Supabase SQL editor before using cloud sync.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_own_select" on public.profiles;
drop policy if exists "profiles_own_upsert" on public.profiles;

create policy "profiles_own_select"
on public.profiles
for select
using (auth.uid() = id);

create policy "profiles_own_upsert"
on public.profiles
for all
using (auth.uid() = id)
with check (auth.uid() = id);

create table if not exists public.app_snapshots (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_label text,
  schema_version int not null default 1,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

-- عمود مطلوب من تطبيق Flutter (رفع لقطة بمفتاح إيديمبوتنسي لجلسة الرفع).
alter table public.app_snapshots
  add column if not exists idempotency_key text;

create unique index if not exists ux_app_snapshots_user
  on public.app_snapshots(user_id);

alter table public.app_snapshots enable row level security;

drop policy if exists "snapshots_own_select" on public.app_snapshots;
drop policy if exists "snapshots_own_write" on public.app_snapshots;

create policy "snapshots_own_select"
on public.app_snapshots
for select
using (auth.uid() = user_id);

create policy "snapshots_own_write"
on public.app_snapshots
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create table if not exists public.app_snapshot_chunks (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  sync_id text not null,
  chunk_index int not null,
  chunk_data text not null,
  updated_at timestamptz not null default now(),
  unique (user_id, sync_id, chunk_index)
);

create index if not exists idx_app_snapshot_chunks_lookup
  on public.app_snapshot_chunks(user_id, sync_id, chunk_index);

alter table public.app_snapshot_chunks enable row level security;

drop policy if exists "snapshot_chunks_own_select" on public.app_snapshot_chunks;
drop policy if exists "snapshot_chunks_own_write" on public.app_snapshot_chunks;

create policy "snapshot_chunks_own_select"
on public.app_snapshot_chunks
for select
using (auth.uid() = user_id);

create policy "snapshot_chunks_own_write"
on public.app_snapshot_chunks
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create table if not exists public.account_devices (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null,
  device_name text not null,
  platform text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, device_id)
);

create index if not exists idx_account_devices_user_last_seen
  on public.account_devices(user_id, last_seen_at desc);

alter table public.account_devices enable row level security;

drop policy if exists "devices_own_select" on public.account_devices;
drop policy if exists "devices_own_write" on public.account_devices;

create policy "devices_own_select"
on public.account_devices
for select
using (auth.uid() = user_id);

create policy "devices_own_write"
on public.account_devices
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);
