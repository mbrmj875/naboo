/*
  اختبار 20261108_wa_rpc_lockdown.sql — قراءة فقط، يصلح للإنتاج بعد التطبيق.
  النتيجة المتوقعة: رسالة TEST_PASSED، وأي فشل يظهر كخطأ TEST_FAIL.
*/

do $test$
declare
  r record;
  v_fail text := '';
  v_n int := 0;
begin
  for r in
    select * from (values
      ('public.wa_wallet_credit_lot(uuid, integer, text, text, text, uuid, text, text)', false),
      ('public.wa_wallet_debit_one(uuid, text, text, text, uuid)', false),
      ('public.wa_wallet_ensure(uuid)', false),
      ('public.wa_wallet_expire_lots()', false),
      ('public.prune_whatsapp_diagnostic_events(integer)', false),
      ('public.whatsapp_lid_failure_stats(integer)', false),
      ('public.wa_followup_schedule_job(text, text, jsonb, timestamptz)', true),
      ('public.wa_followup_cancel_pending()', true),
      ('public.acquire_whatsapp_gateway_lock(integer)', true),
      ('public.release_whatsapp_gateway_lock()', true),
      ('public.wa_followup_compute_due_at(timestamptz, integer, text, boolean)', true)
    ) as t(fn, auth_allowed)
  loop
    v_n := v_n + 1;
    if has_function_privilege('anon', r.fn, 'execute') then
      v_fail := v_fail || ' anon:' || r.fn;
    end if;
    if has_function_privilege('authenticated', r.fn, 'execute') <> r.auth_allowed then
      v_fail := v_fail || ' authenticated:' || r.fn;
    end if;
    if not has_function_privilege('service_role', r.fn, 'execute') then
      v_fail := v_fail || ' service_role:' || r.fn;
    end if;
  end loop;

  if v_fail <> '' then
    raise exception 'TEST_FAIL:%', v_fail;
  end if;
  raise notice 'TEST_PASSED: % functions', v_n;
end;
$test$;
