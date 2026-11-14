-- المرحلة 0-ج (الجزء الثاني): ضغط أرشيف النسخ بعد تخفيفه (14 نوفمبر 2026).
--
-- ليس ملف تغيير: لا يُطبَّق بـ apply_migration لأن VACUUM FULL لا يعمل داخل
-- معاملة. هو دليل تشغيل بثلاث خطوات، كل خطوة استدعاء execute_sql مستقل.
--
-- لماذا: المهمة thin-snapshot-history (05:00 بغداد) تحذف 2989 نسخة، لكن
-- الحذف لا يعيد المساحة. القياس (14 نوفمبر 02:40): الجدول 1063 MB، منها
-- 1048 MB بيانات النسخ الكبيرة (TOAST)، والباقي بعد التخفيف حوالي 23 MB.
--
-- الخطر: VACUUM FULL يقفل الجدول قفلاً كاملاً حتى ينتهي. كل رفع نسخة يكتب في
-- هذا الجدول (fn_archive_app_snapshot_before_update)، فينتظر. مهلة الرفع من
-- التطبيق 8 ثوانٍ (authenticated statement_timeout)؛ إن تجاوزها فشل الرفع
-- وأعاده التطبيق بعد دقيقة، والبيانات باقية على الجهاز.
-- القياس: 24 رفعة فقط بين 05:00 و06:00 في 27 يوماً، أي حوالي واحدة في اليوم.
-- النسخ الجديدة 23 MB، فالمدة المتوقعة ثوانٍ (تقدير لم يُقس على الخادم).
--
-- الوقت: بين 05:15 و07:30 بتوقيت بغداد فقط، وبعد نجاح التخفيف.
-- الرجوع: لا شيء يُرجع؛ الضغط لا يغير أي صف. إن عُلّق يُلغى بـ
--   select pg_cancel_backend(pid) from pg_stat_activity
--    where query ilike 'vacuum (full%app_snapshots_history%' and pid <> pg_backend_pid();

-- الخطوة 1: فحص قبل الضغط. يتوقف التنفيذ إن لم تتحقق كل الشروط:
--   now_baghdad بين 05:15 و07:30، thin_ok = true، history أقل من 600،
--   long_xacts = 0، vacuum_running = 0.
select to_char(now() at time zone 'Asia/Baghdad', 'MM-DD HH24:MI') as now_baghdad,
       exists (
         select 1 from cron.job_run_details d join cron.job j using (jobid)
          where j.jobname = 'thin-snapshot-history' and d.status = 'succeeded'
            and d.start_time > now() - interval '3 hours'
       ) as thin_ok,
       (select count(*) from public.app_snapshots_history) as history,
       (select count(*) from public.app_snapshots) as snapshots,
       (select count(*) from pg_stat_activity
         where state <> 'idle' and backend_type = 'client backend'
           and xact_start < now() - interval '5 seconds'
           and pid <> pg_backend_pid()) as long_xacts,
       (select count(*) from pg_stat_activity
         where query ilike 'vacuum%' and pid <> pg_backend_pid()) as vacuum_running,
       pg_size_pretty(pg_total_relation_size('public.app_snapshots_history')) as size_before,
       pg_size_pretty(pg_database_size(current_database())) as db_before;

-- الخطوة 2: الضغط (وحده في استدعاء مستقل).
vacuum (full, analyze) public.app_snapshots_history;

-- الخطوة 3: فحص بعد الضغط. العدد يطابق الخطوة 1، والحجم نزل.
select (select count(*) from public.app_snapshots_history) as history,
       (select count(*) from public.app_snapshots) as snapshots,
       pg_size_pretty(pg_total_relation_size('public.app_snapshots_history')) as size_after,
       pg_size_pretty(pg_database_size(current_database())) as db_after,
       (select count(*) from pg_trigger
         where tgrelid = 'public.app_snapshots'::regclass
           and tgname ilike '%archive%') as archive_trigger_present;
