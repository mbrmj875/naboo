/*
  اختبار 20261130_public_receipts.sql — داخل معاملة تتراجع، فلا يترك بيانات.
  يحاكي حسابين مسجّلين وزائراً بلا حساب.
*/
begin;

do $test$
declare
  t1 uuid := gen_random_uuid();
  t2 uuid := gen_random_uuid();
  tok text := 'AbCdEfGhIjKlMnOpQrStUv';
  v jsonb;
  g text;
  failed boolean;
begin
  -- 1) الحساب الأول يرفع نسخة.
  perform set_config('request.jwt.claims', json_build_object('sub', t1, 'role', 'authenticated')::text, true);
  perform public.receipt_publish(tok, 1, 'gid-1', '{"title":"إيصال بيع","v":1}'::jsonb);

  -- 2) القراءة العامة بالرمز تُرجع النسخة وحالتها السارية.
  v := public.receipt_public_get(tok);
  if v->>'title' <> 'إيصال بيع' or v ? 'owner_uid' or v->>'state' is not null then
    raise exception 'TEST_FAIL public get %', v;
  end if;

  -- 3) رمز خاطئ أو قصير لا يُرجع شيئاً.
  if public.receipt_public_get('short') is not null
     or public.receipt_public_get('ZZZZZZZZZZZZZZZZZZZZZZ') is not null
     or public.receipt_public_get('x'' or 1=1 --') is not null then
    raise exception 'TEST_FAIL bad token';
  end if;

  -- 4) الحساب الثاني لا يستطيع الكتابة فوق رمز الأول ولا معرفة فاتورته.
  perform set_config('request.jwt.claims', json_build_object('sub', t2, 'role', 'authenticated')::text, true);
  failed := false;
  begin
    perform public.receipt_publish(tok, 1, 'gid-x', '{"title":"مزوّر"}'::jsonb);
  exception when others then failed := sqlerrm = 'RECEIPT_TOKEN_TAKEN';
  end;
  if not failed then raise exception 'TEST_FAIL token takeover'; end if;
  if public.receipt_owner_lookup(tok) is not null then
    raise exception 'TEST_FAIL foreign lookup';
  end if;
  perform public.receipt_set_state('gid-1', 'deleted');
  if public.receipt_public_get(tok)->>'state' is not null then
    raise exception 'TEST_FAIL foreign state change';
  end if;

  -- 5) صاحب الرمز يعرف فاتورته، ويحدّث النسخة، ويعلّمها مسترجعة ثم محذوفة.
  perform set_config('request.jwt.claims', json_build_object('sub', t1, 'role', 'authenticated')::text, true);
  g := public.receipt_owner_lookup(tok);
  if g <> 'gid-1' then raise exception 'TEST_FAIL owner lookup %', g; end if;
  perform public.receipt_publish(tok, 1, 'gid-1', '{"title":"إيصال بيع","v":2}'::jsonb);
  if (public.receipt_public_get(tok)->>'v') <> '2' then raise exception 'TEST_FAIL update'; end if;
  perform public.receipt_set_state('gid-1', 'returned');
  if public.receipt_public_get(tok)->>'state' <> 'returned' then raise exception 'TEST_FAIL returned'; end if;
  perform public.receipt_set_state('gid-1', 'deleted');
  v := public.receipt_public_get(tok);
  if v <> '{"state":"deleted"}'::jsonb then raise exception 'TEST_FAIL deleted shows data %', v; end if;

  -- 6) بلا حساب: لا رفع.
  perform set_config('request.jwt.claims', '', true);
  failed := false;
  begin
    perform public.receipt_publish('QqQqQqQqQqQqQqQqQqQqQq', 1, 'g', '{}'::jsonb);
  exception when others then failed := sqlerrm = 'RECEIPT_UNAUTHENTICATED';
  end;
  if not failed then raise exception 'TEST_FAIL anon publish'; end if;

  -- 7) الصلاحيات: الزائر لا يقرأ الجدول مباشرة ولا يرفع.
  if has_table_privilege('anon', 'public.public_receipts', 'select')
     or has_function_privilege('anon', 'public.receipt_publish(text, integer, text, jsonb)', 'execute')
     or not has_function_privilege('anon', 'public.receipt_public_get(text)', 'execute') then
    raise exception 'TEST_FAIL privileges';
  end if;

  raise notice 'public_receipts: all tests passed';
end
$test$;

rollback;
