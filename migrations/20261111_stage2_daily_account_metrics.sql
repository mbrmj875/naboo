-- المرحلة 2، البند 2.2: مقارنة يومية لعدد البطاقات والرصيد لكل حساب.
-- قراءة فقط من app_snapshots، تكتب في جدول خاص بالخادم لا يراه التطبيق.
-- اللقطة المجزأة (مضغوطة) لا تُقرأ في SQL، فتُسجَّل بعلامة chunked وأرقام فارغة.
-- الرجوع:
--   select cron.unschedule('daily-account-metrics');
--   drop view if exists public.ops_account_metrics_alerts;
--   drop function if exists public.ops_capture_account_metrics();
--   drop table if exists public.ops_account_daily_metrics;

create table if not exists public.ops_account_daily_metrics (
  user_id uuid not null,
  day date not null,
  captured_at timestamptz not null default now(),
  content_version bigint,
  chunked boolean not null default false,
  cards_total integer,
  cards_active integer,
  invoices_active integer,
  invoices_total_fils numeric,
  cash_rows_active integer,
  cash_balance_fils numeric,
  primary key (user_id, day)
);

alter table public.ops_account_daily_metrics enable row level security;
revoke all on public.ops_account_daily_metrics from anon, authenticated;

create or replace function public.ops_capture_account_metrics()
returns integer
language sql
security definer
set search_path = ''
as $$
  with snap as (
    select s.user_id, s.content_version, s.payload,
           coalesce(s.payload->>'chunked', 'false') = 'true' as chunked
      from public.app_snapshots s
  ), m as (
    select
      user_id, content_version, chunked,
      case when chunked then null else (
        select count(*) from jsonb_array_elements(coalesce(payload->'tables'->'service_orders', '[]')) r) end as cards_total,
      case when chunked then null else (
        select count(*) from jsonb_array_elements(coalesce(payload->'tables'->'service_orders', '[]')) r
         where coalesce(r->>'deletedAt', r->>'deleted_at') is null) end as cards_active,
      case when chunked then null else (
        select count(*) from jsonb_array_elements(coalesce(payload->'tables'->'invoices', '[]')) r
         where coalesce(r->>'deleted_at', r->>'deletedAt') is null) end as invoices_active,
      case when chunked then null else (
        select coalesce(sum(case when coalesce(nullif(r->>'totalFils', '')::numeric, 0) <> 0 then (r->>'totalFils')::numeric else round(coalesce(nullif(r->>'total', '')::numeric, 0) * 1000) end), 0)
          from jsonb_array_elements(coalesce(payload->'tables'->'invoices', '[]')) r
         where coalesce(r->>'deleted_at', r->>'deletedAt') is null) end as invoices_total_fils,
      case when chunked then null else (
        select count(*) from jsonb_array_elements(coalesce(payload->'tables'->'cash_ledger', '[]')) r
         where coalesce(r->>'deleted_at', r->>'deletedAt') is null) end as cash_rows_active,
      case when chunked then null else (
        select coalesce(sum(case when coalesce(nullif(r->>'amountFils', '')::numeric, 0) <> 0 then (r->>'amountFils')::numeric else round(coalesce(nullif(r->>'amount', '')::numeric, 0) * 1000) end), 0)
          from jsonb_array_elements(coalesce(payload->'tables'->'cash_ledger', '[]')) r
         where coalesce(r->>'deleted_at', r->>'deletedAt') is null) end as cash_balance_fils
    from snap
  ), ins as (
    insert into public.ops_account_daily_metrics as t
      (user_id, day, content_version, chunked, cards_total, cards_active,
       invoices_active, invoices_total_fils, cash_rows_active, cash_balance_fils)
    select user_id, (now() at time zone 'Asia/Baghdad')::date, content_version, chunked,
           cards_total, cards_active, invoices_active, invoices_total_fils,
           cash_rows_active, cash_balance_fils
      from m
    on conflict (user_id, day) do update set
      captured_at = now(), content_version = excluded.content_version, chunked = excluded.chunked,
      cards_total = excluded.cards_total, cards_active = excluded.cards_active,
      invoices_active = excluded.invoices_active, invoices_total_fils = excluded.invoices_total_fils,
      cash_rows_active = excluded.cash_rows_active, cash_balance_fils = excluded.cash_balance_fils
    returning 1
  )
  select count(*)::integer from ins;
$$;

revoke all on function public.ops_capture_account_metrics() from public, anon, authenticated;

-- الرصيد بطريقة التطبيق نفسها (db_cash.dart: getCashSummary): amountFils وإلا amount × 1000.
-- ما يستحق النظر: نقص البطاقات أو الفواتير، أو تغيّر الرصيد بلا زيادة في الفواتير.
create or replace view public.ops_account_metrics_alerts
with (security_invoker = true) as
select cur.user_id, cur.day,
       prev.cards_total as cards_total_before, cur.cards_total as cards_total_now,
       prev.invoices_active as invoices_before, cur.invoices_active as invoices_now,
       prev.cash_balance_fils as cash_before, cur.cash_balance_fils as cash_now,
       case
         when cur.cards_total < prev.cards_total then 'cards_dropped'
         when cur.invoices_active < prev.invoices_active then 'invoices_dropped'
         when cur.cash_balance_fils < prev.cash_balance_fils
              and cur.invoices_active <= prev.invoices_active then 'cash_dropped'
       end as reason
  from public.ops_account_daily_metrics cur
  join public.ops_account_daily_metrics prev
    on prev.user_id = cur.user_id and prev.day = cur.day - 1
 where not cur.chunked and not prev.chunked
   and (cur.cards_total < prev.cards_total
        or cur.invoices_active < prev.invoices_active
        or (cur.cash_balance_fils < prev.cash_balance_fils
            and cur.invoices_active <= prev.invoices_active));

revoke all on public.ops_account_metrics_alerts from anon, authenticated;

-- 23:50 بتوقيت بغداد = 20:50 بتوقيت الخادم.
select cron.schedule('daily-account-metrics', '50 20 * * *', $$select public.ops_capture_account_metrics()$$);
