/*
  قفل دوال المحفظة والتذكيرات.

  قبل هذه الهجرة كان بإمكان أي شخص يملك المفتاح العام (anon) أن يشحن رصيدًا أو
  يخصمه لأي متجر. لا يوجد في التطبيق أو لوحة الإدارة من يستدعيها بغير مفتاح الإدارة.

  شرط التطبيق: نشر wallet.ts الجديد أولًا، وإلا تحوّل منع الصلاحية إلى إرسال بلا خصم.
  الاختبار: 20261108_wa_rpc_lockdown.test.sql
  الرجوع: 20261108_wa_rpc_lockdown.rollback.sql
*/

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

-- service_role فقط: تستدعيها الدوال ولوحة الإدارة بمفتاح الإدارة.
revoke execute on function public.wa_wallet_credit_lot(uuid, integer, text, text, text, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.wa_wallet_debit_one(uuid, text, text, text, uuid) from public, anon, authenticated;
revoke execute on function public.wa_wallet_ensure(uuid) from public, anon, authenticated;
revoke execute on function public.wa_wallet_expire_lots() from public, anon, authenticated;
revoke execute on function public.prune_whatsapp_diagnostic_events(integer) from public, anon, authenticated;
revoke execute on function public.whatsapp_lid_failure_stats(integer) from public, anon, authenticated;

grant execute on function public.wa_wallet_credit_lot(uuid, integer, text, text, text, uuid, text, text) to service_role;
grant execute on function public.wa_wallet_debit_one(uuid, text, text, text, uuid) to service_role;
grant execute on function public.wa_wallet_ensure(uuid) to service_role;
grant execute on function public.wa_wallet_expire_lots() to service_role;
grant execute on function public.prune_whatsapp_diagnostic_events(integer) to service_role;
grant execute on function public.whatsapp_lid_failure_stats(integer) to service_role;

-- authenticated وservice_role: يستدعيها Flutter والبوابة برمز المستخدم.
revoke execute on function public.wa_followup_schedule_job(text, text, jsonb, timestamptz) from public, anon;
revoke execute on function public.wa_followup_cancel_pending() from public, anon;
revoke execute on function public.acquire_whatsapp_gateway_lock(integer) from public, anon;
revoke execute on function public.release_whatsapp_gateway_lock() from public, anon;
revoke execute on function public.wa_followup_compute_due_at(timestamptz, integer, text, boolean) from public, anon;

grant execute on function public.wa_followup_schedule_job(text, text, jsonb, timestamptz) to authenticated, service_role;
grant execute on function public.wa_followup_cancel_pending() to authenticated, service_role;
grant execute on function public.acquire_whatsapp_gateway_lock(integer) to authenticated, service_role;
grant execute on function public.release_whatsapp_gateway_lock() to authenticated, service_role;
grant execute on function public.wa_followup_compute_due_at(timestamptz, integer, text, boolean) to authenticated, service_role;

commit;
