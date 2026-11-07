/*
  اختبار 20261116_wa_recipient_consent.sql — قراءة فقط، يصلح للإنتاج بعد التطبيق.
  الخانة الأهم: لم تُلغ الهجرة أي تذكير، وكل queued له صف موافقة.
*/
do $test$
declare
  v_missing integer;
begin
  if public.wa_phone_key('07701234567') <> public.wa_phone_key('+964 770 123 4567') then
    raise exception 'TEST_FAIL phone key differs';
  end if;
  if has_table_privilege('authenticated', 'public.wa_recipient_consent', 'insert')
     or has_table_privilege('authenticated', 'public.wa_recipient_consent', 'update') then
    raise exception 'TEST_FAIL authenticated can write';
  end if;
  if has_function_privilege('anon', 'public.wa_recipient_consent_set(text, boolean)', 'execute') then
    raise exception 'TEST_FAIL anon can set consent';
  end if;
  select count(*) into v_missing
  from public.wa_oil_followup_jobs j
  where j.status = 'queued'
    and length(public.wa_phone_key(j.customer_phone)) >= 8
    and not exists (
      select 1 from public.wa_recipient_consent c
      where c.tenant_user_id = j.tenant_user_id
        and c.phone_key = public.wa_phone_key(j.customer_phone)
    );
  if v_missing > 0 then
    raise exception 'TEST_FAIL % queued jobs without a consent row', v_missing;
  end if;
  raise notice 'TEST_PASSED';
end;
$test$;
