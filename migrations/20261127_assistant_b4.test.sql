/*
  اختبار 20261127_assistant_b4.sql — داخل معاملة تتراجع، فلا يترك بيانات.
*/
begin;

do $test$
declare
  t text;
begin
  -- 1) جداول الخادم وحده: لا قراءة ولا كتابة للتطبيق ولا للزائر.
  foreach t in array array['assistant_car_specs', 'assistant_car_aliases', 'assistant_support_requests', 'assistant_knowledge'] loop
    if has_table_privilege('anon', 'public.' || t, 'select')
       or has_table_privilege('authenticated', 'public.' || t, 'select')
       or has_table_privilege('authenticated', 'public.' || t, 'insert') then
      raise exception 'TEST_FAIL % open to the app', t;
    end if;
    if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
      raise exception 'TEST_FAIL rls off on %', t;
    end if;
  end loop;

  -- 2) الذاكرة: قراءة وإضافة وحذف، ولا تعديل، وكل السياسات مقيّدة بالمحل.
  if has_table_privilege('anon', 'public.assistant_shop_memory', 'select')
     or has_table_privilege('authenticated', 'public.assistant_shop_memory', 'update') then
    raise exception 'TEST_FAIL wrong memory privileges';
  end if;
  if (select count(*) from pg_policies where tablename = 'assistant_shop_memory'
      and coalesce(qual, '') || coalesce(with_check, '') like '%app_current_tenant_id%') <> 3 then
    raise exception 'TEST_FAIL memory policies not tenant scoped';
  end if;
end
$test$;

-- 3) محلان: كل محل يرى ذاكرته فقط، ولا يكتب في غيره، والنص الفارغ أو الطويل مرفوض.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","tenant_id":"test-mem-a"}';
insert into public.assistant_shop_memory (text, created_by) values ('نغلق الجمعة', 'المالك');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","tenant_id":"test-mem-b"}';
do $t$
begin
  if (select count(*) from public.assistant_shop_memory) <> 0 then
    raise exception 'TEST_FAIL tenant b sees tenant a memory';
  end if;
  begin
    insert into public.assistant_shop_memory (tenant_id, text) values ('test-mem-a', 'spoof');
    raise exception 'TEST_FAIL wrote into another tenant';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.assistant_shop_memory (text) values (repeat('x', 301));
    raise exception 'TEST_FAIL long text accepted';
  exception when check_violation then null;
  end;
end
$t$;

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","tenant_id":"test-mem-a"}';
do $t$
begin
  if (select count(*) from public.assistant_shop_memory) <> 1 then
    raise exception 'TEST_FAIL tenant a lost its memory';
  end if;
end
$t$;

reset role;

-- 4) دليل السيارات: درجة ثقة غير معروفة وسعة خارج الحدود مرفوضة.
do $t$
begin
  begin
    insert into public.assistant_car_specs (make, model, year_from, year_to, confidence) values ('x', 'y', 2015, 2016, 'unverified');
    raise exception 'TEST_FAIL unverified spec saved';
  exception when check_violation then null;
  end;
  begin
    insert into public.assistant_car_specs (make, model, year_from, year_to, oil_capacity_l, confidence) values ('x', 'y', 2015, 2016, 99, 'verified');
    raise exception 'TEST_FAIL capacity out of range';
  exception when check_violation then null;
  end;
end
$t$;

select 'ALL B4 TESTS PASSED' as result;
rollback;
