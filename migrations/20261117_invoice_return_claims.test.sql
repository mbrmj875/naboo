/*
  اختبار 20261117_invoice_return_claims.sql — يعمل داخل معاملة ويتراجع، فلا يترك بيانات.
  يحاكي جلستين لمستأجرين مختلفين عبر request.jwt.claims.
*/
begin;

do $test$
declare
  v_orig uuid := gen_random_uuid();
  v_r1 uuid := gen_random_uuid();
  v_r2 uuid := gen_random_uuid();
  v_r3 uuid := gen_random_uuid();
  v_res jsonb;
begin
  if has_table_privilege('authenticated', 'public.invoice_return_claims', 'insert')
     or has_table_privilege('authenticated', 'public.invoice_return_claims', 'select') then
    raise exception 'TEST_FAIL authenticated can touch the table directly';
  end if;
  if has_function_privilege('anon',
       'public.rpc_claim_invoice_return(uuid, uuid, jsonb, numeric, text)', 'execute') then
    raise exception 'TEST_FAIL anon can claim';
  end if;

  perform set_config('request.jwt.claims', '{"tenant_id":"test-tenant-a"}', true);

  -- 1) مطالبة أولى: 2 من 5.
  v_res := public.rpc_claim_invoice_return(v_orig, v_r1,
    '[{"key":"line-1","qty":2,"sold":5}]', 2000, 'tester');
  if (v_res ->> 'ok')::boolean is not true then
    raise exception 'TEST_FAIL first claim %', v_res;
  end if;

  -- 2) إعادة الطلب نفسه لا تكرر.
  v_res := public.rpc_claim_invoice_return(v_orig, v_r1,
    '[{"key":"line-1","qty":2,"sold":5}]', 2000, 'tester');
  if (v_res ->> 'replay')::boolean is not true then
    raise exception 'TEST_FAIL replay %', v_res;
  end if;

  -- 3) تجاوز المباع يُرفض حتى لو ادّعى الجهاز مبيعاً أكبر.
  v_res := public.rpc_claim_invoice_return(v_orig, v_r2,
    '[{"key":"line-1","qty":4,"sold":50}]', 4000, 'tester');
  if (v_res ->> 'ok')::boolean or v_res ->> 'reason' <> 'exceeds_sold'
     or (v_res ->> 'remaining')::numeric <> 3 then
    raise exception 'TEST_FAIL exceed %', v_res;
  end if;

  -- 3ب) سطر سليم مع سطر متجاوز: لا يُحفظ أي منهما.
  v_res := public.rpc_claim_invoice_return(v_orig, v_r2,
    '[{"key":"line-2","qty":1,"sold":1},{"key":"line-1","qty":9,"sold":5}]', 9000, 'tester');
  if (v_res ->> 'ok')::boolean then
    raise exception 'TEST_FAIL mixed lines accepted %', v_res;
  end if;
  if exists (select 1 from public.invoice_return_claims where line_key = 'line-2') then
    raise exception 'TEST_FAIL partial claim saved';
  end if;

  -- 4) المتبقي مسموح.
  v_res := public.rpc_claim_invoice_return(v_orig, v_r2,
    '[{"key":"line-1","qty":3,"sold":5}]', 3000, 'tester');
  if (v_res ->> 'ok')::boolean is not true then
    raise exception 'TEST_FAIL remaining claim %', v_res;
  end if;

  -- 5) الإلغاء يعيد الكمية.
  if not public.rpc_void_return_claim(v_r2) then
    raise exception 'TEST_FAIL void';
  end if;
  v_res := public.rpc_claim_invoice_return(v_orig, v_r3,
    '[{"key":"line-1","qty":3,"sold":5}]', 3000, 'tester');
  if (v_res ->> 'ok')::boolean is not true then
    raise exception 'TEST_FAIL after void %', v_res;
  end if;

  -- 6) مستأجر آخر لا يتأثر ولا يلغي مطالبات غيره.
  perform set_config('request.jwt.claims', '{"tenant_id":"test-tenant-b"}', true);
  if public.rpc_void_return_claim(v_r1) then
    raise exception 'TEST_FAIL tenant b voided tenant a';
  end if;
  v_res := public.rpc_claim_invoice_return(v_orig, gen_random_uuid(),
    '[{"key":"line-1","qty":5,"sold":5}]', 5000, 'tester');
  if (v_res ->> 'ok')::boolean is not true then
    raise exception 'TEST_FAIL tenant isolation %', v_res;
  end if;

  raise notice 'TEST_PASSED';
end;
$test$;

rollback;
