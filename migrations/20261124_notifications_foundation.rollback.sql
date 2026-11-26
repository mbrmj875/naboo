-- تراجع المرحلة 1 (الجداول + هاتف المالك). يحذف السجل الموحد وما فيه.
select cron.unschedule(jobid) from cron.job where jobname in ('notify-dispatch-due', 'cleanup-notifications');
drop trigger if exists trg_notifications_kick_dispatch on public.notifications;
drop trigger if exists trg_disable_push_on_device_revoke on public.account_devices;
drop function if exists public.notifications_kick_dispatch();
drop function if exists public.disable_push_on_device_revoke();
drop function if exists public.app_register_push_device(text, text, text, text, integer, text, text, text[]);
drop function if exists public.app_unregister_push_device(text);
drop function if exists public.app_mark_notifications_read(bigint[]);
drop table if exists public.notifications, public.notification_events, public.notification_preferences, public.push_devices;
delete from public.ops_edge_cron_config where key = 'notify_dispatch_url';
-- هاتف المالك
drop trigger if exists trg_guard_account_device_owner_notify on public.account_devices;
drop function if exists public.guard_account_device_owner_notify();
drop function if exists public.app_set_owner_notify_device(text, boolean);
drop function if exists public.account_has_owner_phone(uuid);
drop index if exists public.account_devices_owner_notify_idx;
alter table public.account_devices drop column if exists owner_notify, drop column if exists owner_notify_at;
