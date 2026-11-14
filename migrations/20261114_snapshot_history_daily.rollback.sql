-- رجوع عن 20261114_snapshot_history_daily.sql.
-- يوقف التخفيف الليلي فقط. النسخ التي حُذفت لا تعود.

select cron.unschedule(jobname) from cron.job
where jobname = 'thin-snapshot-history';

drop function if exists ops_private.thin_snapshot_history(boolean, integer);
