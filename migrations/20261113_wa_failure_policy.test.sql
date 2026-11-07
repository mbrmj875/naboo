/*
  اختبار 20261113_wa_failure_policy.sql — قراءة فقط، يصلح للإنتاج بعد التطبيق.
  النتيجة المتوقعة: رسالة TEST_PASSED، وأي فشل يظهر كخطأ TEST_FAIL.
*/

do $test$
declare
  r record;
  v_missing text := '';
begin
  for r in
    select * from (values
      ('wa_oil_followup_jobs', 'attempts'),
      ('wa_oil_followup_jobs', 'next_attempt_at'),
      ('wa_oil_followup_jobs', 'last_error_code'),
      ('tenant_whatsapp_gateways', 'send_block_reason'),
      ('tenant_whatsapp_gateways', 'send_block_since'),
      ('wa_message_platform_settings', 'send_block_reason'),
      ('wa_message_platform_settings', 'send_block_since'),
      ('whatsapp_message_logs', 'dismissed_at')
    ) as t(tbl, col)
  loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = r.tbl and column_name = r.col
    ) then
      v_missing := v_missing || ' ' || r.tbl || '.' || r.col;
    end if;
  end loop;
  if v_missing <> '' then
    raise exception 'TEST_FAIL: missing%', v_missing;
  end if;
  raise notice 'TEST_PASSED';
end;
$test$;
