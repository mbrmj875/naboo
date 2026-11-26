-- اختبارات 20261125_notifications_phases.sql. تُشغَّل بعد الترحيلين السابقين واختبارهما.
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

select pg_temp.as_admin();
delete from public.notifications;
delete from net.calls;

-- 20. نص الإغلاق يكتبه الخادم، وفرق الصندوق إشعار حرج مستقل
select pg_temp.as_user(:'A');
insert into public.notification_events (user_id, local_tenant_id, event_key, type, payload, occurred_at, device_id)
values (:'A', 1, 'dev1:shift_close:7', 'shift_close',
  '{"shift_id":7,"staff_name":"علي","declared_fils":450000000,"system_fils":455000000,"withdrawn_fils":100000000,"actor_role":"staff"}',
  now(), 'shopA');
select pg_temp.as_admin();
select case when (select title_ar || ' | ' || body_ar from public.notifications where type = 'shift_close')
  = 'علي أغلق الوردية | في الصندوق 450,000 د.ع، والمسحوب 100,000 د.ع' then 'PASS 20a close text' end;
select case when (select priority || ' ' || title_ar from public.notifications where type = 'cash_difference')
  = 'critical فرق في الصندوق: نقص 5,000 د.ع' then 'PASS 20b cash difference critical' end;
select case when (select source_device_id from public.notifications where type = 'shift_close') = 'shopA'
  then 'PASS 20c source device recorded' end;

-- 21. الحدث نفسه من جهازين (أو مرتين) لا يتكرر
select pg_temp.as_user(:'A');
select pg_temp.expect_error($$insert into public.notification_events (user_id, local_tenant_id, event_key, type, payload, occurred_at)
  values ('00000000-0000-0000-0000-00000000000a', 1, 'dev1:shift_close:7', 'shift_close', '{}', now())$$, 'duplicate key');
select pg_temp.as_admin();
select case when (select count(*) from public.notifications where type = 'shift_close') = 1 then 'PASS 21 event dedupe' end;

-- 22. فعل المالك نفسه يُسجَّل ولا يُرسل
select pg_temp.as_user(:'A');
insert into public.notification_events (user_id, local_tenant_id, event_key, type, payload, occurred_at, device_id)
values (:'A', 1, 'dev1:debt:9', 'debt_sale',
  '{"invoice_id":9,"staff_name":"المالك","customer_name":"حسن","total_fils":250000000,"advance_fils":50000000,"actor_role":"owner"}',
  now(), 'phoneA');
select pg_temp.as_admin();
select case when (select status || ' | ' || title_ar from public.notifications where type = 'debt_sale')
  = 'own_action | بيع بالدين لـحسن: 200,000 د.ع' then 'PASS 22 own action logged not sent' end;

-- 23. حد المبلغ
insert into public.notification_preferences (user_id, local_tenant_id, amount_min) values (:'A', 1, 50000)
  on conflict (user_id, local_tenant_id) do update set amount_min = excluded.amount_min;
select pg_temp.as_user(:'A');
insert into public.notification_events (user_id, local_tenant_id, event_key, type, payload, occurred_at, device_id)
values (:'A', 1, 'dev1:ret:3', 'sale_return', '{"invoice_id":3,"amount_fils":10000000,"staff_name":"علي"}', now(), 'shopA');
select pg_temp.as_admin();
select case when (select status from public.notifications where type = 'sale_return') = 'below_min' then 'PASS 23 amount threshold' end;
update public.notification_preferences set amount_min = 0 where user_id = :'A';

-- 24. الدمج: حدث ثان من النوع نفسه خلال دقيقتين يؤجَّل ليُرسل مجمعا
select pg_temp.as_user(:'A');
insert into public.notification_events (user_id, local_tenant_id, event_key, type, payload, occurred_at, device_id)
values (:'A', 1, 'dev1:neg:1', 'negative_stock_sale', '{"invoice_id":1,"product_name":"زيت","lines_count":3,"staff_name":"علي"}', now(), 'shopA'),
       (:'A', 1, 'dev1:neg:2', 'negative_stock_sale', '{"invoice_id":2,"product_name":"فلتر","staff_name":"علي"}', now(), 'shopA');
select pg_temp.as_admin();
select case when (select count(*) from public.notifications where type = 'negative_stock_sale' and deliver_after > now() + interval '90 seconds') = 1
  and (select count(*) from public.notifications where type = 'negative_stock_sale' and deliver_after <= now()) = 1
  then 'PASS 24 merge window' end;
