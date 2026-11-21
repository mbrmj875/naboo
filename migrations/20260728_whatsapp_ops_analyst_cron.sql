-- جدولة whatsapp-ops-analyst كل 5 دقائق عبر pg_cron + pg_net
-- Healthchecks.io خارجياً: period=5m، grace=10m على نفس HEALTHCHECKS_PING_URL
--
-- بديل: Supabase Dashboard → Edge Functions → whatsapp-ops-analyst → Schedules → */5 * * * *
--
-- قبل التشغيل: عيّن أسرار الدالة:
--   WHATSAPP_OPS_ANALYST_SECRET أو CRON_SECRET
--   HEALTHCHECKS_PING_URL, TELEGRAM_OPS_*, OPS_ALERT_EMAIL, RESEND_API_KEY, DEEPSEEK_API_KEY

create table if not exists public.whatsapp_ops_cron_config (
  key text primary key,
  value text not null
);

insert into public.whatsapp_ops_cron_config (key, value)
values
  (
    'whatsapp_ops_analyst_url',
    'https://YOUR_PROJECT.supabase.co/functions/v1/whatsapp-ops-analyst'
  ),
  ('whatsapp_ops_analyst_bearer', 'REPLACE_WITH_CRON_OR_OPS_SECRET')
on conflict (key) do nothing;

alter table public.whatsapp_ops_cron_config enable row level security;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'whatsapp-ops-analyst';

    perform cron.schedule(
      'whatsapp-ops-analyst',
      '*/5 * * * *',
      $cron$
      select net.http_post(
        url := (select value from public.whatsapp_ops_cron_config where key = 'whatsapp_ops_analyst_url'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            select value from public.whatsapp_ops_cron_config where key = 'whatsapp_ops_analyst_bearer'
          )
        ),
        body := '{"source":"pg_cron"}'::jsonb
      );
      $cron$
    );
  else
    raise notice 'pg_cron غير مفعّل — استخدم Supabase Dashboard Schedules (*/5 * * * *).';
  end if;
exception
  when undefined_table then
    raise notice 'pg_net غير متاح — استخدم Dashboard Schedules.';
  when others then
    raise notice 'تخطّي جدولة whatsapp-ops-analyst: %', sqlerrm;
end $$;
