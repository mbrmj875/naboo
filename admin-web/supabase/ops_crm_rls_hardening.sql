-- Follow-up hardening for DBs that already applied ops_crm_v1 without RLS.
-- Safe to re-run. Run from Supabase SQL Editor (service role).

alter table if exists public.ops_contacts enable row level security;
alter table if exists public.ops_crm_meta enable row level security;
alter table if exists public.ops_crm_notes enable row level security;
alter table if exists public.ops_crm_tasks enable row level security;
alter table if exists public.ops_messages enable row level security;
alter table if exists public.ops_ai_suggestions enable row level security;

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