select case when (select body_ar from public.notifications where entity_id is null and type = 'negative_stock_sale' and body_ar like 'زيت%')
  = 'زيت و2 أصناف أخرى، فاتورة #1، البائع علي' then 'PASS 24b negative text' end;
select case when (select audience from public.notifications where type = 'negative_stock_sale' limit 1) = 'perm:inventory.view' then 'PASS 24c perm audience' end;

-- 25. نوع غير معروف أو أرقام تالفة لا تُسقط الإدراج
select pg_temp.as_user(:'A');
insert into public.notification_events (user_id, local_tenant_id, event_key, type, payload, occurred_at)
values (:'A', 1, 'x:1', 'hack', '{"title":"ادفع الآن"}', now()),
       (:'A', 1, 'x:2', 'shift_open', '{"declared_fils":"abc","staff_name":"   سارة\n  "}', now());
select pg_temp.as_admin();
select case when (select count(*) from public.notifications where type = 'hack') = 0
  and (select title_ar || ' | ' || body_ar from public.notifications where type = 'shift_open') = 'سارة فتح الوردية | في الصندوق عند الفتح 0 د.ع'
  then 'PASS 25 unknown type ignored, bad numbers safe' end;

-- 26. الحساب B لا يكتب حدثا باسم A
select pg_temp.as_user(:'B');
select pg_temp.expect_error($$insert into public.notification_events (user_id, local_tenant_id, event_key, type, payload, occurred_at)
  values ('00000000-0000-0000-0000-00000000000a', 1, 'evil', 'shift_open', '{}', now())$$, 'row-level security');
select 'PASS 26 cross-account event blocked';

-- 27. اسم الفرع والإسكات
select pg_temp.as_admin();
update public.notification_preferences set branch_name = 'فرع العشار' where user_id = :'A' and local_tenant_id = 1;
insert into public.notification_preferences (user_id, local_tenant_id, branch_name, muted) values (:'A', 2, 'فرع الجزائر', true);
select pg_temp.as_user(:'A');
insert into public.notification_events (user_id, local_tenant_id, event_key, type, payload, occurred_at)
values (:'A', 1, 'b:1', 'shift_open', '{"staff_name":"علي","declared_fils":1000}', now()),
       (:'A', 2, 'b:2', 'shift_open', '{"staff_name":"زيد","declared_fils":1000}', now());
select pg_temp.as_admin();
select case when (select title_ar from public.notifications where dedupe_key = 'ev:b:1') = 'فرع العشار — علي فتح الوردية'
  and (select status from public.notifications where dedupe_key = 'ev:b:2') = 'branch_muted'
  then 'PASS 27 branch prefix and mute' end;
delete from public.notification_preferences where user_id = :'A' and local_tenant_id = 2;

-- 28. طلب سوق جديد يكتب إشعارا حرجا لصاحب المتجر، والطلب لا يسقط أبدا
insert into public.marketplace_stores values ('11111111-1111-1111-1111-111111111111', :'B');
insert into public.marketplace_orders (order_number, seller_store_id, total_fils) values ('M-55', '11111111-1111-1111-1111-111111111111', 35000000);
insert into public.marketplace_orders (order_number, seller_store_id, total_fils) values ('M-56', '22222222-2222-2222-2222-222222222222', 1000);
select case when (select category || ' ' || priority || ' ' || audience || ' | ' || title_ar from public.notifications where type = 'market_order')
  = 'orders critical perm:sales.pos | طلب جديد من السوق #M-55' then 'PASS 28 market order' end;
insert into public.restaurant_orders (tenant_uuid, channel) values (:'B', 'qr_table'), ('not-a-uuid', 'qr_table'), (:'B', 'pos');
select case when (select count(*) from public.notifications where type = 'restaurant_order') = 1 then 'PASS 28b restaurant order' end;

-- 29. تنبيه الاشتراك: 7 و3 و1 و0 فقط، ولا يتكرر
insert into public.licenses (status, plan, expires_at, assigned_user_id) values
  ('active', 'monthly', now() + interval '3 days', :'A'),
  ('active', 'monthly', now() + interval '5 days', :'B'),
  ('suspended', 'monthly', now() + interval '1 days', :'B');
select public.notify_subscription_reminders();
select public.notify_subscription_reminders();
select case when (select count(*) from public.notifications where type = 'subscription_expiry') = 1
  and (select title_ar from public.notifications where type = 'subscription_expiry') = 'ينتهي اشتراكك بعد 3 أيام'
  then 'PASS 29 subscription reminder' end;

