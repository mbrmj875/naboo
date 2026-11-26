begin;
select cron.unschedule(jobname) from cron.job where jobname in ('assistant-learn-nightly', 'assistant-learn-evaluate');
delete from public.ops_edge_cron_config where key in ('assistant_learn_url', 'assistant_support_email');
drop function if exists public.assistant_lesson_usage(integer);
drop function if exists public.assistant_pick_for_judging(integer, text);
alter table public.assistant_support_requests drop column if exists notified_at;
alter table public.assistant_lessons drop column if exists eval_requested_at, drop column if exists merged_from;
commit;
