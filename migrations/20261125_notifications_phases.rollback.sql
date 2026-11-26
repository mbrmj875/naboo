-- تراجع 20261125_notifications_phases.sql. يعيد المهمة المجدولة كل 15 دقيقة،
-- ودالة طلبات السوق القديمة كما كانت (معطلة: تستدعي send-notification).

do $$
begin
  perform cron.unschedule(jobid) from cron.job
   where jobname in ('notify-subscription', 'notify-daily-summary', 'notify-dispatch-due');
  perform cron.schedule(
    'notify-dispatch-due',
    '*/15 * * * *',
    $cron$
    select net.http_post(
      url := (select value from public.ops_edge_cron_config where key = 'notify_dispatch_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select value from public.ops_edge_cron_config where key = 'cron_bearer')
      ),
      body := '{"source":"pg_cron"}'::jsonb,
      timeout_milliseconds := 55000
    )
    where exists (
      select 1 from public.notifications
       where status in ('pending', 'quiet_deferred', 'failed')
         and attempts < 5
         and deliver_after <= now()
    );
    $cron$
  );
end $$;

delete from public.ops_edge_cron_config where key = 'notify_daily_summary_url';

drop trigger if exists trg_notification_from_event on public.notification_events;
drop trigger if exists trg_notify_new_restaurant_order on public.restaurant_orders;

create or replace function public.notify_new_order()
returns trigger
language plpgsql
security definer
as $function$
BEGIN
  PERFORM net.http_post(
    url := 'https://rkofqwcuvbzrnmelvxhz.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
    ),
    body := jsonb_build_object(
      'type', 'new_order',
      'order_id', NEW.id::text,
      'buyer_id', NEW.buyer_id::text,
      'store_id', NEW.seller_store_id::text,
      'order_number', NEW.order_number
    )
  );
  RETURN NEW;
END;
$function$;

drop function if exists public.app_send_test_notification(text, integer);
drop function if exists public.notify_write_business_alert(uuid, integer, text, text, text, text, text, text);
drop function if exists public.notify_write_summary(uuid, integer, text, text, text, jsonb, boolean);
drop function if exists public.notify_summary_due_accounts();
drop function if exists public.admin_notification_readiness();
drop function if exists public.admin_broadcast_send(text, text, text, text, text, text, jsonb, timestamptz, text);
drop function if exists public.admin_broadcast_preview(jsonb);
drop function if exists public.admin_broadcast_targets(jsonb);
drop function if exists public.notify_version_lt(text, text);
drop table if exists public.notification_broadcasts;
drop function if exists public.notify_subscription_reminders();
drop function if exists public.notify_new_restaurant_order();
drop function if exists public.notification_from_event();
drop function if exists public.notify_insert(uuid, integer, text, text, text, text, text, text, text, text, text, text, text, jsonb, boolean);
drop function if exists public.notify_num(jsonb, text);
drop function if exists public.notify_clean_name(text);
drop function if exists public.notify_fmt_iqd(numeric);

alter table public.notifications drop column if exists details;
alter table public.notification_preferences alter column summary_time set default '21:00';
alter table public.notification_preferences
  drop column if exists muted,
  drop column if exists branch_name;
