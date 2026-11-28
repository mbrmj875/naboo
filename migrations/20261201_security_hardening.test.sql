-- اختبار 20261201_security_hardening.sql.
-- يعمل داخل معاملة وينتهي دائماً باستثناء، فلا يبقى منه أي أثر.
-- النجاح = الرسالة ALL_TESTS_PASSED_ROLLED_BACK.
do $test$
declare
  a uuid := gen_random_uuid();
  b uuid := gen_random_uuid();
  v_slug text := 'sec-test-' || left(replace(gen_random_uuid()::text, '-', ''), 10);
  s_a uuid;
  s_b uuid;
  gid text;
  failed boolean;
  n int;
begin
  -- 0) العرض العام للقراءة فقط.
  if has_table_privilege('anon', 'public.marketplace_stores_public', 'update')
     or has_table_privilege('anon', 'public.marketplace_stores_public', 'delete')
     or has_table_privilege('anon', 'public.marketplace_stores_public', 'insert')
     or has_table_privilege('authenticated', 'public.marketplace_stores_public', 'update')
     or not has_table_privilege('anon', 'public.marketplace_stores_public', 'select') then
    raise exception 'TEST_FAIL view privileges';
  end if;

  -- 1) حساب ثانٍ يطلب الاسم نفسه فيأخذ متجراً جديداً، ولا يلمس متجر الأول.
  perform set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  s_a := public.marketplace_provision_store('متجر اختبار أ', v_slug);
  perform set_config('request.jwt.claims', json_build_object('sub', b, 'role', 'authenticated')::text, true);
  s_b := public.marketplace_provision_store('متجر اختبار ب', v_slug);
  if s_a = s_b then raise exception 'TEST_FAIL slug hijack'; end if;
  if (select tenant_uuid from public.marketplace_stores where id = s_a) <> a
     or (select name from public.marketplace_stores where id = s_a) <> 'متجر اختبار أ' then
    raise exception 'TEST_FAIL first store changed';
  end if;
  -- الطلب الثاني لنفس الحساب يعيد متجره.
  if public.marketplace_provision_store('أي اسم', null) <> s_b then
    raise exception 'TEST_FAIL idempotent provision';
  end if;

  -- 3) من لديه متجر لا يربط متجراً آخر.
  failed := false;
  begin
    perform public.marketplace_claim_store(gen_random_uuid());
  exception when others then failed := sqlerrm = 'ALREADY_HAS_STORE';
  end;
  if not failed then raise exception 'TEST_FAIL claim with store'; end if;

  -- 2) لا تصنيف لمنتج محل آخر.
  select product_global_id into gid from public.marketplace_products
  where product_global_id is not null limit 1;
  if gid is not null then
    select count(*) into n from public.marketplace_classification_queue where product_global_id = gid;
    if public.marketplace_enqueue_classification(gid) is not null then
      raise exception 'TEST_FAIL foreign enqueue';
    end if;
    if (select count(*) from public.marketplace_classification_queue where product_global_id = gid) <> n then
      raise exception 'TEST_FAIL foreign enqueue wrote';
    end if;
  end if;

  -- 4) دوال المزامنة الداخلية مغلقة، والعامة مفتوحة.
  if has_function_privilege('authenticated', 'public._rpc_process_sync_queue_legacy(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public._rpc_process_sync_queue_legacy_base(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.rpc_process_sync_queue(jsonb)', 'execute') then
    raise exception 'TEST_FAIL sync privileges';
  end if;

  -- 5) لا دالة مشغّل قابلة للاستدعاء من الزائر أو المستخدم.
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and p.prorettype = 'trigger'::regtype and p.prosecdef
    and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));
  if n > 0 then raise exception 'TEST_FAIL % trigger functions still executable', n; end if;

  -- 6) لا دالة بلا مسار بحث.
  select count(*) into n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
  where s.nspname = 'public' and p.prokind = 'f'
    and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e');
  if n > 0 then raise exception 'TEST_FAIL % functions without search_path', n; end if;

  -- 7) الزائر يرى الأعمدة العامة فقط، ويقرأ العرض بنجاح.
  if has_column_privilege('anon', 'public.marketplace_stores', 'internal_address', 'select')
     or has_column_privilege('anon', 'public.marketplace_stores', 'commission_rate_bps', 'select')
     or not has_column_privilege('anon', 'public.marketplace_stores', 'name', 'select')
     or has_table_privilege('anon', 'public.marketplace_stores', 'update') then
    raise exception 'TEST_FAIL anon columns';
  end if;
  perform set_config('request.jwt.claims', '', true);
  set local role anon;
  select count(*) into n from public.marketplace_stores_public;
  select count(*) into n from (select id, name, slug, rating_avg from public.marketplace_stores where is_published) x;
  reset role;

  -- 8) لا سياسة قراءة عامة تكشف قوائم الملفات.
  if exists (select 1 from pg_policies where schemaname = 'storage'
             and policyname in ('Public read store images', 'naboo_public_read')) then
    raise exception 'TEST_FAIL storage listing';
  end if;

  raise exception 'ALL_TESTS_PASSED_ROLLED_BACK';
end
$test$;
