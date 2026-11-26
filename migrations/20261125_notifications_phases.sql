-- خطة الإشعارات: باقي المرحلة 1 والمراحل 2 إلى 5 (جانب الخادم).
-- docs/specs/notifications_master_plan_ar.md
--
-- فوق 20261124_notifications_foundation.sql:
--   1. أعمدة إضافية: الفروع (اسم الفرع وإسكاته)، تفاصيل الملخص، وقت الملخص الافتراضي 22:00.
--   2. تحويل حدث الجهاز إلى إشعار بنص عربي يكتبه الخادم (المرحلة 2)، مع الدمج
--      خلال دقيقتين، واستثناء فعل المالك نفسه، وحد المبلغ.
--   3. طلبات السوق والمطعم تكتب في السجل الموحد بدل الدالة القديمة المعطلة (المرحلة 1، البند 5).
--   4. تنبيه الاشتراك قبل 7 و3 أيام ويوم واحد ويوم الانتهاء (المرحلة 3، البند 2). SQL فقط.
--   5. الإرسال الجماعي من لوحة الإدارة ومعاينة عدد المستلمين وسجله (المرحلة 3، البند 1).
--   6. عدّاد الحسابات بلا هاتف مالك للوحة الإدارة (المرحلة 1، 5ج).
--   7. الملخص اليومي: أي الحسابات حان ملخصها (المرحلة 4). الحساب نفسه في دالة notify-daily-summary.
--   8. إشعار تجريبي من شاشة الإعدادات.
--   9. المهام: الإرسال المؤجل كل دقيقة بدل 15 (للدمج)، الاشتراك يوميا، الملخص كل 15 دقيقة.
--      كلها بشرط where exists، فلا تستدعي شيئا إن لم يكن هناك عمل.

-- ─── 1. أعمدة ────────────────────────────────────────────────────────────────
alter table public.notification_preferences
  add column if not exists branch_name text,
  add column if not exists muted boolean not null default false;
alter table public.notification_preferences
  alter column summary_time set default '22:00';

alter table public.notifications
  add column if not exists details jsonb;

-- ─── مساعدات النص ───────────────────────────────────────────────────────────
create or replace function public.notify_fmt_iqd(p_fils numeric)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(round(coalesce(p_fils, 0) / 1000.0), 'FM999,999,999,990') || ' د.ع';
$$;

create or replace function public.notify_clean_name(p_raw text)
returns text
language sql
immutable
set search_path = ''
as $$
  select left(trim(regexp_replace(coalesce(p_raw, ''), '\s+', ' ', 'g')), 40);
$$;

-- رقم من الحمولة؛ أي قيمة غير رقمية تصير null بدل خطأ يُسقط الحدث.
create or replace function public.notify_num(p jsonb, p_key text)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    when (p ->> p_key) ~ '^-?[0-9]+(\.[0-9]+)?$' then (p ->> p_key)::numeric
    else null
  end;
$$;

