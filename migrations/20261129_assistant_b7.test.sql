/*
  اختبار 20261129_assistant_b7.sql — داخل معاملة تتراجع، فلا يترك بيانات.
*/
begin;

do $test$
declare
  -- حسابان حقيقيان (السجل مربوط بـ auth.users)؛ كل شيء يتراجع.
  t1 uuid := (select id from auth.users order by created_at limit 1);
  t2 uuid := (select id from auth.users order by created_at offset 1 limit 1);
  v_log uuid;
  v_other uuid;
  v_turn uuid := gen_random_uuid();
  v_notes jsonb;
  v_seen int;
begin
  -- 1) الجدار: المقال افتراضه داخلي.
  if (select column_default from information_schema.columns
       where table_name = 'assistant_knowledge' and column_name = 'audience') not like '%app%' then
    raise exception 'TEST_FAIL knowledge audience default';
  end if;

  delete from public.whatsapp_responder_profiles where tenant_user_id = t1;
  delete from public.whatsapp_visit_requests where tenant_user_id = t1;

  -- 2) «رد خاطئ»: يضيف ملاحظة ويعلّم الدور.
  insert into public.assistant_turns (id, tenant_id, thread_id, channel, question_clean, answer_clean, model, app_version)
  values (v_turn, t1::text, gen_random_uuid(), 'whatsapp', 'س', 'ج', 'm', null);
  insert into public.whatsapp_message_logs (tenant_user_id, template_key, to_phone, status, body, assistant_turn_id)
  values (t1, 'rating_auto_reply', '9647700000000', 'sent', 'رد', v_turn) returning id into v_log;
  insert into public.whatsapp_message_logs (tenant_user_id, template_key, to_phone, status, body)
  values (t2, 'rating_auto_reply', '9647700000001', 'sent', 'رد') returning id into v_other;

  perform set_config('request.jwt.claim.sub', t1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', t1::text, 'role', 'authenticated')::text, true);

  perform public.whatsapp_correct_reply(v_log, 'الدوام من 9 للـ 9');
  select notes into v_notes from public.whatsapp_responder_profiles where tenant_user_id = t1;
  if jsonb_array_length(v_notes) <> 1 or v_notes -> 0 ->> 'source' <> 'correction' then
    raise exception 'TEST_FAIL correction note %', v_notes;
  end if;
  if not (select s_user_corrected from public.assistant_turns where id = v_turn) then
    raise exception 'TEST_FAIL turn not marked';
  end if;

  -- 3) لا يصحّح رد محل آخر.
  begin
    perform public.whatsapp_correct_reply(v_other, 'محاولة');
    raise exception 'TEST_FAIL corrected another tenant';
  exception when others then
    if sqlerrm like 'TEST_FAIL%' then raise; end if;
  end;

  -- 4) 20 ملاحظة كحد: يسقط أقدم تصحيح، وملاحظات المالك تبقى.
  update public.whatsapp_responder_profiles
     set notes = (select jsonb_agg(jsonb_build_object('text', 'م' || g, 'source', 'owner')) from generate_series(1, 19) g)
              || jsonb_build_array(jsonb_build_object('text', 'قديم', 'source', 'correction'))
   where tenant_user_id = t1;
  perform public.whatsapp_correct_reply(v_log, 'جديد');
  select notes into v_notes from public.whatsapp_responder_profiles where tenant_user_id = t1;
  if jsonb_array_length(v_notes) <> 20 or v_notes::text like '%قديم%' or v_notes::text not like '%جديد%' then
    raise exception 'TEST_FAIL notes cap %', jsonb_array_length(v_notes);
  end if;

  -- 5) طلب زيارة واحد مفتوح لكل زبون في اليوم.
  insert into public.whatsapp_visit_requests (tenant_user_id, customer_phone, request) values (t1, '964770', 'باچر');
  begin
    insert into public.whatsapp_visit_requests (tenant_user_id, customer_phone, request) values (t1, '964770', 'مرة ثانية');
    raise exception 'TEST_FAIL duplicate visit';
  exception when unique_violation then null;
  end;

  -- 6) العزل: سياسات الجداول الثلاثة على auth.uid().
  select count(*) into v_seen from pg_policies
   where tablename in ('whatsapp_responder_profiles', 'whatsapp_handoffs', 'whatsapp_visit_requests')
     and qual like '%auth.uid()%';
  if v_seen < 5 then raise exception 'TEST_FAIL policies %', v_seen; end if;
  if has_function_privilege('anon', 'public.whatsapp_correct_reply(uuid, text)', 'execute') then
    raise exception 'TEST_FAIL anon can correct';
  end if;

  raise exception 'TEST_PASS';
end
$test$;

rollback;
