/*
  اختبار 20261020_device_lifecycle_fix.sql — يعمل داخل كتلة DO واحدة تنتهي دائماً
  بـ RAISE EXCEPTION ⇒ يُلغى كل ما أنشأه الاختبار (مستخدم تجريبي، أجهزة، رخصة)
  مهما كان نمط تنفيذ الأداة (لا حاجة لـ BEGIN/ROLLBACK).

  شغّله بعد تطبيق الـ migration (على staging أو على النسخة المحلية tool/device_lifecycle_local_stub.sql).
  النتيجة المتوقعة (رسالة "خطأ" مقصودة):
      TEST_PASSED_AND_ROLLED_BACK: ...
  أي رسالة أخرى تبدأ بـ TEST_FAIL: أو غيرها = فشل.

  ملاحظة: يُنشئ صفاً في auth.users. إن كانت بيئتك تتطلب أعمدة إضافية NOT NULL
  أضفها في إدخال الـ fixture أدناه.
*/

do $test$
declare
  v_uid  uuid := gen_random_uuid();
  v_uid2 uuid := gen_random_uuid();
  r      jsonb;
  n      int;
  s      text;
  v_log  text := '';
begin
  -- ── fixtures (بصلاحية المالك) ───────────────────────────────────────────────
  insert into auth.users (id) values (v_uid), (v_uid2);

  -- ════════════════════════════════════════════════════════════════════════════
  -- السيناريو A: حدّ افتراضي 2 (لا رخصة ⇒ app_user_max_devices() = 2)
  -- ════════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid::text, 'role', 'authenticated', 'session_id', 'sess-test')::text, true);
  set local role authenticated;

  -- A1: تسجيل جهازين
  r := public.app_register_device('D1', 'DESKTOP', 'windows');
  if r->>'access_status' <> 'active' then raise exception 'TEST_FAIL A1: D1 %', r; end if;
  r := public.app_register_device('D2', 'PHONE', 'android');
  if r->>'access_status' <> 'active' or (r->>'active_devices')::int <> 2 then
    raise exception 'TEST_FAIL A1: D2 %', r;
  end if;
  v_log := v_log || 'A1 ';

  -- A2: فصل D2 بـ UPDATE مباشر (مثل "الخروج النهائي") ⇒ يُسجَّل حدث source=direct
  update public.account_devices set access_status = 'revoked' where user_id = v_uid and device_id = 'D2';
  select count(*) into n from public.account_device_events
   where user_id = v_uid and device_id = 'D2' and new_status = 'revoked'
     and source = 'direct' and actor_session_id = 'sess-test';
  if n <> 1 then raise exception 'TEST_FAIL A2: audit event missing (n=%)', n; end if;
  v_log := v_log || 'A2 ';

  -- A3: نافذة السماح 30 ثانية: heartbeat فوري من D2 يبقى مفصولاً
  r := public.app_register_device('D2', 'PHONE', 'android');
  if r->>'access_status' <> 'revoked' or r->>'reason' <> 'recently_revoked' then
    raise exception 'TEST_FAIL A3: expected recently_revoked, got %', r;
  end if;
  v_log := v_log || 'A3 ';

  -- A4: بعد النافذة، يوجد مكان (D1 فقط نشط من 2) ⇒ D2 يعود تلقائياً   [إصلاح المشكلة الأصلية]
  reset role;
  update public.account_device_events set created_at = created_at - interval '5 minutes' where user_id = v_uid;
  set local role authenticated;
  r := public.app_register_device('D2', 'PHONE', 'android');
  if r->>'access_status' <> 'active' or (r->>'active_devices')::int <> 2 then
    raise exception 'TEST_FAIL A4: D2 should be re-activated, got %', r;
  end if;
  select count(*) into n from public.account_devices where user_id = v_uid and access_status = 'active';
  if n <> 2 then raise exception 'TEST_FAIL A4: D1 must remain active (active=%)', n; end if;
  v_log := v_log || 'A4 ';

  -- A5: الحد ممتلئ: D2 مفصول ⇒ D3 جديد يملأ المكان ⇒ D2 يبقى مفصولاً (device_limit_reached)
  update public.account_devices set access_status = 'revoked' where user_id = v_uid and device_id = 'D2';
  reset role;
  update public.account_device_events set created_at = created_at - interval '5 minutes' where user_id = v_uid;
  set local role authenticated;
  r := public.app_register_device('D3', 'TABLET', 'android');
  if r->>'access_status' <> 'active' then raise exception 'TEST_FAIL A5: D3 %', r; end if;
  r := public.app_register_device('D2', 'PHONE', 'android');
  if r->>'access_status' <> 'revoked' or r->>'reason' <> 'device_limit_reached' then
    raise exception 'TEST_FAIL A5: expected device_limit_reached, got %', r;
  end if;
  begin
    perform public.app_register_device('D4', 'NEW', 'android');
    raise exception 'TEST_FAIL A5: D4 should hit DEVICE_LIMIT_REACHED';
  exception when others then
    if sqlerrm like 'TEST_FAIL%' then raise; end if;
    if sqlerrm not like 'DEVICE_LIMIT_REACHED%' then raise exception 'TEST_FAIL A5: unexpected %', sqlerrm; end if;
  end;
  v_log := v_log || 'A5 ';

  -- A6: استعادة المالك D2 والحد ممتلئ (D1,D3 نشطان): تفصل جهازاً واحداً فقط = الأقدم نشاطاً
  reset role;
  update public.account_devices set last_seen_at = now() - interval '1 hour'   where user_id = v_uid and device_id = 'D1';
  update public.account_devices set last_seen_at = now() - interval '5 minutes' where user_id = v_uid and device_id = 'D3';
  set local role authenticated;
  r := public.app_owner_recover_device('D2', true);
  if (r->>'revoked_others')::int <> 1 or (r->>'active_devices')::int <> 2 then
    raise exception 'TEST_FAIL A6: expected exactly 1 evicted, got %', r;
  end if;
  select string_agg(device_id || '=' || access_status, ',' order by device_id) into s
    from public.account_devices where user_id = v_uid;
  if s <> 'D1=revoked,D2=active,D3=active' then raise exception 'TEST_FAIL A6: state %', s; end if;
  select count(*) into n from public.account_device_events
   where user_id = v_uid and device_id = 'D1' and new_status = 'revoked'
     and source = 'rpc:app_owner_recover_device';
  if n <> 1 then raise exception 'TEST_FAIL A6: recover audit missing (n=%)', n; end if;
  v_log := v_log || 'A6 ';

  -- A7: استعادة D1 مع p_revoke_other_devices=false والحد ممتلئ ⇒ ترفض
  begin
    perform public.app_owner_recover_device('D1', false);
    raise exception 'TEST_FAIL A7: should refuse';
  exception when others then
    if sqlerrm like 'TEST_FAIL%' then raise; end if;
    if sqlerrm not like 'DEVICE_LIMIT_REACHED%' then raise exception 'TEST_FAIL A7: unexpected %', sqlerrm; end if;
  end;
  v_log := v_log || 'A7 ';

  -- A8: زر "السماح": UPDATE مباشر لإلغاء الفصل. ممتلئ ⇒ يرفض؛ بعد إفساح مكان ⇒ ينجح
  begin
    update public.account_devices set access_status = 'active' where user_id = v_uid and device_id = 'D1';
    raise exception 'TEST_FAIL A8: approve should be refused when full';
  exception when others then
    if sqlerrm like 'TEST_FAIL%' then raise; end if;
    if sqlerrm not like 'cannot_unrevoke_device_limit_reached%' then raise exception 'TEST_FAIL A8: unexpected %', sqlerrm; end if;
  end;
  update public.account_devices set access_status = 'revoked' where user_id = v_uid and device_id = 'D3';
  update public.account_devices set access_status = 'active'  where user_id = v_uid and device_id = 'D1';
  select count(*) into n from public.account_devices where user_id = v_uid and access_status = 'active';
  if n <> 2 then raise exception 'TEST_FAIL A8: expected 2 active, got %', n; end if;
  v_log := v_log || 'A8 ';

  -- A9: استعادة عند وجود مكان لا تفصل أحداً
  update public.account_devices set access_status = 'revoked' where user_id = v_uid and device_id = 'D1';
  r := public.app_owner_recover_device('D3', true);
  if (r->>'revoked_others')::int <> 0 or (r->>'active_devices')::int <> 2 then
    raise exception 'TEST_FAIL A9: no eviction expected, got %', r;
  end if;
  select access_status into s from public.account_devices where user_id = v_uid and device_id = 'D2';
  if s <> 'active' then raise exception 'TEST_FAIL A9: D2 must remain active'; end if;
  v_log := v_log || 'A9 ';

  -- A10: DEVICE_NOT_FOUND محفوظ
  begin
    perform public.app_owner_recover_device('NOPE', true);
    raise exception 'TEST_FAIL A10: should raise DEVICE_NOT_FOUND';
  exception when others then
    if sqlerrm like 'TEST_FAIL%' then raise; end if;
    if sqlerrm not like 'DEVICE_NOT_FOUND%' then raise exception 'TEST_FAIL A10: unexpected %', sqlerrm; end if;
  end;
  v_log := v_log || 'A10 ';

  -- ════════════════════════════════════════════════════════════════════════════
  -- السيناريو B: رخصة بحدّ 6 — حالة الحادثة: جهازان فقط نشطان من 6
  -- ════════════════════════════════════════════════════════════════════════════
  reset role;
  insert into public.licenses (license_key, status, plan, max_devices, assigned_user_id)
  values ('TEST-' || v_uid2::text, 'active', 'monthly', 6, v_uid2);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_uid2::text, 'role', 'authenticated', 'session_id', 'sess-test-2')::text, true);
  set local role authenticated;

  r := public.app_register_device('PC',    'DESKTOP-X', 'windows');
  r := public.app_register_device('PHONE', 'realme',    'android');
  if (r->>'max_devices')::int <> 6 then raise exception 'TEST_FAIL B1: max %', r; end if;

  -- الهاتف يخرج نهائياً ثم يعيد الدخول بعد دقيقة (الجهاز الآخر ما زال نشطاً)
  update public.account_devices set access_status = 'revoked' where user_id = v_uid2 and device_id = 'PHONE';
  reset role;
  update public.account_device_events set created_at = created_at - interval '5 minutes' where user_id = v_uid2;
  set local role authenticated;
  r := public.app_register_device('PHONE', 'realme', 'android');
  if r->>'access_status' <> 'active' then
    raise exception 'TEST_FAIL B2 (incident repro): revoked phone must return while 1 of 6 slots used, got %', r;
  end if;
  select access_status into s from public.account_devices where user_id = v_uid2 and device_id = 'PC';
  if s <> 'active' then raise exception 'TEST_FAIL B2: PC must stay active'; end if;
  v_log := v_log || 'B2 ';

  -- استعادة بـ OTP والحد بعيد: لا تفصل أحداً (كان يفصل الكل)
  update public.account_devices set access_status = 'revoked' where user_id = v_uid2 and device_id = 'PHONE';
  r := public.app_owner_recover_device('PHONE', true);
  if (r->>'revoked_others')::int <> 0 then raise exception 'TEST_FAIL B3: %', r; end if;
  select access_status into s from public.account_devices where user_id = v_uid2 and device_id = 'PC';
  if s <> 'active' then raise exception 'TEST_FAIL B3: PC must stay active'; end if;
  v_log := v_log || 'B3 ';

  -- ملء الحد (6) ثم الجهاز السابع جديد ⇒ يرفض
  r := public.app_register_device('X3', 'X3', 'android');
  r := public.app_register_device('X4', 'X4', 'android');
  r := public.app_register_device('X5', 'X5', 'android');
  r := public.app_register_device('X6', 'X6', 'android');
  begin
    perform public.app_register_device('X7', 'X7', 'android');
    raise exception 'TEST_FAIL B4: 7th device should be refused';
  exception when others then
    if sqlerrm like 'TEST_FAIL%' then raise; end if;
    if sqlerrm not like 'DEVICE_LIMIT_REACHED%' then raise exception 'TEST_FAIL B4: unexpected %', sqlerrm; end if;
  end;
  v_log := v_log || 'B4 ';

  -- ── عزل المستخدمين: v_uid2 لا يرى أحداث v_uid ──────────────────────────────
  select count(*) into n from public.account_device_events where user_id = v_uid;
  if n <> 0 then raise exception 'TEST_FAIL RLS: user2 sees user1 events (n=%)', n; end if;
  -- ولا يستطيع الكتابة في جدول التدقيق
  begin
    insert into public.account_device_events (user_id, device_id, event_type) values (v_uid2, 'x', 'forged');
    raise exception 'TEST_FAIL RLS: authenticated could write audit table';
  exception when others then
    if sqlerrm like 'TEST_FAIL%' then raise; end if;
  end;
  v_log := v_log || 'RLS ';

  reset role;
  raise exception 'TEST_PASSED_AND_ROLLED_BACK: %', v_log;
end
$test$;
