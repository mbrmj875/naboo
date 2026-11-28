-- اختبار 20261202_owner_pin_server_verify.sql — ينتهي باستثناء فلا يبقى أثر.
-- النجاح = ALL_TESTS_PASSED_ROLLED_BACK.
do $test$
declare
  u uuid := gen_random_uuid();
  r jsonb;
  i int;
begin
  insert into auth.users (id) values (u);

  -- أربع محاولات: مسموحة والمتبقي ينقص.
  for i in 1..4 loop
    r := public.owner_pin_attempt_begin(u);
    if not (r->>'allowed')::boolean or (r->>'remaining')::int <> 5 - i or r->>'locked_until' is not null then
      raise exception 'TEST_FAIL attempt % %', i, r;
    end if;
  end loop;

  -- الخامسة مسموحة لكنها تضع القفل إن فشلت.
  r := public.owner_pin_attempt_begin(u);
  if not (r->>'allowed')::boolean or r->>'locked_until' is null then
    raise exception 'TEST_FAIL fifth %', r;
  end if;

  -- السادسة مرفوضة.
  r := public.owner_pin_attempt_begin(u);
  if (r->>'allowed')::boolean then raise exception 'TEST_FAIL sixth allowed %', r; end if;
  if (select locked_until from public.owner_pin_attempts where user_id = u)
     not between now() + interval '14 minutes' and now() + interval '16 minutes' then
    raise exception 'TEST_FAIL first lock length';
  end if;

  -- انتهاء القفل ثم فشل خمس مرات أخرى: القفل يتضاعف.
  update public.owner_pin_attempts set locked_until = now() - interval '1 second' where user_id = u;
  for i in 1..5 loop perform public.owner_pin_attempt_begin(u); end loop;
  if (select locked_until from public.owner_pin_attempts where user_id = u)
     not between now() + interval '29 minutes' and now() + interval '31 minutes' then
    raise exception 'TEST_FAIL escalation';
  end if;

  -- تعيين PIN جديد يفك القفل.
  insert into public.owner_auth_secrets (user_id, phone, pin_hash, pin_salt) values (u, '07700000000', 'h1', 's1')
  on conflict (user_id) do update set pin_hash = 'h1';
  if exists (select 1 from public.owner_pin_attempts where user_id = u) then
    raise exception 'TEST_FAIL secret change did not clear';
  end if;

  -- تحديث لا يغيّر الـ hash لا يفك قفلاً.
  for i in 1..5 loop perform public.owner_pin_attempt_begin(u); end loop;
  update public.owner_auth_secrets set phone = '07711111111' where user_id = u;
  if not exists (select 1 from public.owner_pin_attempts where user_id = u and locked_until > now()) then
    raise exception 'TEST_FAIL phone change cleared lock';
  end if;

  -- النجاح يمسح كل شيء.
  perform public.owner_pin_attempt_success(u);
  if exists (select 1 from public.owner_pin_attempts where user_id = u) then
    raise exception 'TEST_FAIL success did not clear';
  end if;

  -- التطبيق لا يصل إلى العدّاد ولا الجدول.
  if has_function_privilege('authenticated', 'public.owner_pin_attempt_begin(uuid)', 'execute')
     or has_function_privilege('anon', 'public.owner_pin_attempt_success(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.owner_pin_attempt_success(uuid)', 'execute')
     or has_table_privilege('authenticated', 'public.owner_pin_attempts', 'select')
     or has_table_privilege('anon', 'public.owner_pin_attempts', 'delete')
     or not has_function_privilege('service_role', 'public.owner_pin_attempt_begin(uuid)', 'execute') then
    raise exception 'TEST_FAIL privileges';
  end if;

  raise exception 'ALL_TESTS_PASSED_ROLLED_BACK';
end
$test$;
