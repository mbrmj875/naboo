-- خطة الإشعارات، المرحلة 0: جدولة owner-alert-push-cron كل 15 دقيقة.
-- يحل محل 20260532_owner_alert_push_cron_schedule.sql الذي لم يُطبَّق (owner_cron_config غير موجود).
-- يستعمل نمط المهام الموجودة: ops_edge_cron_config (الرابط + cron_bearer الموجود). لا سر في هذا الملف.
--
-- الحمل: الاستدعاء لا يحدث إلا إن كان هناك عمل:
--   دورة رأس الساعة (تنبيهات زمنية)، أو نسخة بيانات تغيّرت خلال 17 دقيقة لحساب له تفضيلات تنبيه.
-- الإرسال نفسه مقيّد داخل الدالة بالسر PUSH_ALLOWED_USER_IDS (اليوم: حسابا المالك فقط).

insert into public.ops_edge_cron_config (key, value)
values (
  'owner_alert_push_url',
  'https://rkofqwcuvbzrnmelvxhz.supabase.co/functions/v1/owner-alert-push-cron'
)
on conflict (key) do update set value = excluded.value;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'owner-alert-push';

  perform cron.schedule(
    'owner-alert-push',
    '*/15 * * * *',
    $cron$
    select net.http_post(
      url := (select value from public.ops_edge_cron_config where key = 'owner_alert_push_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select value from public.ops_edge_cron_config where key = 'cron_bearer')
      ),
      body := '{"source":"pg_cron"}'::jsonb,
      timeout_milliseconds := 55000
    )
    where extract(minute from now()) < 15
       or exists (
         select 1
           from public.app_snapshots s
           join public.owner_alert_preferences p on p.user_id = s.user_id
          where s.updated_at > now() - interval '17 minutes'
       );
    $cron$
  );
end $$;
