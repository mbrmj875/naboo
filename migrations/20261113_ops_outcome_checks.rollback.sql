-- رجوع عن 20261113_ops_outcome_checks.sql.

select cron.unschedule(jobname) from cron.job
where jobname in ('ops-check-data-loss', 'ops-check-guard', 'ops-check-whatsapp');

drop function if exists ops_private.check_data_loss();
drop function if exists ops_private.check_guard_violations();
drop function if exists ops_private.check_wa_pdf();
drop function if exists ops_private.check_wa_followup();
drop function if exists ops_private.check_wa_gateways();

delete from ops_private.heartbeat_urls
where job in ('data-loss', 'guard-violations', 'wa-pdf-stuck', 'wa-followup-stuck', 'wa-gateway-repair');
