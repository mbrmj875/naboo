-- صندوق أسود تشخيص واتساب — دعم فني فقط (service_role).
-- نفّذ في Supabase SQL Editor ثم انشر whatsapp-gateway + whatsapp-events.

create table if not exists public.whatsapp_diagnostic_events (
  id bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  instance_name text not null,
  event_type text not null,
  severity text not null default 'info'
    check (severity in ('info', 'warn', 'error')),
  connection_state text,
  provider_message_id text,
  correlation_id text,
  shop_phone text,
  recipient_phone text,
  -- phone | lid | unknown — لتتبع فشل @lid كمقاييس لا كملاحظة
  recipient_jid_type text
    check (recipient_jid_type is null or recipient_jid_type in ('phone', 'lid', 'unknown')),
  outcome text,
  reason_code text,
  technical_detail text,
  suggested_action text,
  -- لا تخزّن نص الرسالة / QR / tokens — meta للتشخيص فقط
  meta jsonb,
  created_at timestamptz not null default now()
);

comment on table public.whatsapp_diagnostic_events is
  'سجل تشخيص واتساب للدعم — append-only، بلا محتوى رسائل، احتفاظ 90 يوماً';

create index if not exists idx_wa_diag_user_created
  on public.whatsapp_diagnostic_events (user_id, created_at desc);

create index if not exists idx_wa_diag_instance_created
  on public.whatsapp_diagnostic_events (instance_name, created_at desc);

create index if not exists idx_wa_diag_provider_msg
  on public.whatsapp_diagnostic_events (provider_message_id)
  where provider_message_id is not null;

create index if not exists idx_wa_diag_correlation
  on public.whatsapp_diagnostic_events (correlation_id)
  where correlation_id is not null;

create index if not exists idx_wa_diag_shop_phone
  on public.whatsapp_diagnostic_events (shop_phone, created_at desc)
  where shop_phone is not null;

create index if not exists idx_wa_diag_recipient_phone
  on public.whatsapp_diagnostic_events (recipient_phone, created_at desc)
  where recipient_phone is not null;

create index if not exists idx_wa_diag_outcome_pending
  on public.whatsapp_diagnostic_events (outcome, created_at)
  where outcome in ('accepted', 'server_ack');

create index if not exists idx_wa_diag_jid_type_created
  on public.whatsapp_diagnostic_events (recipient_jid_type, created_at desc)
  where recipient_jid_type is not null;

alter table public.whatsapp_diagnostic_events enable row level security;

-- لا سياسات للمستخدمين — service_role يتجاوز RLS. منع أي وصول authenticated.
drop policy if exists wa_diag_deny_all on public.whatsapp_diagnostic_events;
create policy wa_diag_deny_all
  on public.whatsapp_diagnostic_events
  for all
  to authenticated
  using (false)
  with check (false);

-- تنظيف تلقائي بعد 90 يوماً (يتطلب pg_cron إن وُجد؛ وإلا شغّل يدوياً/من cron Edge).
create or replace function public.prune_whatsapp_diagnostic_events(
  p_retain_days int default 90
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count bigint;
begin
  delete from public.whatsapp_diagnostic_events
  where created_at < now() - make_interval(days => greatest(7, least(coalesce(p_retain_days, 90), 365)));
  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$$;

revoke all on function public.prune_whatsapp_diagnostic_events(int) from public;
grant execute on function public.prune_whatsapp_diagnostic_events(int) to service_role;

-- مقاييس أسبوعية لنسبة فشل الإرسال حسب نوع JID (phone vs lid)
create or replace function public.whatsapp_lid_failure_stats(
  p_days int default 7
)
returns table (
  recipient_jid_type text,
  total_sends bigint,
  failed_or_timeout bigint,
  delivered_or_read bigint,
  fail_rate numeric
)
language sql
security definer
set search_path = public
stable
as $$
  with sends as (
    select
      coalesce(e.recipient_jid_type, 'unknown') as jid_type,
      e.outcome
    from public.whatsapp_diagnostic_events e
    where e.event_type in ('send_attempt', 'send_accepted', 'delivery_update', 'none_timeout')
      and e.created_at >= now() - make_interval(days => greatest(1, least(coalesce(p_days, 7), 90)))
      and e.recipient_jid_type is not null
  )
  select
    jid_type as recipient_jid_type,
    count(*)::bigint as total_sends,
    count(*) filter (
      where outcome in ('error', 'none_timeout', 'rejected', 'same_as_shop_phone', 'invalid_phone')
    )::bigint as failed_or_timeout,
    count(*) filter (
      where outcome in ('delivered', 'read', 'delivery_ack', 'DELIVERY_ACK', 'READ')
    )::bigint as delivered_or_read,
    case when count(*) = 0 then 0
      else round(
        (count(*) filter (
          where outcome in ('error', 'none_timeout', 'rejected', 'same_as_shop_phone', 'invalid_phone')
        )::numeric / count(*)::numeric) * 100,
        1
      )
    end as fail_rate
  from sends
  group by jid_type
  order by jid_type;
$$;

revoke all on function public.whatsapp_lid_failure_stats(int) from public;
grant execute on function public.whatsapp_lid_failure_stats(int) to service_role;
