-- مراقبة خارجية للمهام الدورية عبر healthchecks.io (13 نوفمبر 2026).
--
-- كل مهمة تطرق رابطها بعد أن تنتهي دون خطأ. إن فشلت المهمة أو توقفت المهام
-- كلها تصمت الطرقة، فيصل التنبيه إلى المالك.
--
-- الروابط لا تُكتب هنا لأن المستودع عام. تُدخل في ops_private.heartbeat_urls
-- مباشرة على الخادم. مهمة بلا رابط لا تطرق شيئاً ولا تفشل.
--
-- الرجوع: 20261113_ops_heartbeats.rollback.sql يعيد أوامر المهام كما كانت.

create schema if not exists ops_private;
revoke all on schema ops_private from public, anon, authenticated;

create table if not exists ops_private.heartbeat_urls (
  job text primary key,
  url text not null
);
revoke all on ops_private.heartbeat_urls from public, anon, authenticated;

-- نسخة من أوامر المهام قبل التعديل، ومنها يقرأ ملف الرجوع.
create table if not exists ops_private.cron_command_backup (
  jobname text primary key,
  command text not null,
  saved_at timestamptz not null default now()
);
revoke all on ops_private.cron_command_backup from public, anon, authenticated;

create or replace function ops_private.ping(p_job text, p_fail boolean default false)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
begin
  select url into v_url from ops_private.heartbeat_urls where job = p_job;
  if v_url is null then
    return;
  end if;
  perform net.http_get(
    url := v_url || case when p_fail then '/fail' else '' end,
    timeout_milliseconds := 10000
  );
exception when others then
  -- الطرقة لا تُفشل المهمة الأصلية أبداً.
  null;
end;
$$;
revoke all on function ops_private.ping(text, boolean) from public, anon, authenticated;

-- هل ما زالت المحلات ترفع؟ جهاز واحد على الأقل خلال 4 ساعات.
-- القياس (7 أيام): كل ساعة من 7 إلى 20 UTC فيها رفع في أغلب الأيام، والنافذة
-- 4 ساعات تمنع الإنذار الكاذب في ساعة هادئة.
create or replace function ops_private.check_sync_alive()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alive boolean;
begin
  select exists (
    select 1 from public.app_snapshots
    where updated_at > now() - interval '4 hours'
  ) into v_alive;
  perform ops_private.ping('sync-alive', not v_alive);
end;
$$;
revoke all on function ops_private.check_sync_alive() from public, anon, authenticated;

-- احفظ الأوامر الحالية مرة واحدة فقط، فإعادة التشغيل لا تكتب فوق الأصل.
insert into ops_private.cron_command_backup (jobname, command)
select jobname, command from cron.job
where jobname in (
  'cleanup_sync_notifications', 'whatsapp-oil-card-pdf',
  'restaurant-auto-accept-tick', 'whatsapp-health-check',
  'whatsapp-oil-followup', 'cleanup-cron-run-details',
  'cleanup-wa-delivery-stats', 'cleanup-snapshot-history',
  'daily-account-metrics', 'sync-guard-violations-cleanup'
)
on conflict (jobname) do nothing;

-- أضف الطرقة بعد أمر كل مهمة. whatsapp-ops-analyst تطرق من دالتها نفسها، فلا تُمس.
-- مهام واتساب الثلاث تتصل بدالتها فقط عند وجود عمل، والطرقة بعدها تعمل دائماً:
-- فهي تثبت أن المهمة دارت، لا أن الدالة نجحت.
do $$
declare
  r record;
  v_ping text;
begin
  for r in
    select j.jobid, j.jobname, b.command
    from cron.job j
    join ops_private.cron_command_backup b using (jobname)
  loop
    -- مهمة المطاعم تعمل كل 15 ثانية وتطرق مع كل دورة: شرط «مرة في الدقيقة»
    -- فوّت دقائق لأنها تبدأ عند الثانية 5 و20 و35 و50.
    v_ping := 'select ops_private.ping(''' || r.jobname || ''')';
    perform cron.alter_job(
      job_id := r.jobid,
      command := regexp_replace(r.command, '[\s;]+$', '') || ';' || chr(10) || v_ping || ';'
    );
  end loop;
end;
$$;

-- مهمة جديدة: كل ساعة من 12 ظهراً إلى 11 ليلاً بتوقيت بغداد.
select cron.schedule('ops-sync-alive', '0 9-20 * * *', 'select ops_private.check_sync_alive()');
