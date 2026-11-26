-- رجوع عن 20261114_snapshot_chunks_archive.sql.
-- يوقف الأرشفة والتنظيف. جدول الأرشيف يبقى حتى لا تضيع أجزاء محفوظة؛
-- احذفه يدوياً بالسطر الأخير إن أردت استرجاع مساحته.

select cron.unschedule(jobname) from cron.job
where jobname = 'prune-snapshot-chunks-archive';

drop trigger if exists trg_archive_deleted_snapshot_chunk on public.app_snapshot_chunks;
drop function if exists ops_private.fn_archive_deleted_snapshot_chunk();
drop function if exists ops_private.prune_snapshot_chunks_archive();
drop function if exists ops_private.snapshot_history_restorable(bigint);

-- drop table if exists ops_private.snapshot_chunks_archive;
