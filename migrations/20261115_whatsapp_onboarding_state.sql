/*
  حالة ربط واتساب لكل متجر: للاستكمال بعد إغلاق الشاشة، ولقياس مكان توقف المتاجر.
  الكتابة من الخادم فقط، وصاحب المتجر يقرأ صفه.
*/

begin;

create table if not exists public.whatsapp_onboarding_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  provider text,
  current_step text not null check (current_step in (
    'started', 'meta_opened', 'meta_returned', 'completed',
    'test_sent', 'failed'
  )),
  steps jsonb not null default '{}'::jsonb,
  last_error_code text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.whatsapp_onboarding_state enable row level security;

revoke all on table public.whatsapp_onboarding_state from public, anon, authenticated;
grant select on table public.whatsapp_onboarding_state to authenticated;
grant all on table public.whatsapp_onboarding_state to service_role;

drop policy if exists whatsapp_onboarding_state_select_own
  on public.whatsapp_onboarding_state;
create policy whatsapp_onboarding_state_select_own
  on public.whatsapp_onboarding_state
  for select
  to authenticated
  using (auth.uid() = user_id);

commit;