-- يدرج إشعارا مع اسم الفرع (إن كان للحساب أكثر من فرع) والدمج وحالة الفرع المسكت.
create or replace function public.notify_insert(
  p_user_id uuid,
  p_tenant integer,
  p_category text,
  p_type text,
  p_priority text,
  p_title text,
  p_body text,
  p_route text,
  p_entity text,
  p_audience text,
  p_source_device text,
  p_dedupe text,
  p_status text default 'pending',
  p_details jsonb default null,
  p_merge boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text := p_title;
  v_status text := coalesce(p_status, 'pending');
  v_deliver timestamptz := now();
  v_first timestamptz;
  v_branch text;
  v_muted boolean;
begin
  select nullif(public.notify_clean_name(p.branch_name), ''), p.muted
    into v_branch, v_muted
    from public.notification_preferences p
   where p.user_id = p_user_id and p.local_tenant_id = p_tenant;

  if v_branch is not null
     and (select count(*) from public.notification_preferences q where q.user_id = p_user_id) > 1 then
    v_title := v_branch || ' — ' || v_title;
  end if;

  if coalesce(v_muted, false) and p_category not in ('naboo_account', 'naboo_ads') and v_status = 'pending' then
    v_status := 'branch_muted';
  end if;

  -- الدمج (سادسا): حدث من النوع نفسه خلال دقيقتين يُرسل مع أول حدث بعد دقيقتين في إشعار واحد.
  if p_merge and v_status = 'pending' then
    select min(n.created_at) into v_first
      from public.notifications n
     where n.user_id = p_user_id
       and n.type = p_type
       and n.status in ('pending', 'sent')
       and n.created_at > now() - interval '2 minutes';
    if v_first is not null then
      v_deliver := greatest(now(), v_first + interval '2 minutes');
    end if;
  end if;

  insert into public.notifications
    (user_id, local_tenant_id, category, type, priority, title_ar, body_ar,
     route, entity_id, audience, source_device_id, dedupe_key, status,
     deliver_after, details)
  values
    (p_user_id, coalesce(p_tenant, 1), p_category, p_type, p_priority,
     left(v_title, 120), left(p_body, 400), p_route, p_entity, p_audience,
     p_source_device, p_dedupe, v_status, v_deliver, p_details)
  on conflict (user_id, dedupe_key) do nothing;
end;
$$;

revoke all on function public.notify_insert(uuid, integer, text, text, text, text, text, text, text, text, text, text, text, jsonb, boolean) from public, anon, authenticated;

-- ─── 2. الحدث → الإشعار (المرحلة 2) ────────────────────────────────────────
-- الجهاز يرسل أرقاما ومعرّفات وأسماء قصيرة فقط. الخادم يكتب النص، فلا يرسل جهاز نصا من عنده.
create or replace function public.notification_from_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  p jsonb := coalesce(new.payload, '{}'::jsonb);
  v_staff text := coalesce(nullif(public.notify_clean_name(p ->> 'staff_name'), ''), 'موظف');
  v_cust text := public.notify_clean_name(p ->> 'customer_name');
  v_owner_acted boolean := coalesce(p ->> 'actor_role', '') = 'owner';
  v_amount_min numeric;
  v_amount numeric;
  v_title text;
  v_body text;
  v_cat text := 'shop_event';
  v_prio text := 'high';
  v_route text;
  v_entity text;
  v_aud text := 'owner_phone';
  v_status text := 'pending';
  v_declared numeric;
  v_system numeric;
  v_diff numeric;
  v_lines integer;
  v_total numeric;
  v_advance numeric;
begin
  select coalesce(pr.amount_min, 0) into v_amount_min
    from public.notification_preferences pr
   where pr.user_id = new.user_id and pr.local_tenant_id = new.local_tenant_id;
  v_amount_min := coalesce(v_amount_min, 0);

  case new.type
    when 'shift_open' then
      v_title := v_staff || ' فتح الوردية';
      v_body := 'في الصندوق عند الفتح ' || public.notify_fmt_iqd(public.notify_num(p, 'declared_fils'));
      v_route := 'shift';
      v_entity := p ->> 'shift_id';

    when 'shift_close' then
      v_declared := public.notify_num(p, 'declared_fils');
      v_system := public.notify_num(p, 'system_fils');
      v_title := v_staff || ' أغلق الوردية';
      v_body := 'في الصندوق ' || public.notify_fmt_iqd(v_declared)
        || '، والمسحوب ' || public.notify_fmt_iqd(public.notify_num(p, 'withdrawn_fils'));
      v_route := 'shift';
      v_entity := p ->> 'shift_id';

    when 'sale_return' then
      v_amount := public.notify_num(p, 'amount_fils');
      v_title := 'مرتجع بمبلغ ' || public.notify_fmt_iqd(v_amount);
      v_body := 'سجّله ' || v_staff
        || case when v_cust <> '' then ' للعميل ' || v_cust else '' end
        || case when p ? 'original_invoice_id' then '، من الفاتورة #' || (p ->> 'original_invoice_id') else '' end;
      v_route := 'invoice';
      v_entity := p ->> 'invoice_id';

    when 'negative_stock_sale' then
      v_lines := coalesce(public.notify_num(p, 'lines_count'), 1)::integer;
      v_title := 'بيع أدى إلى رصيد سالب';
      v_body := coalesce(nullif(public.notify_clean_name(p ->> 'product_name'), ''), 'صنف')
        || case when v_lines > 1 then ' و' || (v_lines - 1) || ' أصناف أخرى' else '' end
        || '، فاتورة #' || coalesce(p ->> 'invoice_id', '—') || '، البائع ' || v_staff;
      v_prio := 'critical';
      v_aud := 'perm:inventory.view';
      v_route := 'product';
      v_entity := p ->> 'product_id';

    when 'debt_sale', 'installment_sale' then
      v_total := coalesce(public.notify_num(p, 'total_fils'), 0);
      v_advance := coalesce(public.notify_num(p, 'advance_fils'), 0);
      v_amount := greatest(v_total - v_advance, 0);
      v_title := case when new.type = 'debt_sale' then 'بيع بالدين' else 'بيع بالتقسيط' end
        || case when v_cust <> '' then ' لـ' || v_cust else '' end
        || ': ' || public.notify_fmt_iqd(v_amount);
      v_body := 'الفاتورة #' || coalesce(p ->> 'invoice_id', '—') || '، البائع ' || v_staff
        || case when v_advance > 0 then '، المقدم ' || public.notify_fmt_iqd(v_advance) else '' end;
      v_route := 'invoice';
      v_entity := p ->> 'invoice_id';

    else
      return null; -- نوع غير معروف: يبقى في سجل الأحداث بلا إشعار.
  end case;

  -- حدث تأخر وصوله (جهاز بلا إنترنت): النص يحمل وقت وقوعه الحقيقي (ثامنا).
  if new.occurred_at < now() - interval '10 minutes' then
    v_body := v_body || '. وقع '
      || case when (new.occurred_at at time zone 'Asia/Baghdad')::date < (now() at time zone 'Asia/Baghdad')::date
              then to_char(new.occurred_at at time zone 'Asia/Baghdad', 'YYYY-MM-DD ') else '' end
      || 'الساعة ' || to_char(new.occurred_at at time zone 'Asia/Baghdad', 'HH24:MI');
  end if;

  if v_amount is not null and v_amount_min > 0 and v_amount < v_amount_min * 1000 then
    v_status := 'below_min';
  end if;
  -- المالك الذي نفّذ العملية بيده لا يُشعَر بها (سادسا). تبقى في السجل.
  if v_owner_acted and v_aud = 'owner_phone' then
    v_status := 'own_action';
  end if;

  perform public.notify_insert(
    new.user_id, new.local_tenant_id, v_cat, new.type, v_prio, v_title, v_body,
    v_route, v_entity, v_aud, new.device_id, 'ev:' || new.event_key, v_status, null, true);

  -- فرق الصندوق إشعار حرج مستقل، يُشتق من إغلاق الوردية.
  if new.type = 'shift_close' and v_declared is not null and v_system is not null then
    v_diff := v_declared - v_system;
    if abs(v_diff) >= 1000 then
      perform public.notify_insert(
        new.user_id, new.local_tenant_id, 'shop_event', 'cash_difference', 'critical',
        'فرق في الصندوق: ' || case when v_diff > 0 then 'زيادة ' else 'نقص ' end
          || public.notify_fmt_iqd(abs(v_diff)),
        v_staff || ' أغلق الوردية. حسب النظام ' || public.notify_fmt_iqd(v_system)
          || '، والمعلَن ' || public.notify_fmt_iqd(v_declared),
        'shift', p ->> 'shift_id', 'owner_phone', new.device_id,
        'ev:' || new.event_key || ':diff',
        case when v_owner_acted then 'own_action' else 'pending' end, null, false);
    end if;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_notification_from_event on public.notification_events;
create trigger trg_notification_from_event
  after insert on public.notification_events
  for each row execute function public.notification_from_event();

-- ─── 3. طلبات السوق والمطعم ────────────────────────────────────────────────
-- كانت تستدعي send-notification التي تبحث في جدول المشترين، فلا يصل شيء للتاجر.
create or replace function public.notify_new_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  begin
    select s.tenant_uuid into v_owner
      from public.marketplace_stores s
     where s.id = new.seller_store_id;
    if v_owner is not null then
      perform public.notify_insert(
        v_owner, 1, 'orders', 'market_order', 'critical',
        'طلب جديد من السوق #' || coalesce(new.order_number, ''),
        'المبلغ ' || public.notify_fmt_iqd(new.total_fils)
          || case when coalesce(new.delivery_address, '') <> '' then '، توصيل' else '، استلام من المحل' end,
        'market_orders', new.id::text, 'perm:sales.pos', null,
        'mko:' || new.id::text);
    end if;
  exception when others then
    null; -- الطلب لا يسقط أبدا بسبب الإشعار.
  end;
  return new;
end;
$$;

create or replace function public.notify_new_restaurant_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  if coalesce(new.channel, '') <> 'qr_table' then
    return new;
  end if;
  begin
    if new.tenant_uuid ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_owner := new.tenant_uuid::uuid;
      perform public.notify_insert(
        v_owner, 1, 'orders', 'restaurant_order', 'critical',
        'طلب جديد من طاولة',
        'افتح الطلبات لقبوله.',
        'restaurant_orders', new.id::text, 'perm:sales.pos', null,
        'rso:' || new.id::text);
    end if;
  exception when others then
    null;
  end;
  return new;
end;
$$;

drop trigger if exists trg_notify_new_restaurant_order on public.restaurant_orders;
create trigger trg_notify_new_restaurant_order
  after insert on public.restaurant_orders
  for each row execute function public.notify_new_restaurant_order();

-- ─── 4. تنبيه الاشتراك ─────────────────────────────────────────────────────
create or replace function public.notify_subscription_reminders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (now() at time zone 'Asia/Baghdad')::date;
  r record;
  v_days integer;
  v_count integer := 0;
  v_title text;
begin
  for r in
    select l.id, l.assigned_user_id, l.expires_at,
           (l.expires_at at time zone 'Asia/Baghdad')::date as exp_day
      from public.licenses l
     where l.assigned_user_id is not null
       and lower(coalesce(l.status, '')) = 'active'
       and l.expires_at is not null
       and (l.expires_at at time zone 'Asia/Baghdad')::date between v_today and v_today + 7
  loop
    v_days := r.exp_day - v_today;
    if v_days not in (7, 3, 1, 0) then
      continue;
    end if;
    v_title := case v_days
      when 0 then 'ينتهي اشتراكك اليوم'
      when 1 then 'ينتهي اشتراكك غدا'
      else 'ينتهي اشتراكك بعد ' || v_days || ' أيام'
    end;
    perform public.notify_insert(
      r.assigned_user_id, 1, 'naboo_account', 'subscription_expiry', 'high',
      v_title,
      'جدّد الاشتراك حتى يستمر عمل المحل بلا توقف.',
      'subscription', r.id::text, 'owner', null,
      'sub:' || r.id || ':' || r.exp_day || ':' || v_days);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.notify_subscription_reminders() from public, anon, authenticated;

-- ─── 5. لوحة الإدارة: الإرسال الجماعي ─────────────────────────────────────
create table if not exists public.notification_broadcasts (
  id bigint generated always as identity primary key,
  broadcast_key text not null unique,
  category text not null,
  type text not null,
  title_ar text not null,
  body_ar text not null,
  route text,
  filter jsonb not null default '{}',
  recipients integer not null default 0,
  deliver_after timestamptz not null default now(),
  created_by text,
  created_at timestamptz not null default now()
);
alter table public.notification_broadcasts enable row level security;
-- لا سياسات: لوحة الإدارة تقرأ بمفتاح الخدمة فقط.

-- مقارنة نسخ مثل 2.2.43. غير الرقمي يُعامل كأقدم نسخة.
create or replace function public.notify_version_lt(p_a text, p_b text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(p_a, '') !~ '^[0-9]+(\.[0-9]+)*' then true
    when coalesce(p_b, '') !~ '^[0-9]+(\.[0-9]+)*' then false
    else string_to_array(substring(p_a from '^[0-9]+(?:\.[0-9]+)*'), '.')::int[]
       < string_to_array(substring(p_b from '^[0-9]+(?:\.[0-9]+)*'), '.')::int[]
  end;
$$;

-- الحسابات المطابقة للفلتر. الفلتر:
--   user_id (حساب واحد)، email، vertical (profiles.business_vertical)،
--   subscription: active_paid | lifetime | monthly | expiring_7d | no_license،
--   version_below: نسخة (أي جهاز نشط أقدم منها).
create or replace function public.admin_broadcast_targets(p_filter jsonb)
returns table (user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  with accounts as (
    select distinct d.user_id
      from public.account_devices d
     where lower(coalesce(d.access_status, 'active')) = 'active'
  )
  select a.user_id
    from accounts a
    left join public.profiles pr on pr.id = a.user_id
   where (coalesce(p_filter ->> 'user_id', '') = '' or a.user_id::text = p_filter ->> 'user_id')
     and (coalesce(p_filter ->> 'email', '') = '' or lower(pr.email) = lower(trim(p_filter ->> 'email')))
     and (coalesce(p_filter ->> 'vertical', '') = '' or pr.business_vertical = p_filter ->> 'vertical')
     and (
       coalesce(p_filter ->> 'subscription', '') = ''
       or (p_filter ->> 'subscription' = 'active_paid' and exists (
             select 1 from public.licenses l where l.assigned_user_id = a.user_id and lower(l.status) = 'active'))
       or (p_filter ->> 'subscription' = 'lifetime' and exists (
             select 1 from public.licenses l where l.assigned_user_id = a.user_id and lower(l.status) = 'active' and l.plan = 'lifetime'))
       or (p_filter ->> 'subscription' = 'monthly' and exists (
             select 1 from public.licenses l where l.assigned_user_id = a.user_id and lower(l.status) = 'active' and l.plan = 'monthly'))
       or (p_filter ->> 'subscription' = 'expiring_7d' and exists (
             select 1 from public.licenses l where l.assigned_user_id = a.user_id and lower(l.status) = 'active'
                and l.expires_at between now() and now() + interval '7 days'))
       or (p_filter ->> 'subscription' = 'no_license' and not exists (
             select 1 from public.licenses l where l.assigned_user_id = a.user_id and lower(l.status) = 'active'))
     )
     and (
       coalesce(p_filter ->> 'version_below', '') = ''
       or exists (
         select 1 from public.account_devices d
          where d.user_id = a.user_id
            and lower(coalesce(d.access_status, 'active')) = 'active'
            and public.notify_version_lt(d.app_version, p_filter ->> 'version_below'))
     );
$$;

create or replace function public.admin_broadcast_preview(p_filter jsonb)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'accounts', (select count(*) from public.admin_broadcast_targets(p_filter)),
    'with_owner_phone', (
      select count(*) from public.admin_broadcast_targets(p_filter) t
       where exists (select 1 from public.account_devices d
                      where d.user_id = t.user_id and d.owner_notify))
  );
$$;

-- الإرسال مرتين بالمفتاح نفسه لا يكرر شيئا (broadcast_key فريد + dedupe_key لكل حساب).
create or replace function public.admin_broadcast_send(
  p_broadcast_key text,
  p_category text,
  p_type text,
  p_title text,
  p_body text,
  p_route text,
  p_filter jsonb,
  p_deliver_after timestamptz default null,
  p_created_by text default null
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_key text := trim(coalesce(p_broadcast_key, ''));
  v_when timestamptz := coalesce(p_deliver_after, now());
begin
  if v_key = '' then
    raise exception 'BROADCAST_KEY_REQUIRED' using errcode = 'P0001';
  end if;
  if p_category not in ('naboo_ads', 'naboo_account') then
    raise exception 'INVALID_CATEGORY' using errcode = 'P0001';
  end if;
  if coalesce(trim(p_title), '') = '' or coalesce(trim(p_body), '') = '' then
    raise exception 'TEXT_REQUIRED' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.notification_broadcasts b where b.broadcast_key = v_key) then
    return 0;
  end if;

  insert into public.notifications
    (user_id, local_tenant_id, category, type, priority, title_ar, body_ar,
     route, audience, dedupe_key, deliver_after)
  select t.user_id, 1, p_category, coalesce(nullif(p_type, ''), 'announcement'),
         case when p_category = 'naboo_account' then 'high' else 'low' end,
         left(trim(p_title), 120), left(trim(p_body), 400),
         nullif(p_route, ''), 'owner', 'bc:' || v_key, v_when
    from public.admin_broadcast_targets(coalesce(p_filter, '{}'::jsonb)) t
  on conflict (user_id, dedupe_key) do nothing;
  get diagnostics v_count = row_count;

  insert into public.notification_broadcasts
    (broadcast_key, category, type, title_ar, body_ar, route, filter, recipients, deliver_after, created_by)
  values
    (v_key, p_category, coalesce(nullif(p_type, ''), 'announcement'), trim(p_title), trim(p_body),
     nullif(p_route, ''), coalesce(p_filter, '{}'::jsonb), v_count, v_when, p_created_by);

  return v_count;
end;
$$;

-- ─── 6. عدّاد الجاهزية للوحة الإدارة (5ج) ──────────────────────────────────
create or replace function public.admin_notification_readiness()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with acc as (
    select d.user_id,
           bool_or(d.owner_notify) as has_owner_phone,
           bool_or(lower(coalesce(d.platform, '')) in ('android', 'ios')) as has_phone
      from public.account_devices d
     where lower(coalesce(d.access_status, 'active')) = 'active'
     group by d.user_id
  )
  select jsonb_build_object(
    'accounts', (select count(*) from acc),
    'with_owner_phone', (select count(*) from acc where has_owner_phone),
    'without_owner_phone', (select count(*) from acc where not has_owner_phone),
    'without_any_phone', (select count(*) from acc where not has_phone),
    'registered_push_devices', (select count(*) from public.push_devices where enabled),
    'sent_24h', (select count(*) from public.notifications where status = 'sent' and sent_at > now() - interval '24 hours'),
    'held_24h', (select count(*) from public.notifications where status = 'held_no_owner_phone' and created_at > now() - interval '24 hours'),
    'failed_24h', (select count(*) from public.notifications where status = 'failed' and created_at > now() - interval '24 hours'),
    'gated_24h', (select count(*) from public.notifications where status = 'gated' and created_at > now() - interval '24 hours')
  );
$$;

revoke all on function public.admin_broadcast_targets(jsonb) from public, anon, authenticated;
revoke all on function public.admin_broadcast_preview(jsonb) from public, anon, authenticated;
revoke all on function public.admin_broadcast_send(text, text, text, text, text, text, jsonb, timestamptz, text) from public, anon, authenticated;
revoke all on function public.admin_notification_readiness() from public, anon, authenticated;
grant execute on function public.admin_broadcast_targets(jsonb) to service_role;
grant execute on function public.admin_broadcast_preview(jsonb) to service_role;
grant execute on function public.admin_broadcast_send(text, text, text, text, text, text, jsonb, timestamptz, text) to service_role;
grant execute on function public.admin_notification_readiness() to service_role;

-- ─── 7. الملخص اليومي: من حان ملخصه ─────────────────────────────────────────
-- حساب له هاتف مالك وجهاز مسجل، ووقت ملخصه (بتوقيت بغداد) خلال آخر 30 دقيقة،
-- ولم يُكتب ملخص اليوم بعد، ولم يطفئ النوع. لا يُقرأ أي حساب آخر.
create or replace function public.notify_summary_due_accounts()
returns table (user_id uuid, local_tenant_id integer)
language sql
stable
security definer
set search_path = public
as $$
  with local_now as (
    select (now() at time zone 'Asia/Baghdad') as ts
  ), cand as (
    select distinct pd.user_id, coalesce(pd.local_tenant_id, 1) as local_tenant_id
      from public.push_devices pd
     where pd.enabled
       and exists (select 1 from public.account_devices d
                    where d.user_id = pd.user_id and d.owner_notify)
  )
  select c.user_id, c.local_tenant_id
    from cand c
    left join public.notification_preferences p
      on p.user_id = c.user_id and p.local_tenant_id = c.local_tenant_id
    cross join local_now ln
   where not ('daily_summary' = any (coalesce(p.disabled_types, '{}')))
     and not coalesce(p.muted, false)
     and ln.ts::time >= coalesce(p.summary_time, '22:00'::time)
     and ln.ts::time < coalesce(p.summary_time, '22:00'::time) + interval '30 minutes'
     and not exists (
       select 1 from public.notifications n
        where n.user_id = c.user_id
          and n.dedupe_key = 'summary:' || c.local_tenant_id || ':' || to_char(ln.ts::date, 'YYYY-MM-DD'));
$$;

revoke all on function public.notify_summary_due_accounts() from public, anon, authenticated;
grant execute on function public.notify_summary_due_accounts() to service_role;

-- كتابة الملخص من الدالة (مفتاح الخدمة فقط).
create or replace function public.notify_write_summary(
  p_user_id uuid,
  p_tenant integer,
  p_ymd text,
  p_title text,
  p_body text,
  p_details jsonb,
  p_has_activity boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.notify_insert(
    p_user_id, p_tenant, 'summary', 'daily_summary', 'low', p_title, p_body,
    'daily_summary', p_ymd, 'owner_phone', null, 'summary:' || p_tenant || ':' || p_ymd,
    case when p_has_activity then 'pending' else 'no_activity' end, p_details, false);
end;
$$;

revoke all on function public.notify_write_summary(uuid, integer, text, text, text, jsonb, boolean) from public, anon, authenticated;
grant execute on function public.notify_write_summary(uuid, integer, text, text, text, jsonb, boolean) to service_role;

-- كتابة تنبيهات العمل التسعة من owner-alert-push-cron (مفتاح الخدمة فقط).
create or replace function public.notify_write_business_alert(
  p_user_id uuid,
  p_tenant integer,
  p_type text,
  p_title text,
  p_body text,
  p_route text,
  p_audience text,
  p_dedupe text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.notify_insert(
    p_user_id, p_tenant, 'business', p_type, 'normal', p_title, p_body,
    p_route, null, p_audience, null, p_dedupe, 'pending', null, false);
end;
$$;

revoke all on function public.notify_write_business_alert(uuid, integer, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.notify_write_business_alert(uuid, integer, text, text, text, text, text, text) to service_role;

-- ─── 8. إشعار تجريبي من الإعدادات ───────────────────────────────────────────
-- يمر بكل القواعد (هاتف المالك أولا). واحد في الدقيقة للجهاز.
create or replace function public.app_send_test_notification(p_device_id text, p_local_tenant_id integer default 1)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'tenant_unauthenticated' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.push_devices p
                  where p.user_id = v_uid and p.device_id = p_device_id and p.enabled) then
    raise exception 'DEVICE_NOT_REGISTERED' using errcode = 'P0001';
  end if;
  perform public.notify_insert(
    v_uid, coalesce(p_local_tenant_id, 1), 'business', 'test', 'critical',
    'إشعار تجريبي من نابو',
    'الإشعارات تعمل على هذا الهاتف.',
    'notifications', null, 'device:' || p_device_id, null,
    'test:' || p_device_id || ':' || to_char(now(), 'YYYYMMDDHH24MI'));
end;
$$;

revoke all on function public.app_send_test_notification(text, integer) from public, anon;
grant execute on function public.app_send_test_notification(text, integer) to authenticated;

-- ─── 9. المهام المجدولة ────────────────────────────────────────────────────
-- الإرسال المؤجل كل دقيقة: الدمج يؤجل دقيقتين، والفحص استعلام صغير على فهرس جزئي.
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'notify-dispatch-due';
  perform cron.schedule(
    'notify-dispatch-due',
    '* * * * *',
    $cron$
    select net.http_post(
      url := (select value from public.ops_edge_cron_config where key = 'notify_dispatch_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select value from public.ops_edge_cron_config where key = 'cron_bearer')
      ),
      body := '{"source":"pg_cron"}'::jsonb,
      timeout_milliseconds := 55000
    )
    where exists (
      select 1 from public.notifications
       where status in ('pending', 'quiet_deferred', 'failed')
         and attempts < 5
         and deliver_after <= now()
    );
    $cron$
  );
end $$;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'notify-subscription';
  perform cron.schedule(
    'notify-subscription',
    '0 6 * * *',
    $cron$ select public.notify_subscription_reminders(); $cron$
  );
end $$;

insert into public.ops_edge_cron_config (key, value)
values ('notify_daily_summary_url', 'https://rkofqwcuvbzrnmelvxhz.supabase.co/functions/v1/notify-daily-summary')
on conflict (key) do update set value = excluded.value;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'notify-daily-summary';
  perform cron.schedule(
    'notify-daily-summary',
    '*/15 * * * *',
    $cron$
    select net.http_post(
      url := (select value from public.ops_edge_cron_config where key = 'notify_daily_summary_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select value from public.ops_edge_cron_config where key = 'cron_bearer')
      ),
      body := '{"source":"pg_cron"}'::jsonb,
      timeout_milliseconds := 55000
    )
    where exists (select 1 from public.notify_summary_due_accounts());
    $cron$
  );
end $$;
