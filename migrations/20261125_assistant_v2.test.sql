/*
  اختبار 20261125_assistant_v2.sql — داخل معاملة تتراجع، فلا يترك بيانات.
*/
begin;

do $test$
declare
  v jsonb;
  t text := 'test-tenant-assistant';
begin
  -- 1) مستخدمو التطبيق لا يلمسون جداول المساعد.
  if has_table_privilege('authenticated', 'public.assistant_turns', 'select')
     or has_table_privilege('authenticated', 'public.assistant_turns', 'insert')
     or has_table_privilege('anon', 'public.assistant_lessons', 'select')
     or has_table_privilege('authenticated', 'public.assistant_budget', 'insert')
     or has_table_privilege('authenticated', 'public.assistant_eval_cases', 'select') then
    raise exception 'TEST_FAIL app users can touch assistant tables';
  end if;
  if has_function_privilege('authenticated',
       'public.assistant_budget_add(text, bigint, integer, integer, text)', 'execute') then
    raise exception 'TEST_FAIL app users can add budget';
  end if;

  -- 2) الهاتف لم يعد يكتب الأمثلة (ع8).
  if has_table_privilege('authenticated', 'public.assistant_approved_examples', 'insert')
     or exists (select 1 from pg_policies where tablename = 'assistant_approved_examples'
                and cmd in ('INSERT', 'UPDATE')) then
    raise exception 'TEST_FAIL phone can still promote examples';
  end if;
  if (select count(*) from public.assistant_lessons where origin = 'legacy_example')
     < (select count(*) from public.assistant_approved_examples) then
    raise exception 'TEST_FAIL legacy examples not copied';
  end if;

  -- 3) محل جديد: كامل.
  v := public.assistant_budget_check(t, 'app', false);
  if v ->> 'mode' <> 'full' or (v ->> 'monthly')::bigint <> 1000000 then
    raise exception 'TEST_FAIL fresh tenant %', v;
  end if;

  -- 4) الحد اليومي 8% = 80,000. نصرف 79,000 ثم 2,000 فيُستنفد اليوم.
  perform public.assistant_budget_add(t, 79000, 0, 0, 'app');
  v := public.assistant_budget_check(t, 'app', false);
  if v ->> 'mode' <> 'full' then raise exception 'TEST_FAIL before daily cap %', v; end if;
  perform public.assistant_budget_add(t, 2000, 1, 1, 'app');
  v := public.assistant_budget_check(t, 'app', false);
  if v ->> 'mode' <> 'exhausted' then raise exception 'TEST_FAIL daily cap %', v; end if;

  -- 5) الوضع الاقتصادي عند 70% (نفرّغ عدّاد اليوم لنختبر الشهري وحده).
  update public.assistant_budget set micro_usd = 700000, today = current_date - 1
   where tenant_id = t and channel = 'app';
  v := public.assistant_budget_check(t, 'app', false);
  if v ->> 'mode' <> 'economy' then raise exception 'TEST_FAIL economy %', v; end if;

  -- 6) السقف الشهري.
  update public.assistant_budget set micro_usd = 1000000 where tenant_id = t and channel = 'app';
  v := public.assistant_budget_check(t, 'app', false);
  if v ->> 'mode' <> 'exhausted' then raise exception 'TEST_FAIL monthly cap %', v; end if;

  -- 7) قناة واتساب منفصلة (ق88): ما زالت كاملة وسقفها نصف دولار.
  v := public.assistant_budget_check(t, 'whatsapp', false);
  if v ->> 'mode' <> 'full' or (v ->> 'monthly')::bigint <> 500000 then
    raise exception 'TEST_FAIL whatsapp separate %', v;
  end if;

  -- 8) التجريبي ربع دولار (ق51).
  v := public.assistant_budget_check('test-trial', 'app', true);
  if (v ->> 'monthly')::bigint <> 250000 then raise exception 'TEST_FAIL trial cap %', v; end if;

  -- 9) سقف خاص بمحل، والمحل النموذجي بلا سقف (ق54).
  insert into public.assistant_tenant_settings (tenant_id, monthly_cap_micro_usd) values (t, 2000000);
  v := public.assistant_budget_check(t, 'app', false);
  if v ->> 'mode' <> 'full' or (v ->> 'monthly')::bigint <> 2000000 then
    raise exception 'TEST_FAIL override %', v;
  end if;
  update public.assistant_tenant_settings set monthly_cap_micro_usd = 1, is_demo = true where tenant_id = t;
  v := public.assistant_budget_check(t, 'app', false);
  if v ->> 'mode' <> 'full' then raise exception 'TEST_FAIL demo has cap %', v; end if;

  -- 10) المحل يقرأ إعداده فقط.
  insert into public.assistant_tenant_settings (tenant_id, v2_enabled) values ('other-tenant', true);
  perform set_config('request.jwt.claims', json_build_object('tenant_id', t)::text, true);
  set local role authenticated;
  if (select count(*) from public.assistant_tenant_settings) <> 1 then
    raise exception 'TEST_FAIL tenant sees other settings';
  end if;
  reset role;

  -- 11) الحذف بعد 60 يوماً.
  insert into public.assistant_turns (id, tenant_id, thread_id, question_clean, model, created_at)
  values (gen_random_uuid(), t, gen_random_uuid(), 'قديم', 'm', now() - interval '61 days'),
         (gen_random_uuid(), t, gen_random_uuid(), 'جديد', 'm', now());
  -- استدعاء منفصل: الفحص في الاستعلام نفسه يرى لقطة ما قبل الحذف.
  if public.assistant_purge_old() < 1 then
    raise exception 'TEST_FAIL purge count';
  end if;
  if exists (select 1 from public.assistant_turns where question_clean = 'قديم')
     or not exists (select 1 from public.assistant_turns where question_clean = 'جديد') then
    raise exception 'TEST_FAIL purge';
  end if;

  -- 12) مفاتيح الإعداد العام موجودة.
  if not exists (select 1 from public.app_remote_config
                 where id = 1 and config -> 'assistant' ? 'kill'
                   and config -> 'assistant' -> 'caps' ? 'execute') then
    raise exception 'TEST_FAIL remote config keys';
  end if;

  raise notice 'TEST_OK assistant_v2';
end
$test$;

rollback;
