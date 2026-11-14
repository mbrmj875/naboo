-- المرحلة 0، البند 0.6: حارس يمنع حذف أجزاء اللقطة المنشورة حالياً.
--
-- السبب (cloud_sync_service.dart: _deleteStaleSnapshotChunks): بعد كل رفع ينجح
-- يحذف الجهاز كل أجزاء الحساب التي ليست من رفعته. إن نشر جهاز آخر لقطة أحدث
-- بين رفع الأول وحذفه، أو كان جهاز ثانٍ يرفع أجزاءه في اللحظة نفسها، حُذفت
-- أجزاء اللقطة المنشورة أو التي ستُنشر، فلا يمكن تجميعها على أي جهاز.
--
-- الحارس لا يغيّر التطبيق ولا يحتاج إصداراً. يتجاهل الحذف بصمت (فالتطبيق لا
-- يعتمد على عدد المحذوف) لصفين فقط:
--   1) أجزاء الرفعة المنشورة الآن في app_snapshots لهذا الحساب.
--   2) أجزاء كُتبت في آخر 10 دقائق، فقد تكون رفعة لم تُنشر بعد.
-- ما تبقى منها يحذفه الرفع التالي كالمعتاد.
-- لا يعمل إلا على حذف المستخدم من التطبيق (anon/authenticated). حذف الحساب
-- بالتتابع من auth.users وحذف الخادم يمرّان كما هما.
--
-- الرجوع:
--   drop trigger if exists trg_guard_published_snapshot_chunks on public.app_snapshot_chunks;
--   drop function if exists public.fn_guard_published_snapshot_chunks();

create or replace function public.fn_guard_published_snapshot_chunks()
returns trigger
language plpgsql
-- invoker عمداً: current_user هو دور الحاذف. يقرأ لقطة الحساب نفسه فقط عبر RLS.
security invoker
set search_path = ''
as $$
declare
  old_upload text := coalesce(nullif(old.upload_id, ''), old.sync_id);
begin
  if current_user not in ('anon', 'authenticated') then
    return old;
  end if;

  if old.updated_at is not null
     and old.updated_at > now() - interval '10 minutes' then
    return null;
  end if;

  if exists (
    select 1
      from public.app_snapshots s
     where s.user_id = old.user_id
       and old_upload is not null
       and old_upload in (
         nullif(s.upload_id, ''),
         nullif(s.payload ->> 'upload_id', ''),
         nullif(s.payload ->> 'sync_id', '')
       )
  ) then
    return null;
  end if;

  return old;
end;
$$;

revoke all on function public.fn_guard_published_snapshot_chunks() from public, anon, authenticated;

-- وقت كتابة الجزء من ساعة الخادم لا ساعة الجهاز، حتى تصح نافذة الدقائق العشر.
-- لا شيء يقرأ هذا العمود غير الحارس.
-- الرجوع: drop trigger if exists trg_stamp_snapshot_chunk on public.app_snapshot_chunks;
create or replace function public.fn_stamp_snapshot_chunk()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.fn_stamp_snapshot_chunk() from public, anon, authenticated;

drop trigger if exists trg_stamp_snapshot_chunk on public.app_snapshot_chunks;
create trigger trg_stamp_snapshot_chunk
before insert or update on public.app_snapshot_chunks
for each row execute function public.fn_stamp_snapshot_chunk();

drop trigger if exists trg_guard_published_snapshot_chunks on public.app_snapshot_chunks;
create trigger trg_guard_published_snapshot_chunks
before delete on public.app_snapshot_chunks
for each row execute function public.fn_guard_published_snapshot_chunks();
