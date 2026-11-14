-- المرحلة 4 من خطة المزامنة: خادم التعديلات.
--
-- الجهاز يرسل التعديلات الملتقطة (المرحلة 3) دفعات، والخادم يعطي كل تعديل رقماً
-- تسلسلياً لكل حساب داخل قفل صف الحساب، فلا يظهر الرقم 10 قبل حفظ الرقم 9.
-- الأجهزة الأخرى تطلب "ما بعد رقمي" فقط.
--
-- لا يمس هذا الملف أي مسار قائم: النسخة الكاملة (rpc_push_snapshot) والطابور
-- والإشعارات تبقى كما هي. كل حساب مطفأ حتى يُشغَّل بدالة إدارة، فالدالتان ترفضان
-- بـ 'disabled' لكل الحسابات بعد التطبيق.
--
-- الوصول: لا قراءة ولا كتابة مباشرة على جدول التعديلات، بل عبر الدالتين فقط.
-- الحساب من جلسة الدخول (auth.uid())، لا من الطلب.
--
-- رجوع: 20261115_sync_changes.rollback.sql

begin;

-- حالة كل حساب: آخر رقم، ورقم الجيل، والتشغيل.
create table if not exists public.sync_account_state (
  user_id uuid primary key,
  last_seq bigint not null default 0,
  generation integer not null default 0,
  changes_enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.sync_account_state enable row level security;
revoke all on public.sync_account_state from public, anon, authenticated;

create table if not exists public.sync_changes (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  seq bigint not null,
  generation integer not null,
  device_id text not null,
  change_key text not null,
  table_name text not null,
  row_key text not null,
  op text not null check (op in ('U', 'D')),
  row_data jsonb,
  created_at timestamptz not null default now(),
  constraint sync_changes_user_seq_key unique (user_id, seq),
  constraint sync_changes_user_change_key_key unique (user_id, change_key)
);
create index if not exists idx_sync_changes_created_at
  on public.sync_changes (created_at);
alter table public.sync_changes enable row level security;
revoke all on public.sync_changes from public, anon, authenticated;

-- إشارة صغيرة: سطر واحد لكل حساب فيه آخر رقم فقط، يتغير بعد كل دفعة ويُبث
-- لحظياً. لا بيانات محل فيه.
create table if not exists public.sync_change_signals (
  user_id uuid primary key,
  last_seq bigint not null default 0,
  generation integer not null default 0,
  sender_device_id text,
  updated_at timestamptz not null default now()
);
alter table public.sync_change_signals enable row level security;
revoke all on public.sync_change_signals from public, anon, authenticated;
grant select on public.sync_change_signals to authenticated;
drop policy if exists sync_change_signals_own_select on public.sync_change_signals;
create policy sync_change_signals_own_select on public.sync_change_signals
  for select to authenticated using (auth.uid() = user_id);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public' and tablename = 'sync_change_signals'
     ) then
    execute 'alter publication supabase_realtime add table public.sync_change_signals';
  end if;
end $$;

