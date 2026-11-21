-- Naboo Field Reps v1 — مندوبون ميدانيون + مناطق + زيارات + sync idempotency + audit.
-- يُشغَّل مرة من Supabase SQL Editor (service role / dashboard).
-- الوصول عبر service role من admin-web فقط.

create extension if not exists pgcrypto;

-- ——— مندوبون ———
create table if not exists public.field_reps (
  id uuid primary key default gen_random_uuid(),
  username text not null,
  password_hash text not null,
  display_name text not null,
  is_active boolean not null default true,
  disabled_at timestamptz,
  disabled_reason text,
  password_version integer not null default 1,
  created_at timestamptz not null default now(),
  constraint field_reps_username_unique unique (username),
  constraint field_reps_username_nonempty check (char_length(trim(username)) >= 2)
);

create index if not exists field_reps_active_idx
  on public.field_reps (is_active)
  where is_active = true;

-- ——— مناطق محجوزة (مضلع GeoJSON) ———
create table if not exists public.field_territories (
  id uuid primary key default gen_random_uuid(),
  rep_id uuid not null references public.field_reps (id) on delete restrict,
  name text not null,
  geom_geojson jsonb not null,
  status text not null default 'active'
    check (status in ('active', 'released')),
  client_op_id uuid,
  claimed_at timestamptz not null default now(),
  released_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists field_territories_rep_status_idx
  on public.field_territories (rep_id, status);

create index if not exists field_territories_status_idx
  on public.field_territories (status)
  where status = 'active';

-- ——— زيارات المحلات ———
create table if not exists public.field_visits (
  id uuid primary key default gen_random_uuid(),
  rep_id uuid not null references public.field_reps (id) on delete restrict,
  territory_id uuid references public.field_territories (id) on delete set null,
  shop_name text not null,
  owner_name text not null,
  phone text,
  lat double precision not null,
  lng double precision not null,
  gps_accuracy double precision,
  location_source text not null
    check (location_source in ('gps', 'manual')),
  geo_warning text
    check (geo_warning is null or geo_warning in ('out_of_basra', 'weak_accuracy')),
  interest text not null
    check (interest in ('rejected', 'warm', 'interested', 'purchased')),
  notes text,
  visited_at timestamptz not null default now(),
  client_op_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists field_visits_rep_visited_idx
  on public.field_visits (rep_id, visited_at desc);

create index if not exists field_visits_interest_idx
  on public.field_visits (interest);

create index if not exists field_visits_visited_at_idx
  on public.field_visits (visited_at desc);

-- ——— سجل تدقيق الزيارات ———
create table if not exists public.field_visit_events (
  id bigserial primary key,
  visit_id uuid not null references public.field_visits (id) on delete cascade,
  actor_rep_id uuid references public.field_reps (id) on delete set null,
  actor_kind text not null check (actor_kind in ('rep', 'admin')),
  field_name text not null,
  old_value text,
  new_value text,
  created_at timestamptz not null default now()
);

create index if not exists field_visit_events_visit_created_idx
  on public.field_visit_events (visit_id, created_at desc);

create index if not exists field_visit_events_id_idx
  on public.field_visit_events (id);

-- ——— سجل idempotency للمزامنة ———
create table if not exists public.field_sync_log (
  id bigserial primary key,
  client_op_id uuid not null,
  operation_hash varchar(64) not null,
  rep_id uuid not null references public.field_reps (id) on delete cascade,
  op text not null
    check (op in (
      'create_visit', 'update_visit', 'create_territory', 'update_territory'
    )),
  result_json jsonb not null,
  created_at timestamptz not null default now(),
  constraint field_sync_log_op_unique unique (client_op_id, operation_hash)
);

create index if not exists field_sync_log_rep_created_idx
  on public.field_sync_log (rep_id, created_at desc);

create index if not exists field_sync_log_client_op_idx
  on public.field_sync_log (client_op_id);

-- ——— RLS: إغلاق الوصول العام (service role يتجاوز) ———
alter table public.field_reps enable row level security;
alter table public.field_territories enable row level security;
alter table public.field_visits enable row level security;
alter table public.field_visit_events enable row level security;
alter table public.field_sync_log enable row level security;

-- لا سياسات للمستخدمين المجهولين / authenticated — الوصول عبر service role فقط.
