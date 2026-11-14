-- مرحلة 2 — بوابة واتساب المحل (Evolution) لكل حساب سحابي
-- نفّذ في Supabase SQL Editor قبل نشر Edge Functions.

create table if not exists public.tenant_whatsapp_gateways (
  user_id uuid primary key references auth.users (id) on delete cascade,
  evolution_instance_name text not null,
  status text not null default 'unknown'
    check (status in ('unknown', 'connecting', 'connected', 'disconnected')),
  whatsapp_phone text,
  last_connected_at timestamptz,
  last_disconnected_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists idx_tenant_whatsapp_gateways_status
  on public.tenant_whatsapp_gateways (status, updated_at desc);

alter table public.tenant_whatsapp_gateways enable row level security;

create policy tenant_whatsapp_gateways_own
  on public.tenant_whatsapp_gateways
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

comment on table public.tenant_whatsapp_gateways is
  'حالة ربط واتساب المحل عبر Evolution — مزامنة بين كل أجهزة NaBoo لنفس الحساب.';
