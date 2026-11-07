/*
  اختبار 20261114_wa_wallet_settle.sql — ينتهي دائمًا بـ RAISE EXCEPTION فيُلغى كل
  ما أنشأه. شغّله على بيئة محلية أو اختبار، لا على الإنتاج.
  النتيجة المتوقعة: TEST_PASSED_AND_ROLLED_BACK.
*/

do $test$
declare
  t uuid := gen_random_uuid();
  bal integer;
  v jsonb;
  since timestamptz := now() - interval '10 days';
  n integer;
begin
  insert into auth.users (id) values (t);
  perform public.wa_wallet_credit_lot(t, 10, 'monthly', 'purchase', 'test', null, null, 'seed');

  -- 1) فشل ثم إعادة ناجحة = وحدة واحدة.
  perform public.wa_wallet_debit_one(t, 'a');
  insert into public.whatsapp_message_logs (tenant_user_id, status, idempotency_key)
    values (t, 'failed', 'a');
  v := public.wa_wallet_debit_one(t, 'a');
  if not (v ->> 'duplicate')::boolean then
    raise exception 'TEST_FAIL: free retry within window';
  end if;
  update public.whatsapp_message_logs set status = 'delivered'
    where tenant_user_id = t and idempotency_key = 'a';
  update public.wa_message_ledger set created_at = now() - interval '2 days'
    where tenant_user_id = t and idempotency_key = 'a';
  perform public.wa_wallet_settle_failed(since, false);
  select balance into bal from public.wa_message_wallet where tenant_user_id = t;
  if bal <> 9 then raise exception 'TEST_FAIL: case 1 balance %', bal; end if;

  -- 2) فشل بلا إعادة = صفر، بعد 24 ساعة فقط.
  perform public.wa_wallet_debit_one(t, 'b');
  insert into public.whatsapp_message_logs (tenant_user_id, status, idempotency_key)
    values (t, 'failed', 'b');
  v := public.wa_wallet_settle_failed(since, false);
  if (v ->> 'refunded')::integer <> 0 then
    raise exception 'TEST_FAIL: refunded inside the 24 hour window';
  end if;
  update public.wa_message_ledger set created_at = now() - interval '2 days'
    where tenant_user_id = t and idempotency_key = 'b';

  v := public.wa_wallet_settle_failed(since, true);
  select balance into bal from public.wa_message_wallet where tenant_user_id = t;
  if (v ->> 'refunded')::integer <> 1 or bal <> 8 then
    raise exception 'TEST_FAIL: dry run wrote or missed, % bal %', v, bal;
  end if;

  v := public.wa_wallet_settle_failed(since, false);
  select balance into bal from public.wa_message_wallet where tenant_user_id = t;
  if (v ->> 'refunded')::integer <> 1 or bal <> 9 then
    raise exception 'TEST_FAIL: case 2 refund, % bal %', v, bal;
  end if;

  -- التشغيل المتكرر لا يغير الرصيد.
  v := public.wa_wallet_settle_failed(since, false);
  v := public.wa_wallet_settle_failed(since, false);
  select balance into bal from public.wa_message_wallet where tenant_user_id = t;
  if bal <> 9 then raise exception 'TEST_FAIL: repeat run balance %', bal; end if;

  -- 3) فشل ثم استرداد ثم إعادة ناجحة = وحدة واحدة.
  v := public.wa_wallet_debit_one(t, 'b');
  if (v ->> 'duplicate') is not null then
    raise exception 'TEST_FAIL: retry after refund must debit';
  end if;
  select balance into bal from public.wa_message_wallet where tenant_user_id = t;
  if bal <> 8 then raise exception 'TEST_FAIL: case 3 balance %', bal; end if;
  select count(*) into n from public.wa_message_ledger
    where tenant_user_id = t and idempotency_key = 'b#2' and delta = -1;
  if n <> 1 then raise exception 'TEST_FAIL: new debit key missing'; end if;

  -- إعادة ثانية بعد الخصم الجديد مجانية.
  v := public.wa_wallet_debit_one(t, 'b');
  if not (v ->> 'duplicate')::boolean then
    raise exception 'TEST_FAIL: second retry must be free';
  end if;

  update public.whatsapp_message_logs set status = 'delivered'
    where tenant_user_id = t and idempotency_key = 'b';
  update public.wa_message_ledger set created_at = now() - interval '2 days'
    where tenant_user_id = t and idempotency_key = 'b#2';
  perform public.wa_wallet_settle_failed(since, false);
  select balance into bal from public.wa_message_wallet where tenant_user_id = t;
  if bal <> 8 then raise exception 'TEST_FAIL: delivered must not refund, %', bal; end if;

  -- الإسقاط يعيد الوحدة فورًا.
  perform public.wa_wallet_debit_one(t, 'c');
  insert into public.whatsapp_message_logs (tenant_user_id, status, idempotency_key, dismissed_at)
    values (t, 'rejected', 'c', now());
  perform public.wa_wallet_settle_failed(since, false);
  select balance into bal from public.wa_message_wallet where tenant_user_id = t;
  if bal <> 8 then raise exception 'TEST_FAIL: dismiss refund, %', bal; end if;

  -- خصم قبل حد التاريخ لا تمسه الدورية، وتمسه تسوية الماضي فقط.
  perform public.wa_wallet_debit_one(t, 'old');
  insert into public.whatsapp_message_logs (tenant_user_id, status, idempotency_key)
    values (t, 'failed', 'old');
  update public.wa_message_ledger set created_at = now() - interval '60 days'
    where tenant_user_id = t and idempotency_key = 'old';
  v := public.wa_wallet_settle_failed(since, false);
  if (v ->> 'refunded')::integer <> 0 then
    raise exception 'TEST_FAIL: cron floor touched an old debit';
  end if;
  v := public.wa_wallet_settle_failed(null, true);
  if (v ->> 'refunded')::integer <> 1 then
    raise exception 'TEST_FAIL: past dry run missed the old debit';
  end if;

  -- مفتاح يشبه العائلة لا يُخلط بها.
  perform public.wa_wallet_debit_one(t, 'x');
  v := public.wa_wallet_debit_one(t, 'x#note');
  if (v ->> 'duplicate') is not null then
    raise exception 'TEST_FAIL: a look-alike key joined the family';
  end if;

  raise exception 'TEST_PASSED_AND_ROLLED_BACK';
end;
$test$;
