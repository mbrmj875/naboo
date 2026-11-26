-- ب7: اختبار الأمان كل 10 دقائق يستيقظ لدروس المجيب المرشحة أيضاً (م6-14).
select cron.unschedule('assistant-learn-evaluate');
select cron.schedule(
  'assistant-learn-evaluate',
  '3-59/10 * * * *',
  $$
    select net.http_post(
      url := (select value from public.ops_edge_cron_config where key = 'assistant_learn_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select value from public.ops_edge_cron_config where key = 'cron_bearer')
      ),
      body := '{"op":"evaluate"}'::jsonb,
      timeout_milliseconds := 150000
    )
    where exists (
      select 1 from public.assistant_lessons
       where status = 'candidate' and audience in ('app', 'whatsapp') and tenant_id is null
         and (origin = 'learn' or eval_requested_at is not null)
    );
  $$
);
