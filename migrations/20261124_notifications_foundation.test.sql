-- اختبارات المرحلة 1 (هاتف المالك + الجداول). تُشغَّل على قاعدة محلية بعد الترحيلين.
-- كل اختبار يطبع PASS أو يرمي استثناء.
\set ON_ERROR_STOP 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'

create or replace function pg_temp.as_user(u text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u, false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  execute 'set role authenticated';
end $$;
create or replace function pg_temp.as_admin() returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claim.role', 'service_role', false);
end $$;
create or replace function pg_temp.expect_error(sql text, code text) returns void language plpgsql as $$
begin
  execute sql;
  raise exception 'FAIL: expected % from: %', code, sql;
exception when others then
  if sqlerrm not like '%' || code || '%' then raise exception 'FAIL: expected %, got %', code, sqlerrm; end if;
end $$;

-- 1. لا هاتف مالك في البداية → الحجب
select pg_temp.as_admin();
select case when not public.account_has_owner_phone(:'A') then 'PASS 1 no owner phone at start' end;

-- 2. الكتابة المباشرة على العمود ممنوعة (عامل على جهاز المحل يحاول التعليم دون الدالة)
select pg_temp.as_user(:'A');
select pg_temp.expect_error($$update public.account_devices set owner_notify = true where device_id = 'phoneA'$$, 'OWNER_NOTIFY_RPC_ONLY');
select pg_temp.expect_error($$insert into public.account_devices(user_id, device_id, device_name, owner_notify) values ('00000000-0000-0000-0000-00000000000a','x','x',true)$$, 'OWNER_NOTIFY_RPC_ONLY');
select 'PASS 2 direct write blocked';

-- 3. التحديثات العادية من النسخ القديمة لا تتأثر
update public.account_devices set last_seen_at = now(), device_name = 'realme 2' where device_id = 'phoneA';
select 'PASS 3 old-app updates still work';

-- 4. التعليم عبر الدالة + السجل
select public.app_set_owner_notify_device('phoneA', true);
select pg_temp.as_admin();
select case when public.account_has_owner_phone(:'A') then 'PASS 4a flagged via RPC' end;
select case when (select count(*) from public.account_device_events where event_type = 'owner_notify_on' and device_id = 'phoneA') = 1 then 'PASS 4b event logged' end;

-- 5. عزل الحسابات: B لا يستطيع تعليم جهاز A ولا رؤيته
select pg_temp.as_user(:'B');
select pg_temp.expect_error($$select public.app_set_owner_notify_device('phoneA', false)$$, 'DEVICE_NOT_FOUND');
select case when (select count(*) from public.account_devices where device_id = 'phoneA') = 0 then 'PASS 5 isolation' end;

-- 6. العميل لا يستدعي account_has_owner_phone
select pg_temp.expect_error($$select public.account_has_owner_phone('00000000-0000-0000-0000-00000000000a')$$, 'permission denied');
select 'PASS 6 helper is server-only';

-- 7. تسجيل رمز: جهاز نشط فقط، والرمز نفسه لا يبقى على جهازين
select pg_temp.as_user(:'A');
select public.app_register_push_device('phoneA', 'tok-1', 'android', '2.2.44', 1, 'owner');
select public.app_register_push_device('shopA', 'tok-1', 'windows');
select case when (select count(*) from public.push_devices where fcm_token = 'tok-1') = 1
             and (select device_id from public.push_devices where fcm_token = 'tok-1') = 'shopA'
       then 'PASS 7a token moves, no duplicate' end;
select public.app_register_push_device('phoneA', 'tok-2', 'android', '2.2.44', 1, 'owner');
select pg_temp.expect_error($$select public.app_register_push_device('nope', 'tok-9', 'android')$$, 'DEVICE_NOT_ACTIVE');
select pg_temp.expect_error($$insert into public.push_devices(user_id, device_id, fcm_token, platform) values ('00000000-0000-0000-0000-00000000000a','z','t','android')$$, 'row-level security');
select 'PASS 7b only via RPC, active device';

-- 8. فصل الجهاز: تسقط العلامة ويتوقف الإرسال
select pg_temp.as_admin();
update public.account_devices set access_status = 'revoked' where device_id = 'phoneA';
select case when not public.account_has_owner_phone(:'A')
             and not (select enabled from public.push_devices where device_id = 'phoneA')
       then 'PASS 8 revoke clears flag and disables push' end;
select pg_temp.as_user(:'A');
select pg_temp.expect_error($$select public.app_set_owner_notify_device('phoneA', true)$$, 'DEVICE_REVOKED');
select 'PASS 8b revoked device cannot be flagged';

-- 9. السجل: العميل يقرأ صفوفه فقط ولا يكتب
select pg_temp.as_admin();
insert into public.notifications(user_id, category, type, title_ar, body_ar, dedupe_key)
values (:'A', 'business', 'retail_stock_shortage', 'نواقص', '3 أصناف', 'a-1'),
       (:'B', 'business', 'retail_stock_shortage', 'نواقص', '1 صنف', 'b-1');
select case when (select count(*) from net.calls where url like '%notify-dispatch%') = 1
             and (select jsonb_array_length(body->'ids') from net.calls order by id desc limit 1) = 2
       then 'PASS 9a one dispatch call per statement' end;
select pg_temp.as_user(:'A');
select case when (select count(*) from public.notifications) = 1 then 'PASS 9b reads own only' end;
select pg_temp.expect_error($$insert into public.notifications(user_id, category, type, title_ar, body_ar, dedupe_key) values ('00000000-0000-0000-0000-00000000000a','business','x','x','x','z')$$, 'row-level security');
select public.app_mark_notifications_read(array(select id from public.notifications));
select pg_temp.as_admin();
select case when (select count(*) from public.notifications where read_at is not null) = 1 then 'PASS 9c mark read own only' end;

-- 10. التكرار نفسه لا يُدرج مرتين
select pg_temp.expect_error($$insert into public.notifications(user_id, category, type, title_ar, body_ar, dedupe_key) values ('00000000-0000-0000-0000-00000000000a','business','x','x','x','a-1')$$, 'duplicate key');
select 'PASS 10 dedupe';

-- 11. صف مؤجل لا يستدعي الإرسال
select count(*) as calls_before from net.calls \gset
insert into public.notifications(user_id, category, type, title_ar, body_ar, dedupe_key, deliver_after)
values (:'A', 'business', 'x', 'x', 'x', 'later-1', now() + interval '1 hour');
select case when (select count(*) from net.calls) = :calls_before then 'PASS 11 deferred row not kicked' end;

-- 12. التفضيلات: كل حساب لنفسه
select pg_temp.as_user(:'A');
insert into public.notification_preferences(user_id) values (:'A');
select pg_temp.expect_error($$insert into public.notification_preferences(user_id) values ('00000000-0000-0000-0000-00000000000b')$$, 'row-level security');
select case when (select amount_min from public.notification_preferences) = 0
             and (select quiet_start from public.notification_preferences) = '23:00'
       then 'PASS 12 prefs own + defaults (no amount threshold, 23:00-07:00)' end;
