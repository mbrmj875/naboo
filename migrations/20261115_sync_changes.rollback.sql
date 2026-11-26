-- رجوع عن 20261115_sync_changes.sql.
-- يحذف سجل التعديلات. النسخة الكاملة لم تتوقف أثناء المرحلة 4، فلا يضيع شيء
-- من بيانات المحلات.
begin;

select cron.unschedule('prune-sync-changes')
  where exists (select 1 from cron.job where jobname = 'prune-sync-changes');

drop trigger if exists trg_bump_sync_generation_on_restore on public.app_snapshots;
drop function if exists public.fn_bump_sync_generation_on_restore();
drop function if exists public.rpc_push_changes(text, integer, jsonb);
drop function if exists public.rpc_pull_changes(text, bigint, integer, integer);
drop function if exists ops_private.set_sync_changes_enabled(uuid, boolean);
drop function if exists ops_private.prune_sync_changes(integer, integer);

do $$
begin
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'sync_change_signals'
  ) then
    execute 'alter publication supabase_realtime drop table public.sync_change_signals';
  end if;
end $$;

drop table if exists public.sync_change_signals;
drop table if exists public.sync_changes;
drop table if exists public.sync_account_state;

commit;
