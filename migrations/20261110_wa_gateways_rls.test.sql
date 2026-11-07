/*
  اختبار 20261110_wa_gateways_rls.sql — قراءة فقط، يصلح للإنتاج بعد التطبيق.
  النتيجة المتوقعة: رسالة TEST_PASSED، وأي فشل يظهر كخطأ TEST_FAIL.
*/

do $test$
declare
  t constant text := 'public.tenant_whatsapp_gateways';
  v_fail text := '';
begin
  if has_table_privilege('anon', t, 'select,insert,update,delete,truncate') then
    v_fail := v_fail || ' anon_has_table_access';
  end if;
  if not has_table_privilege('authenticated', t, 'select') then
    v_fail := v_fail || ' authenticated_cannot_select';
  end if;
  if has_table_privilege('authenticated', t, 'insert,update,delete,truncate') then
    v_fail := v_fail || ' authenticated_has_table_write';
  end if;
  if has_column_privilege('authenticated', t, 'status', 'update') then
    v_fail := v_fail || ' authenticated_can_update_status';
  end if;
  if has_column_privilege('authenticated', t, 'cloud_phone_number_id', 'update') then
    v_fail := v_fail || ' authenticated_can_update_phone_id';
  end if;
  if not has_column_privilege('authenticated', t, 'rating_auto_reply', 'update') then
    v_fail := v_fail || ' authenticated_cannot_update_rating';
  end if;
  if not has_table_privilege('service_role', t, 'select,insert,update,delete') then
    v_fail := v_fail || ' service_role_lost_access';
  end if;
  if exists (
    select 1 from pg_policy
    where polrelid = t::regclass and polname = 'tenant_whatsapp_gateways_own'
  ) then
    v_fail := v_fail || ' old_policy_still_there';
  end if;
  if (
    select count(*) from pg_policy
    where polrelid = t::regclass
      and polname in (
        'tenant_whatsapp_gateways_select_own',
        'tenant_whatsapp_gateways_update_own'
      )
  ) <> 2 then
    v_fail := v_fail || ' new_policies_missing';
  end if;

  if v_fail <> '' then
    raise exception 'TEST_FAIL:%', v_fail;
  end if;
  raise notice 'TEST_PASSED';
end;
$test$;
