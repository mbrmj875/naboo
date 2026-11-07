-- تذكير غيار الزيت: استدعاء whatsapp-oil-followup-cron كل 5 دقائق.
-- السر يُنسخ من مهمة المحلل الموجودة. لا تضع السر في هذا الملف.

insert into public.whatsapp_ops_cron_config (key, value)
values (
  'whatsapp_oil_followup_url',
  'https://rkofqwcuvbzrnmelvxhz.supabase.co/functions/v1/whatsapp-oil-followup-cron'
)
on conflict (key) do update set value = excluded.value;

insert into public.whatsapp_ops_cron_config (key, value)
select 'whatsapp_oil_followup_bearer', value
from public.ops_edge_cron_config
where key = 'cron_bearer'
on conflict (key) do update set value = excluded.value;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'whatsapp-oil-followup';

    perform cron.schedule(
      'whatsapp-oil-followup',
      '*/5 * * * *',
      $cron$
      select net.http_post(
        url := (select value from public.whatsapp_ops_cron_config where key = 'whatsapp_oil_followup_url'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            select value from public.whatsapp_ops_cron_config where key = 'whatsapp_oil_followup_bearer'
          )
        ),
        body := '{"source":"pg_cron"}'::jsonb
      );
      $cron$
    );
  else
    raise notice 'pg_cron غير مفعّل';
  end if;
exception
  when undefined_table then
    raise notice 'pg_net غير متاح';
  when others then
    raise notice 'تخطّي جدولة whatsapp-oil-followup: %', sqlerrm;
end $$;
