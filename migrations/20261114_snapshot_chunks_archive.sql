-- المرحلة 0-أ: أرشيف أجزاء النسخ المقسّمة (14 نوفمبر 2026).
--
-- المشكلة: المحلات الكبيرة ترفع نسختها مقسّمة إلى أجزاء في app_snapshot_chunks.
-- بعد كل رفع يحذف التطبيق أجزاء كل الرفعات السابقة (_deleteStaleSnapshotChunks).
-- صف الأرشيف في app_snapshots_history يبقى، لكنه فهرس بلا أجزاء، فلا يُسترجع.
-- القياس (13 نوفمبر): 728 من 740 نسخة مقسّمة مؤرشفة بلا أجزاء.
--
-- الحل: مشغّل بعد الحذف ينسخ الأجزاء المحذوفة إلى ops_private.snapshot_chunks_archive.
-- لا يغيّر الرفع ولا السحب ولا التطبيق، ويعمل مع كل الإصدارات.
--   * يعمل بعد الحذف الفعلي فقط، فما يمنعه حارس الأجزاء المنشورة لا يُنسخ.
--   * ينسخ فقط أجزاء رفعة لها صف في app_snapshots_history. رفعة لم تُنشر لا تُحفظ.
--   * يتجاهل حذف الخادم وحذف الحساب (كالحارس)، فحذف الحساب لا يتعطل.
--   * إن فشل النسخ لأي سبب يكمل الحذف، فالرفع لا يتأثر أبداً.
--
-- التنظيف الليلي يبقي: كل ما أُرشف في آخر 48 ساعة، وأجزاء آخر نسخة من كل يوم
-- (بتوقيت بغداد) ما دام صفها في الأرشيف. الأرشيف نفسه يُحذف بعد 30 يوماً بمهمته
-- الحالية، فتلحقه أجزاؤه.
--
-- الرجوع: 20261114_snapshot_chunks_archive.rollback.sql

create schema if not exists ops_private;
revoke all on schema ops_private from public, anon, authenticated;

create table if not exists ops_private.snapshot_chunks_archive (
  user_id uuid not null references auth.users(id) on delete cascade,
  upload_id text not null,
  chunk_index integer not null,
  chunk_data text not null,
  chunk_updated_at timestamptz,
  archived_at timestamptz not null default now(),
  primary key (user_id, upload_id, chunk_index)
);
revoke all on ops_private.snapshot_chunks_archive from public, anon, authenticated;

create or replace function ops_private.fn_archive_deleted_snapshot_chunk()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_upload text := coalesce(nullif(old.upload_id, ''), old.sync_id);
begin
  -- دور الطلب من الجلسة، لأن current_user هنا مالك الدالة.
  if coalesce(auth.role(), '') not in ('anon', 'authenticated') then
    return null;
  end if;
  if v_upload is null or old.chunk_data is null then
    return null;
  end if;

  begin
    if exists (
      select 1 from public.app_snapshots_history h
       where h.user_id = old.user_id and h.upload_id = v_upload
    ) then
      insert into ops_private.snapshot_chunks_archive
        (user_id, upload_id, chunk_index, chunk_data, chunk_updated_at)
      values (old.user_id, v_upload, old.chunk_index, old.chunk_data, old.updated_at)
      on conflict (user_id, upload_id, chunk_index) do nothing;
    end if;
  exception when others then
    -- الأرشفة لا تُفشل حذف التطبيق ولا رفعه أبداً.
    null;
  end;
  return null;
end;
$$;
revoke all on function ops_private.fn_archive_deleted_snapshot_chunk() from public, anon, authenticated;

drop trigger if exists trg_archive_deleted_snapshot_chunk on public.app_snapshot_chunks;
create trigger trg_archive_deleted_snapshot_chunk
after delete on public.app_snapshot_chunks
for each row execute function ops_private.fn_archive_deleted_snapshot_chunk();

-- التنظيف: يحذف من جدول الأرشيف الجديد فقط، ولا يمس أي جدول آخر.
create or replace function ops_private.prune_snapshot_chunks_archive()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  with keep as (
    select distinct on (h.user_id, (h.archived_at at time zone 'Asia/Baghdad')::date)
           h.user_id, h.upload_id
      from public.app_snapshots_history h
     order by h.user_id, (h.archived_at at time zone 'Asia/Baghdad')::date,
              h.archived_at desc, h.id desc
  )
  delete from ops_private.snapshot_chunks_archive a
   where a.archived_at < now() - interval '48 hours'
     and not exists (
       select 1 from keep k
        where k.user_id = a.user_id and k.upload_id = a.upload_id
     );
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;
revoke all on function ops_private.prune_snapshot_chunks_archive() from public, anon, authenticated;

-- هل نسخة مؤرشفة قابلة للاسترجاع؟ للفحص اليدوي والمراقبة.
create or replace function ops_private.snapshot_history_restorable(p_history_id bigint)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select case
    when coalesce(h.payload->>'chunked', '') <> 'true' then true
    else (
      select count(*) from ops_private.snapshot_chunks_archive a
       where a.user_id = h.user_id and a.upload_id = h.upload_id
    ) = nullif(h.payload->>'chunk_count', '')::int
  end
  from public.app_snapshots_history h
  where h.id = p_history_id;
$$;
revoke all on function ops_private.snapshot_history_restorable(bigint) from public, anon, authenticated;

-- 06:45 بتوقيت بغداد، بعد تنظيف أرشيف النسخ (06:35) وقبل فتح المحلات.
select cron.schedule(
  'prune-snapshot-chunks-archive', '45 3 * * *',
  'select ops_private.prune_snapshot_chunks_archive();' || chr(10) ||
  'select ops_private.ping(''prune-snapshot-chunks-archive'');'
);
