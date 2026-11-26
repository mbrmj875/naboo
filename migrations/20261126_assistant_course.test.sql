/*
  اختبار 20261126_assistant_course.sql — داخل معاملة تتراجع، فلا يترك بيانات.
*/
begin;

do $test$
begin
  -- 1) الزائر لا يلمس الجدول، والمستخدم لا يحذف.
  if has_table_privilege('anon', 'public.assistant_course_progress', 'select')
     or has_table_privilege('authenticated', 'public.assistant_course_progress', 'delete') then
    raise exception 'TEST_FAIL wrong privileges';
  end if;
  if not has_table_privilege('authenticated', 'public.assistant_course_progress', 'insert') then
    raise exception 'TEST_FAIL app cannot record progress';
  end if;

  -- 2) RLS مفعّل وكل السياسات مقيّدة بالمحل.
  if not (select relrowsecurity from pg_class where oid = 'public.assistant_course_progress'::regclass) then
    raise exception 'TEST_FAIL rls off';
  end if;
  if (select count(*) from pg_policies where tablename = 'assistant_course_progress'
      and coalesce(qual, '') || coalesce(with_check, '') like '%app_current_tenant_id%') <> 3 then
    raise exception 'TEST_FAIL policies not tenant scoped';
  end if;
end
$test$;

-- 3) محاكاة محلين: كل محل يرى صفه فقط، والتكرار يحدّث ولا يضاعف.
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","tenant_id":"test-course-a"}';
insert into public.assistant_course_progress (user_key, user_name, task_id) values ('emp1', 'علي', 'oil_first_card');
insert into public.assistant_course_progress (user_key, user_name, task_id) values ('emp1', 'علي', 'oil_first_card')
  on conflict (tenant_id, user_key, task_id) do update set done_at = now();

do $t$
begin
  if (select count(*) from public.assistant_course_progress) <> 1 then
    raise exception 'TEST_FAIL duplicate rows';
  end if;
end
$t$;

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","tenant_id":"test-course-b"}';
do $t$
begin
  if (select count(*) from public.assistant_course_progress) <> 0 then
    raise exception 'TEST_FAIL tenant b sees tenant a';
  end if;
  begin
    insert into public.assistant_course_progress (tenant_id, user_key, task_id) values ('test-course-a', 'x', 'spoof');
    raise exception 'TEST_FAIL wrote into another tenant';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.assistant_course_progress (user_key, task_id) values ('x', 'Bad Id!');
    raise exception 'TEST_FAIL free text task id accepted';
  exception when check_violation then null;
  end;
end
$t$;

reset role;
select 'assistant_course tests passed' as result;
rollback;
