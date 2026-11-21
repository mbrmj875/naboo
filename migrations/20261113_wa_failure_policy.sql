/*
  أعمدة سياسة الفشل: إعادة المؤقت، وإيقاف الطابور للمتجر أو لرقم نابو، والإسقاط
  الذي يخفي الرسالة دون مسح سببها.

  إضافة فقط، فلا تتأثر الإصدارات المنشورة. تُطبق قبل نشر دوال الدفعة 6، لأن
  whatsapp-oil-followup-cron يقرأ next_attempt_at مباشرة.
  الاختبار: 20261113_wa_failure_policy.test.sql
  الرجوع: 20261113_wa_failure_policy.rollback.sql
*/

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

alter table public.wa_oil_followup_jobs
  add column if not exists attempts integer not null default 0,
  add column if not exists next_attempt_at timestamptz,
  add column if not exists last_error_code text;

alter table public.tenant_whatsapp_gateways
  add column if not exists send_block_reason text,
  add column if not exists send_block_since timestamptz;

alter table public.wa_message_platform_settings
  add column if not exists send_block_reason text,
  add column if not exists send_block_since timestamptz;

alter table public.whatsapp_message_logs
  add column if not exists dismissed_at timestamptz;

commit;
