/*
  تراجع عن 20261108_wa_rpc_lockdown.sql — يعيد الصلاحيات كما كانت في الإنتاج
  بتاريخ 2026-11-07: anon وauthenticated وservice_role، وبلا PUBLIC.

  تحذير: يعيد فتح الشحن والخصم للمفتاح العام. استعمله عند العطل فقط.
*/

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

grant execute on function public.wa_wallet_credit_lot(uuid, integer, text, text, text, uuid, text, text) to anon, authenticated, service_role;
grant execute on function public.wa_wallet_debit_one(uuid, text, text, text, uuid) to anon, authenticated, service_role;
grant execute on function public.wa_wallet_ensure(uuid) to anon, authenticated, service_role;
grant execute on function public.wa_wallet_expire_lots() to anon, authenticated, service_role;
grant execute on function public.prune_whatsapp_diagnostic_events(integer) to anon, authenticated, service_role;
grant execute on function public.whatsapp_lid_failure_stats(integer) to anon, authenticated, service_role;
grant execute on function public.wa_followup_schedule_job(text, text, jsonb, timestamptz) to anon, authenticated, service_role;
grant execute on function public.wa_followup_cancel_pending() to anon, authenticated, service_role;
grant execute on function public.acquire_whatsapp_gateway_lock(integer) to anon, authenticated, service_role;
grant execute on function public.release_whatsapp_gateway_lock() to anon, authenticated, service_role;
grant execute on function public.wa_followup_compute_due_at(timestamptz, integer, text, boolean) to anon, authenticated, service_role;

commit;
