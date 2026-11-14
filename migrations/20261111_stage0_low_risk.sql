-- المرحلة 0: البنود منخفضة الخطر التي لا تحتاج النسخة الخارجية أولاً.
-- لا يُطبَّق إلا بموافقة المالك، بين 6 و9 صباحاً بتوقيت بغداد، وكل قسم وحده.
-- القياس قبلها (10 نوفمبر 2026): القاعدة 2,218 ميغابايت، سجل المهام 1,014
-- ميغابايت منها 589,288 صفاً أقدم من 7 أيام، ومهمة المطاعم 5,753 تشغيلاً يومياً.

-------------------------------------------------------------------------------
-- (أ) دالة وقت الخادم. التطبيق يطلب app_server_time ثم server_time ثم now مع
-- كل فحص ترخيص، ولا توجد أي منها، فتفشل الثلاثة (نحو 2,492 خطأ يومياً).
-- بعد إنشائها تنجح الأولى في كل النسخ، القديمة والجديدة، فتنتهي المحاولتان
-- الباقيتان دون أي إصدار. لا تقرأ أي جدول.
-- الرجوع: drop function if exists public.app_server_time();
create or replace function public.app_server_time()
returns timestamptz
language sql
stable
set search_path = ''
as $$ select now() $$;

revoke all on function public.app_server_time() from public;
grant execute on function public.app_server_time() to anon, authenticated;

-------------------------------------------------------------------------------
-- (ب) البند 0.3: حذف سجل المهام الأقدم من 7 أيام على دفعات.
-- يُشغَّل هذا السطر مرات متتالية حتى يرجع 0 صفوف، كل دفعة 20,000 صف،
-- حتى لا يطول قفل الجدول. لا يمس أي جدول للزبائن.
-- delete from cron.job_run_details
--  where runid in (
--    select runid from cron.job_run_details
--     where end_time < now() - interval '7 days'
--     limit 20000
--  );
--
-- ثم حذف يومي دائم الساعة 3:15 بتوقيت الخادم (6:15 بتوقيت بغداد):
-- select cron.schedule(
--   'cleanup-cron-run-details',
--   '15 3 * * *',
--   $$delete from cron.job_run_details where end_time < now() - interval '7 days'$$
-- );
-- الرجوع: select cron.unschedule('cleanup-cron-run-details');
-- ملاحظة: الحذف لا يعيد المساحة للقرص فوراً، بل يعيد استعمالها. لا VACUUM FULL.

-------------------------------------------------------------------------------
-- (ج) البندان 0.11 و0.12 لمهمة المطاعم: تبقى كل 15 ثانية، لكنها لا تستدعي
-- الدالة الخارجية إلا عند وجود طلب تعمل عليه.
-- تصحيح للخطة: لا يوجد مشغّل يقبل طلب المطعم فوراً، فإبطاؤها إلى دقيقة كان
-- سيؤخر القبول التلقائي على الزبون. والدالة (restaurant-auto-accept-tick،
-- النسخة 38) لا تعمل إلا على طلبات qr_table بحالة new أقدم من 60 ثانية،
-- فالشرط أدناه هو شرطها نفسه.
-- القياس: 5,753 استدعاء يومياً، و3 طلبات مطاعم فقط منذ البداية، آخرها 22 أغسطس.
-- الرجوع: إعادة الأمر نفسه بدون سطر where exists.
-- select cron.alter_job(job_id := 7, command := $cmd$
-- SELECT net.http_post(
--   url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'restaurant_project_url' LIMIT 1) || '/functions/v1/restaurant-auto-accept-tick',
--   headers := jsonb_build_object(
--     'Content-Type', 'application/json',
--     'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'restaurant_anon_key' LIMIT 1),
--     'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'restaurant_anon_key' LIMIT 1),
--     'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'restaurant_cron_secret' LIMIT 1)
--   ),
--   body := jsonb_build_object('source', 'pg_cron', 'job', 'restaurant-auto-accept-tick', 'ts', now()),
--   timeout_milliseconds := 15000
-- ) AS request_id
-- WHERE EXISTS (
--   SELECT 1 FROM public.restaurant_orders o
--    WHERE o.channel = 'qr_table' AND o.state = 'new'
--      AND o.deleted_at IS NULL AND o.created_at < now() - interval '60 seconds'
-- );
-- $cmd$);

-------------------------------------------------------------------------------
-- (د) البند 0.11 لبطاقات PDF ومتابعة الزيوت: الجدول نفسه، والاستدعاء عند وجود عمل فقط.
-- القياس (10 نوفمبر): مهمة PDF تُستدعى 1,440 مرة يومياً لـ 39 بطاقة فقط،
-- والمتابعة 288 مرة يومياً لـ 38 رسالة. الشرط هو شرط الدالة نفسها:
--   whatsapp-oil-card-pdf-cron: status = 'pending' and idle_after <= now
--   whatsapp-oil-followup-cron: status = 'queued' and due_at <= now
-- لا يتأخر أي عمل: المهمة تعمل بالتوقيت نفسه، وتتخطى الاستدعاء حين لا عمل.
-- الرجوع: إعادة الأمر نفسه بدون سطر where exists.
-- select cron.alter_job(job_id := 5, command := $cmd$
-- select net.http_post(
--   url := (select value from public.whatsapp_ops_cron_config where key = 'whatsapp_oil_card_pdf_url'),
--   headers := jsonb_build_object(
--     'Content-Type', 'application/json',
--     'Authorization', 'Bearer ' || (select value from public.whatsapp_ops_cron_config where key = 'whatsapp_oil_card_pdf_bearer')
--   ),
--   body := '{"source":"pg_cron"}'::jsonb
-- )
-- where exists (
--   select 1 from public.whatsapp_oil_card_pdf_jobs j
--    where j.status = 'pending' and j.idle_after <= now()
-- );
-- $cmd$);
--
-- select cron.alter_job(job_id := 9, command := $cmd$
-- select net.http_post(
--   url := (select value from public.whatsapp_ops_cron_config where key = 'whatsapp_oil_followup_url'),
--   headers := jsonb_build_object(
--     'Content-Type', 'application/json',
--     'Authorization', 'Bearer ' || (select value from public.whatsapp_ops_cron_config where key = 'whatsapp_oil_followup_bearer')
--   ),
--   body := '{"source":"pg_cron"}'::jsonb
-- )
-- where exists (
--   select 1 from public.wa_oil_followup_jobs j
--    where j.status = 'queued' and j.due_at <= now()
-- );
-- $cmd$);
