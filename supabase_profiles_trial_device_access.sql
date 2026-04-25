-- Run once in Supabase SQL Editor (adds trial + device revoke support).

-- تجربة مجانية موحّدة لكل حساب Google (نفس تاريخ البدء على كل الأجهزة)
alter table public.profiles
  add column if not exists trial_started_at timestamptz;

comment on column public.profiles.trial_started_at is
  'First Google sign-in: trial starts here; 15 days for all devices of this account.';

-- حالة الجهاز: نشط أو مفعّل بعد فصل مؤقت
alter table public.account_devices
  add column if not exists access_status text not null default 'active';

-- قيم متوقعة: active | revoked
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'account_devices_access_status_check'
  ) then
    alter table public.account_devices
      add constraint account_devices_access_status_check
      check (access_status in ('active', 'revoked'));
  end if;
exception
  when others then null;
end $$;

create index if not exists idx_account_devices_user_status
  on public.account_devices(user_id, access_status);

-- فصل فوري بين الأجهزة (Realtime): من لوحة Supabase → Database → Publications
-- أو نفّذ مرة واحدة (إن لم يكن الجدول مضافاً لمنشور supabase_realtime):
-- alter publication supabase_realtime add table public.account_devices;
