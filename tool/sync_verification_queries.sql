-- Sync verification queries for Naboo
-- Run in Supabase SQL Editor.
--
-- HOW TO USE:
-- 1) Replace target_email with the Google account used in app login.
-- 2) Adjust plan_device_limit if needed (basic=2, pro=3, unlimited can be high like 9999).
-- 3) Run sections one by one.

-- ============================================================================
-- 0) INPUTS
-- ============================================================================
with vars as (
  select
    'mbrmjbaqer@gmail.com'::text as target_email,
    2::int as plan_device_limit
)
select * from vars;

-- ============================================================================
-- 1) Resolve target user_id from auth.users by email
-- ============================================================================
with vars as (
  select 'mbrmjbaqer@gmail.com'::text as target_email
)
select
  u.id as user_id,
  u.email,
  u.created_at,
  u.last_sign_in_at
from auth.users u
join vars v on lower(u.email) = lower(v.target_email)
order by u.created_at desc
limit 1;

-- ============================================================================
-- 2) Snapshot health (latest sync row)
-- ============================================================================
with target_user as (
  select u.id as user_id
  from auth.users u
  where lower(u.email) = lower('mbrmjbaqer@gmail.com')
  limit 1
)
select
  s.user_id,
  s.updated_at,
  s.device_label,
  s.schema_version,
  (s.payload->>'chunked')::text as chunked,
  s.payload->>'sync_id' as sync_id,
  coalesce((s.payload->>'chunk_count')::int, 0) as chunk_count,
  s.payload->>'tableCount' as changed_table_count,
  s.payload->'changedTables' as changed_tables
from public.app_snapshots s
join target_user t on t.user_id = s.user_id;

-- ============================================================================
-- 3) Chunk integrity check (if chunked=true)
-- ============================================================================
with target_user as (
  select u.id as user_id
  from auth.users u
  where lower(u.email) = lower('mbrmjbaqer@gmail.com')
  limit 1
),
latest as (
  select
    s.user_id,
    s.payload->>'sync_id' as sync_id,
    coalesce((s.payload->>'chunk_count')::int, 0) as expected_chunks
  from public.app_snapshots s
  join target_user t on t.user_id = s.user_id
)
select
  l.user_id,
  l.sync_id,
  l.expected_chunks,
  count(c.*)::int as actual_chunks,
  sum(char_length(c.chunk_data))::bigint as total_chunk_chars,
  case when count(c.*)::int = l.expected_chunks then 'OK' else 'MISMATCH' end as status
from latest l
left join public.app_snapshot_chunks c
  on c.user_id = l.user_id
 and c.sync_id = l.sync_id
group by l.user_id, l.sync_id, l.expected_chunks;

-- ============================================================================
-- 4) Registered devices + limit check
-- ============================================================================
with vars as (
  select
    'mbrmjbaqer@gmail.com'::text as target_email,
    2::int as plan_device_limit
),
target_user as (
  select u.id as user_id, v.plan_device_limit
  from auth.users u
  join vars v on lower(u.email) = lower(v.target_email)
  limit 1
)
select
  d.user_id,
  d.device_name,
  d.platform,
  d.device_id,
  d.created_at,
  d.last_seen_at
from public.account_devices d
join target_user t on t.user_id = d.user_id
order by d.last_seen_at desc;

with vars as (
  select
    'mbrmjbaqer@gmail.com'::text as target_email,
    2::int as plan_device_limit
),
target_user as (
  select u.id as user_id, v.plan_device_limit
  from auth.users u
  join vars v on lower(u.email) = lower(v.target_email)
  limit 1
)
select
  t.user_id,
  count(d.*)::int as registered_devices,
  t.plan_device_limit,
  case
    when count(d.*)::int > t.plan_device_limit then 'OVER_LIMIT'
    else 'WITHIN_LIMIT'
  end as device_limit_status
from target_user t
left join public.account_devices d on d.user_id = t.user_id
group by t.user_id, t.plan_device_limit;

-- ============================================================================
-- 5) Server-side summary in one row
--    (last sync + chunks + devices + recent activity window)
-- ============================================================================
with vars as (
  select
    'mbrmjbaqer@gmail.com'::text as target_email,
    2::int as plan_device_limit
),
target_user as (
  select u.id as user_id, v.plan_device_limit
  from auth.users u
  join vars v on lower(u.email) = lower(v.target_email)
  limit 1
),
snap as (
  select s.*
  from public.app_snapshots s
  join target_user t on t.user_id = s.user_id
),
chunks as (
  select
    count(c.*)::int as chunk_rows,
    sum(char_length(c.chunk_data))::bigint as chunk_chars
  from public.app_snapshot_chunks c
  join snap s on s.user_id = c.user_id and (s.payload->>'sync_id') = c.sync_id
),
devices as (
  select
    count(d.*)::int as device_count,
    max(d.last_seen_at) as last_seen_any_device
  from public.account_devices d
  join target_user t on t.user_id = d.user_id
)
select
  t.user_id,
  s.updated_at as last_sync_at,
  s.device_label as last_sync_device_label,
  s.schema_version,
  coalesce((s.payload->>'chunked')::text, 'false') as chunked,
  coalesce((s.payload->>'chunk_count')::int, 0) as expected_chunk_count,
  coalesce(ch.chunk_rows, 0) as actual_chunk_rows,
  coalesce(ch.chunk_chars, 0) as total_chunk_chars,
  coalesce(dev.device_count, 0) as registered_devices,
  t.plan_device_limit,
  case
    when coalesce(dev.device_count, 0) > t.plan_device_limit then 'OVER_LIMIT'
    else 'WITHIN_LIMIT'
  end as device_limit_status,
  dev.last_seen_any_device
from target_user t
left join snap s on true
left join chunks ch on true
left join devices dev on true;

-- ============================================================================
-- 6) Snapshot payload quick visibility (debug)
--    Useful to verify that products/customers/invoices keys exist in payload.
-- ============================================================================
with target_user as (
  select u.id as user_id
  from auth.users u
  where lower(u.email) = lower('mbrmjbaqer@gmail.com')
  limit 1
)
select
  s.updated_at,
  jsonb_object_keys(s.payload->'tables') as table_name
from public.app_snapshots s
join target_user t on t.user_id = s.user_id
order by s.updated_at desc;

-- ============================================================================
-- NOTES:
-- - The backend stores the latest sync snapshot per user (one row in app_snapshots).
-- - "exact A vs B row-count comparison at same timestamp" is not directly possible
--   server-side with current schema because latest snapshot is single-row by user.
-- - Device-level consistency is validated indirectly through:
--   (1) changed tables in latest payload, (2) account_devices last_seen_at,
--   (3) manual in-app count checks on each device after sync.
