/*
  اختبار 20261128_assistant_b6.sql — داخل معاملة تتراجع، فلا يترك بيانات.
*/
begin;

do $test$
declare
  v_pick int;
  v_first uuid;
  v_uses int;
  v_fails int;
  v_oj int;
  v_of int;
  v_l bigint;
begin
  -- 1) الدوال للخادم وحده.
  if has_function_privilege('authenticated', 'public.assistant_pick_for_judging(integer, text)', 'execute')
     or has_function_privilege('anon', 'public.assistant_lesson_usage(integer)', 'execute') then
    raise exception 'TEST_FAIL learn functions open to the app';
  end if;

  -- 2) الاختيار: يتجاهل المحكوم والقديم وتشغيلات الاختبار، والفاشل أولاً.
  insert into public.assistant_turns (id, tenant_id, thread_id, question_clean, answer_clean, model, created_at, app_version, s_rephrased)
  values
    ('00000000-0000-0000-0000-00000000b601', 'test-b6-a', gen_random_uuid(), 'س عادي', 'ج', 'm', now(), '1', null),
    ('00000000-0000-0000-0000-00000000b602', 'test-b6-a', gen_random_uuid(), 'س أعاده', 'ج', 'm', now(), '1', true),
    ('00000000-0000-0000-0000-00000000b603', 'test-b6-a', gen_random_uuid(), 'س قديم', 'ج', 'm', now() - interval '3 days', '1', true),
    ('00000000-0000-0000-0000-00000000b604', 'test-b6-a', gen_random_uuid(), 'س اختبار', 'ج', 'm', now(), 'eval', true);
  select count(*) filter (where id::text like '%b60%'), (array_agg(id))[1]
    into v_pick, v_first
    from public.assistant_pick_for_judging(500, 'app')
   where tenant_id = 'test-b6-a';
  if v_pick <> 2 then raise exception 'TEST_FAIL picked % (want 2)', v_pick; end if;
  if v_first <> '00000000-0000-0000-0000-00000000b602' then raise exception 'TEST_FAIL failed turn not first'; end if;

  -- 3) أثر الدرس: سؤالان استعملاه، واحد محكوم فاشل.
  insert into public.assistant_lessons (kind, topic, trigger_text, body, status, activated_at)
  values ('rule', 'test-b6', 'س', 'درس اختبار', 'active', now() - interval '20 days')
  returning id into v_l;
  update public.assistant_turns set lesson_ids = array[v_l], judged_at = now(), j_answered = false
   where id = '00000000-0000-0000-0000-00000000b601';
  update public.assistant_turns set lesson_ids = array[v_l]
   where id = '00000000-0000-0000-0000-00000000b602';
  select uses, fails, overall_judged, overall_fails into v_uses, v_fails, v_oj, v_of
    from public.assistant_lesson_usage(30) where id = v_l;
  if v_uses <> 2 or v_fails <> 1 or v_oj < 1 or v_of < 1 then
    raise exception 'TEST_FAIL usage % % % %', v_uses, v_fails, v_oj, v_of;
  end if;

  -- 4) المهمتان مجدولتان، وبريد الدعم في جدول الخادم.
  if (select count(*) from cron.job where jobname in ('assistant-learn-nightly', 'assistant-learn-evaluate')) <> 2 then
    raise exception 'TEST_FAIL cron jobs missing';
  end if;
  if not exists (select 1 from public.ops_edge_cron_config where key = 'assistant_support_email') then
    raise exception 'TEST_FAIL support email missing';
  end if;
end
$test$;

rollback;
