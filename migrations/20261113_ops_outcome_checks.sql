-- مراقبة النتائج لا المهام (13 نوفمبر 2026). يعتمد على 20261113_ops_heartbeats.sql.
--
-- كل فحص يطرق رابطه إن كان كل شيء سليماً، ويطرق /fail إن وجد خللاً، فيصل
-- التنبيه فوراً. الروابط في ops_private.heartbeat_urls على الخادم فقط.
--
-- الرجوع: 20261113_ops_outcome_checks.rollback.sql

-- ضياع بيانات: نقص عدد البطاقات أو الفواتير أو قيود الصندوق في أي حساب عن الأمس.
-- لا يرى الحسابات المقسّمة (3 من 27 اليوم) لأن الخادم لا يفك ضغط لقطاتها.
create or replace function ops_private.check_data_loss()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from public.ops_account_daily_metrics t
  join public.ops_account_daily_metrics y
    on y.user_id = t.user_id and y.day = t.day - 1
  where t.day = (select max(day) from public.ops_account_daily_metrics)
    and (t.cards_total < y.cards_total
      or t.invoices_active < y.invoices_active
      or t.cash_rows_active < y.cash_rows_active);
  perform ops_private.ping('data-loss', v_bad > 0);
end;
$$;

-- مخالفة حارس جديدة من حساب حقيقي. حساب التجربة a66b5bad مستثنى لأن أجهزة
-- الاختبار عليه تتجاوز الحد عمداً.
create or replace function ops_private.check_guard_violations()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from public.sync_guard_violations
  where at > now() - interval '24 hours'
    and coalesce(user_id::text, '') not like 'a66b5bad%';
  perform ops_private.ping('guard-violations', v_bad > 0);
end;
$$;

-- واتساب: بطاقة تنتظر أكثر من 30 دقيقة، أو 3 فشل أو أكثر في ساعة.
-- awaiting_inbound ليست عالقة: تنتظر رسالة الزبون لفتح نافذة الـ 24 ساعة.
create or replace function ops_private.check_wa_pdf()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_stuck int;
  v_failed int;
begin
  select count(*) into v_stuck
  from public.whatsapp_oil_card_pdf_jobs
  where status = 'pending' and idle_after < now() - interval '30 minutes';
  select count(*) into v_failed
  from public.whatsapp_oil_card_pdf_jobs
  where status = 'failed' and updated_at > now() - interval '1 hour';
  perform ops_private.ping('wa-pdf-stuck', v_stuck > 0 or v_failed >= 3);
end;
$$;

create or replace function ops_private.check_wa_followup()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from public.wa_oil_followup_jobs
  where status = 'queued' and due_at < now() - interval '30 minutes';
  perform ops_private.ping('wa-followup-stuck', v_bad > 0);
end;
$$;

create or replace function ops_private.check_wa_gateways()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from public.tenant_whatsapp_gateways
  where repair_needed and updated_at < now() - interval '1 hour';
  perform ops_private.ping('wa-gateway-repair', v_bad > 0);
end;
$$;

revoke all on function ops_private.check_data_loss() from public, anon, authenticated;
revoke all on function ops_private.check_guard_violations() from public, anon, authenticated;
revoke all on function ops_private.check_wa_pdf() from public, anon, authenticated;
revoke all on function ops_private.check_wa_followup() from public, anon, authenticated;
revoke all on function ops_private.check_wa_gateways() from public, anon, authenticated;

-- بعد المقارنة اليومية (20:50 UTC) بعشر دقائق.
select cron.schedule('ops-check-data-loss', '0 21 * * *', 'select ops_private.check_data_loss()');
select cron.schedule('ops-check-guard', '5 21 * * *', 'select ops_private.check_guard_violations()');
select cron.schedule('ops-check-whatsapp', '*/15 * * * *',
  'select ops_private.check_wa_pdf(); select ops_private.check_wa_followup(); select ops_private.check_wa_gateways();');
