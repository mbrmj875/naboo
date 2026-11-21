alter table public.profiles
  add column if not exists role text
  not null default 'staff'
  check (role in ('owner', 'admin', 'staff'));

create index if not exists idx_profiles_role
  on public.profiles (id, role);