-- 30. الإرسال الجماعي: الفلتر، المعاينة، ومرتان بالمفتاح نفسه لا تكرر
insert into public.profiles values (:'A', 'a@x.iq', 'oil_change'), (:'B', 'b@x.iq', 'retail');
select case when (public.admin_broadcast_preview('{"vertical":"oil_change"}') ->> 'accounts')::int = 1 then 'PASS 30a preview by vertical' end;
select case when (public.admin_broadcast_preview('{"version_below":"2.2.42"}') ->> 'accounts')::int = 1 then 'PASS 30b version filter' end;
select public.admin_broadcast_send('k1', 'naboo_ads', 'announcement', 'عرض', 'خصم', null, '{}', null, 'admin');
select case when public.admin_broadcast_send('k1', 'naboo_ads', 'announcement', 'عرض', 'خصم', null, '{}', null, 'admin') = 0
  and (select count(*) from public.notifications where dedupe_key = 'bc:k1') = 2
  then 'PASS 30c broadcast idempotent' end;
select pg_temp.expect_error($$select public.admin_broadcast_send('k2', 'shop_event', 'x', 't', 'b', null, '{}')$$, 'INVALID_CATEGORY');
select pg_temp.as_user(:'A');
select pg_temp.expect_error($$select public.admin_broadcast_preview('{}')$$, 'permission denied');
select pg_temp.expect_error($$select public.notify_insert('00000000-0000-0000-0000-00000000000a', 1, 'business', 't', 'normal', 'x', 'y', null, null, 'owner', null, 'evil')$$, 'permission denied');
select 'PASS 30d admin and insert helpers are server-only';

-- 31. عدّاد الجاهزية
select pg_temp.as_admin();
select case when (public.admin_notification_readiness() ->> 'accounts')::int = 2 then 'PASS 31 readiness counter' end;

-- 32. الملخص: يحين عند وقته، ولا يتكرر بعد كتابته
select pg_temp.as_admin();
update public.account_devices set access_status = 'active', owner_notify = true where device_id = 'phoneA';
update public.push_devices set enabled = true where device_id = 'phoneA';
update public.notification_preferences
   set summary_time = ((now() at time zone 'Asia/Baghdad') - interval '5 minutes')::time
 where user_id = :'A';
select case when exists (select 1 from public.notify_summary_due_accounts() where user_id = :'A') then 'PASS 32a summary due' end;
select public.notify_write_summary(:'A', 1, to_char((now() at time zone 'Asia/Baghdad')::date, 'YYYY-MM-DD'), 'ملخص اليوم', 'x', '{"profit_fils":5}', true);
select case when not exists (select 1 from public.notify_summary_due_accounts() where user_id = :'A') then 'PASS 32b summary once a day' end;
update public.notification_preferences set disabled_types = '{daily_summary}' where user_id = :'A';
delete from public.notifications where type = 'daily_summary';
select case when not exists (select 1 from public.notify_summary_due_accounts() where user_id = :'A') then 'PASS 32c summary can be turned off' end;

-- 33. الإشعار التجريبي: لجهاز مسجل فقط، ومرة في الدقيقة
select pg_temp.as_user(:'A');
select pg_temp.expect_error($$select public.app_send_test_notification('shopA')$$, 'DEVICE_NOT_REGISTERED');
select public.app_send_test_notification('phoneA');
select public.app_send_test_notification('phoneA');
select pg_temp.as_admin();
select case when (select count(*) from public.notifications where type = 'test' and audience = 'device:phoneA') = 1 then 'PASS 33 test notification' end;

-- 33b. حدث وصل متأخرا يحمل وقت وقوعه
select pg_temp.as_user(:'A');
insert into public.notification_events (user_id, local_tenant_id, event_key, type, payload, occurred_at)
values (:'A', 1, 'late:1', 'shift_open', '{"staff_name":"علي","declared_fils":1000}', '2026-01-10 07:05:00+00');
select pg_temp.as_admin();
select case when (select body_ar from public.notifications where dedupe_key = 'ev:late:1') like '%. وقع 2026-01-10 الساعة 10:05'
  then 'PASS 33b late event keeps real time' end;

-- 34. المهام: الإرسال كل دقيقة بشرط، والاشتراك يوميا، والملخص بشرط
select case when (select schedule from cron.job where jobname = 'notify-dispatch-due') = '* * * * *'
  and (select command from cron.job where jobname = 'notify-dispatch-due') like '%where exists%'
  and (select command from cron.job where jobname = 'notify-daily-summary') like '%where exists%'
  and (select schedule from cron.job where jobname = 'notify-subscription') = '0 6 * * *'
  then 'PASS 34 cron jobs guarded' end;
