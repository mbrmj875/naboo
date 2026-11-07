/*
  تراجع عن 20261113_wa_failure_policy.sql. أرجع الدوال إلى إصدارها السابق أولًا،
  وإلا تفشل قراءتها لهذه الأعمدة.

  تحذير: يحذف عدد المحاولات وأسباب الإيقاف وأوقات الإسقاط.
*/

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

alter table public.wa_oil_followup_jobs
  drop column if exists attempts,
  drop column if exists next_attempt_at,
  drop column if exists last_error_code;

alter table public.tenant_whatsapp_gateways
  drop column if exists send_block_reason,
  drop column if exists send_block_since;

alter table public.wa_message_platform_settings
  drop column if exists send_block_reason,
  drop column if exists send_block_since;

alter table public.whatsapp_message_logs
  drop column if exists dismissed_at;

commit;