-- إرسال دفعة. كل تعديل: {key, table, row_key, op: U|D, row}.
-- key مفتاح عدم تكرار من الجهاز: إعادة الإرسال لا تُدخل نسخة ثانية.
create or replace function public.rpc_push_changes(
  p_device_id text,
  p_generation integer,
  p_changes jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_state public.sync_account_state%rowtype;
  v_item jsonb;
  v_seq bigint;
  v_existing bigint;
  v_accepted jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;
  if p_device_id is null or length(p_device_id) not between 1 and 128 then
    return jsonb_build_object('ok', false, 'reason', 'bad_device');
  end if;
  if jsonb_typeof(p_changes) is distinct from 'array' then
    return jsonb_build_object('ok', false, 'reason', 'bad_payload');
  end if;
  if jsonb_array_length(p_changes) > 200 then
    return jsonb_build_object('ok', false, 'reason', 'too_many');
  end if;
  if octet_length(p_changes::text) > 4194304 then
    return jsonb_build_object('ok', false, 'reason', 'too_large');
  end if;
  if exists (
    select 1 from public.account_devices d
    where d.user_id = v_uid and d.device_id = p_device_id
      and d.access_status = 'revoked'
  ) then
    return jsonb_build_object('ok', false, 'reason', 'device_revoked');
  end if;

  insert into public.sync_account_state (user_id) values (v_uid)
    on conflict (user_id) do nothing;
  select * into v_state from public.sync_account_state
    where user_id = v_uid for update;

  if not v_state.changes_enabled then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;
  if p_generation is distinct from v_state.generation then
    return jsonb_build_object('ok', false, 'reason', 'generation_mismatch',
                              'generation', v_state.generation);
  end if;

  -- تحقق من الدفعة كلها قبل كتابة أي شيء.
  for v_item in select value from jsonb_array_elements(p_changes) loop
    if jsonb_typeof(v_item) is distinct from 'object'
       or jsonb_typeof(v_item -> 'key') is distinct from 'string'
       or length(v_item ->> 'key') not between 1 and 128
       or not exists (
         select 1 from public.sync_guard_allowed_tables a
         where a.table_name = v_item ->> 'table'
       )
       or coalesce(length(v_item ->> 'row_key'), 0) not between 1 and 200
       or coalesce(v_item ->> 'op', '') not in ('U', 'D')
       or ((v_item ->> 'op') = 'U'
           and jsonb_typeof(v_item -> 'row') is distinct from 'object')
       or octet_length(coalesce(v_item -> 'row', 'null'::jsonb)::text) > 262144
    then
      return jsonb_build_object('ok', false, 'reason', 'bad_change',
                                'key', v_item ->> 'key');
    end if;
  end loop;

  v_seq := v_state.last_seq;
  for v_item in
    select e.value from jsonb_array_elements(p_changes) with ordinality as e
    order by e.ordinality
  loop
    select c.seq into v_existing from public.sync_changes c
      where c.user_id = v_uid and c.change_key = v_item ->> 'key';
    if found then
      v_accepted := v_accepted || jsonb_build_array(jsonb_build_object(
        'key', v_item ->> 'key', 'seq', v_existing, 'duplicate', true));
      continue;
    end if;
    v_seq := v_seq + 1;
    insert into public.sync_changes (
      user_id, seq, generation, device_id, change_key,
      table_name, row_key, op, row_data
    ) values (
      v_uid, v_seq, v_state.generation, p_device_id, v_item ->> 'key',
      v_item ->> 'table', v_item ->> 'row_key', v_item ->> 'op',
      case when v_item ->> 'op' = 'U' then v_item -> 'row' end
    );
    v_accepted := v_accepted || jsonb_build_array(jsonb_build_object(
      'key', v_item ->> 'key', 'seq', v_seq));
  end loop;

  if v_seq > v_state.last_seq then
    update public.sync_account_state
      set last_seq = v_seq, updated_at = now()
      where user_id = v_uid;
    insert into public.sync_change_signals
      (user_id, last_seq, generation, sender_device_id, updated_at)
      values (v_uid, v_seq, v_state.generation, p_device_id, now())
      on conflict (user_id) do update set
        last_seq = excluded.last_seq,
        generation = excluded.generation,
        sender_device_id = excluded.sender_device_id,
        updated_at = excluded.updated_at;
  end if;

  return jsonb_build_object('ok', true, 'last_seq', v_seq,
                            'generation', v_state.generation,
                            'accepted', v_accepted);
end $$;

-- استلام ما بعد رقم الجهاز. snapshot_required: الجهاز يأخذ النسخة الكاملة،
-- لأن الجيل تغيّر (استرجاع) أو لأن ما بعد رقمه حُذف من السجل.
create or replace function public.rpc_pull_changes(
  p_device_id text,
  p_after_seq bigint,
  p_generation integer,
  p_limit integer default 500
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_state public.sync_account_state%rowtype;
  v_min bigint;
  v_limit integer := least(greatest(coalesce(p_limit, 500), 1), 1000);
  v_rows jsonb;
  v_max bigint;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'reason', 'not_authenticated');
  end if;
  if p_after_seq is null or p_after_seq < 0 then
    return jsonb_build_object('ok', false, 'reason', 'bad_cursor');
  end if;
  if exists (
    select 1 from public.account_devices d
    where d.user_id = v_uid and d.device_id = p_device_id
      and d.access_status = 'revoked'
  ) then
    return jsonb_build_object('ok', false, 'reason', 'device_revoked');
  end if;

  select * into v_state from public.sync_account_state where user_id = v_uid;
  if not found or not v_state.changes_enabled then
    return jsonb_build_object('ok', false, 'reason', 'disabled');
  end if;
  if p_generation is distinct from v_state.generation then
    return jsonb_build_object('ok', false, 'reason', 'generation_changed',
                              'generation', v_state.generation,
                              'snapshot_required', true);
  end if;

  select min(c.seq) into v_min from public.sync_changes c
    where c.user_id = v_uid;
  if (v_min is not null and p_after_seq < v_min - 1)
     or (v_min is null and p_after_seq < v_state.last_seq) then
    return jsonb_build_object('ok', false, 'reason', 'too_old',
                              'generation', v_state.generation,
                              'last_seq', v_state.last_seq,
                              'snapshot_required', true);
  end if;

  select
    coalesce(jsonb_agg(jsonb_build_object(
      'seq', s.seq,
      'device_id', s.device_id,
      'table', s.table_name,
      'row_key', s.row_key,
      'op', s.op,
      'row', s.row_data
    ) order by s.seq), '[]'::jsonb),
    max(s.seq)
  into v_rows, v_max
  from (
    select c.seq, c.device_id, c.table_name, c.row_key, c.op, c.row_data
    from public.sync_changes c
    where c.user_id = v_uid and c.seq > p_after_seq
    order by c.seq
    limit v_limit
  ) s;

  return jsonb_build_object(
    'ok', true,
    'generation', v_state.generation,
    'last_seq', v_state.last_seq,
    'changes', v_rows,
    'has_more', coalesce(v_max, p_after_seq) < v_state.last_seq
  );
end $$;

revoke all on function public.rpc_push_changes(text, integer, jsonb)
  from public, anon;
revoke all on function public.rpc_pull_changes(text, bigint, integer, integer)
  from public, anon;
grant execute on function public.rpc_push_changes(text, integer, jsonb)
  to authenticated;
grant execute on function public.rpc_pull_changes(text, bigint, integer, integer)
  to authenticated;

-- الاسترجاع (ops_private.restore_snapshot_from_history) يكتب device_label
-- 'restore:<id>'. هنا يرتفع رقم الجيل، فكل جهاز يترك مؤشره ويأخذ النسخة، وكل
-- تعديل بجيل قديم يُرفض.
create or replace function public.fn_bump_sync_generation_on_restore()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gen integer;
  v_seq bigint;
begin
  insert into public.sync_account_state (user_id, generation)
    values (new.user_id, 1)
    on conflict (user_id) do update set
      generation = public.sync_account_state.generation + 1,
      updated_at = now()
    returning generation, last_seq into v_gen, v_seq;
  insert into public.sync_change_signals
    (user_id, last_seq, generation, sender_device_id, updated_at)
    values (new.user_id, v_seq, v_gen, new.device_label, now())
    on conflict (user_id) do update set
      generation = excluded.generation,
      sender_device_id = excluded.sender_device_id,
      updated_at = excluded.updated_at;
  return null;
end $$;
revoke all on function public.fn_bump_sync_generation_on_restore()
  from public, anon, authenticated;

drop trigger if exists trg_bump_sync_generation_on_restore on public.app_snapshots;
create trigger trg_bump_sync_generation_on_restore
  after update on public.app_snapshots
  for each row
  when (new.device_label like 'restore:%'
        and new.idempotency_key is distinct from old.idempotency_key)
  execute function public.fn_bump_sync_generation_on_restore();

-- إدارة فقط.
create or replace function ops_private.set_sync_changes_enabled(
  p_user_id uuid,
  p_enabled boolean
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v public.sync_account_state%rowtype;
begin
  insert into public.sync_account_state (user_id, changes_enabled)
    values (p_user_id, p_enabled)
    on conflict (user_id) do update set
      changes_enabled = excluded.changes_enabled, updated_at = now()
    returning * into v;
  return jsonb_build_object('user_id', v.user_id, 'enabled', v.changes_enabled,
                            'last_seq', v.last_seq, 'generation', v.generation);
end $$;

-- حذف التعديلات الأقدم من p_days. الجهاز الذي غاب أطول يأخذ النسخة اليومية.
create or replace function ops_private.prune_sync_changes(
  p_days integer default 35,
  p_limit integer default 50000
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_n integer;
begin
  with doomed as (
    select c.id from public.sync_changes c
    where c.created_at < now() - make_interval(days => p_days)
    order by c.id
    limit p_limit
  )
  delete from public.sync_changes c using doomed d where c.id = d.id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

revoke all on function ops_private.set_sync_changes_enabled(uuid, boolean)
  from public, anon, authenticated;
revoke all on function ops_private.prune_sync_changes(integer, integer)
  from public, anon, authenticated;

-- 06:50 بغداد: بعد المهام الليلية الحالية وقبل فتح المحلات.
select cron.schedule(
  'prune-sync-changes',
  '50 3 * * *',
  $cmd$select ops_private.prune_sync_changes(); select ops_private.ping('prune-sync-changes');$cmd$
);

commit;
