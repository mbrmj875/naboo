-- رجوع عن 20261113_ops_heartbeats.sql: أوامر المهام تعود كما كانت حرفياً.

select cron.unschedule('ops-sync-alive')
where exists (select 1 from cron.job where jobname = 'ops-sync-alive');

do $$
declare
  r record;
begin
  for r in
    select j.jobid, b.command
    from cron.job j
    join ops_private.cron_command_backup b using (jobname)
  loop
    perform cron.alter_job(job_id := r.jobid, command := r.command);
  end loop;
end;
$$;

drop function if exists ops_private.check_sync_alive();
drop function if exists ops_private.ping(text, boolean);
drop table if exists ops_private.heartbeat_urls;
drop table if exists ops_private.cron_command_backup;
drop schema if exists ops_private;
