-- Owner alert push — pg_cron schedule (اختياري)
-- بديل أسهل: Supabase Dashboard → Edge Functions → owner-alert-push-cron → Schedules → */15 * * * *
--
-- المتطلبات: pg_cron + pg_net (Supabase Pro أو تفعيل يدوي)
-- قبل التشغيل: عيّن CRON_SECRET في Edge Function Secrets

-- 1) احفظ عنوان الدالة + السر (استبدل YOUR_PROJECT)
--    يُفضّل Vault؛ هنا مثال بجدول إعدادات بسيط:
create table if not exists public.owner_cron_config (
  key text primary key,
  value text not null
);

insert into public.owner_cron_config (key, value)
values
  (
    'owner_alert_push_url',
    'https://YOUR_PROJECT.supabase.co/functions/v1/owner-alert-push-cron'
  ),
  ('owner_alert_push_bearer', 'REPLACE_WITH_CRON_SECRET')
on conflict (key) do nothing;

alter table public.owner_cron_config enable row level security;
-- لا policies — service_role فقط

-- 2) جدولة كل 15 دقيقة (idempotent)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'owner-alert-push-cron';

    perform cron.schedule(
      'owner-alert-push-cron',
      '*/15 * * * *',
      $cron$
      select net.http_post(
        url := (select value from public.owner_cron_config where key = 'owner_alert_push_url'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            select value from public.owner_cron_config where key = 'owner_alert_push_bearer'
          )
        ),
        body := '{}'::jsonb
      );
      $cron$
    );
  else
    raise notice 'pg_cron غير مفعّل — استخدم Supabase Dashboard Schedules بدلاً منه.';
  end if;
exception
  when undefined_table then
    raise notice 'pg_net غير متاح — استخدم Supabase Dashboard Schedules.';
  when others then
    raise notice 'تخطّي جدولة cron: %', sqlerrm;
end $$;
