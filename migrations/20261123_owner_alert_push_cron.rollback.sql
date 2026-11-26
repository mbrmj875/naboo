-- إيقاف فوري لمهمة إشعارات المالك.
select cron.unschedule(jobid) from cron.job where jobname = 'owner-alert-push';
delete from public.ops_edge_cron_config where key = 'owner_alert_push_url';
