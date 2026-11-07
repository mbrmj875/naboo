/*
  اختبار 20261115_whatsapp_onboarding_state.sql — قراءة فقط، يصلح للإنتاج بعد التطبيق.
  النتيجة المتوقعة: رسالة TEST_PASSED، وأي فشل يظهر كخطأ TEST_FAIL.
*/

do $test$
begin
  if to_regclass('public.whatsapp_onboarding_state') is null then
    raise exception 'TEST_FAIL table missing';
  end if;
  if not (select relrowsecurity from pg_class
          where oid = 'public.whatsapp_onboarding_state'::regclass) then
    raise exception 'TEST_FAIL rls off';
  end if;
  if has_table_privilege('anon', 'public.whatsapp_onboarding_state', 'select') then
    raise exception 'TEST_FAIL anon can read';
  end if;
  if not has_table_privilege('authenticated', 'public.whatsapp_onboarding_state', 'select') then
    raise exception 'TEST_FAIL authenticated cannot read';
  end if;
  if has_table_privilege('authenticated', 'public.whatsapp_onboarding_state', 'insert')
     or has_table_privilege('authenticated', 'public.whatsapp_onboarding_state', 'update')
     or has_table_privilege('authenticated', 'public.whatsapp_onboarding_state', 'delete') then
    raise exception 'TEST_FAIL authenticated can write';
  end if;
  raise notice 'TEST_PASSED';
end;
$test$;
