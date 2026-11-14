-- المرحلة 0-ب: أرشيف النسخ بنسخة واحدة لكل يوم (14 نوفمبر 2026).
--
-- المشكلة: app_snapshots_history يحفظ النسخة القديمة عند كل رفع، حوالي 32 مرة
-- في اليوم لكل محل نشط. القياس (14 نوفمبر 02:30): 3270 نسخة، 1063 MB.
-- لا يقرأ الأرشيف أي شيء في التطبيق أو لوحة الإدارة أو دوال الحافة؛ يقرأه فقط
-- مشغّل الأرشفة ودوال ops_private الثلاث من المرحلة 0-أ.
--
-- القاعدة: يبقى كل ما أُرشف في آخر 48 ساعة، وآخر نسخة من كل يوم بتوقيت بغداد
-- لكل حساب. هي نفس قاعدة أرشيف الأجزاء (prune_snapshot_chunks_archive)، فتبقى
-- أجزاء كل نسخة محفوظة مع فهرسها. حد الثلاثين يوماً الحالي لا يتغير.
--
-- أول تشغيل يحذف حوالي 2989 نسخة ويبقي 281، ولكل حساب نسخة لكل يوم.
-- المحذوف لا يعود من داخل القاعدة؛ يبقى فقط في نسخ Supabase اليومية لمدتها.
-- النسخة الحالية في app_snapshots لا تُمس، ولا أجزاؤها.
--
-- تطبيق هذا الملف لا يحذف شيئاً. الحذف يبدأ بالمهمة الليلية 05:00 بغداد،
-- أو بالاستدعاء اليدوي: select ops_private.thin_snapshot_history(false);
-- للمعاينة دون حذف:      select ops_private.thin_snapshot_history(true);
--
-- الرجوع: 20261114_snapshot_history_daily.rollback.sql (يوقف المهمة فقط).

create or replace function ops_private.thin_snapshot_history(
  p_dry_run boolean default true,
  p_limit integer default 5000
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  with ranked as (
    select h.id, h.archived_at,
           row_number() over (
             partition by h.user_id, (h.archived_at at time zone 'Asia/Baghdad')::date
             order by h.archived_at desc, h.id desc
           ) as rn
      from public.app_snapshots_history h
  ),
  doomed as (
    select r.id from ranked r
     where r.rn > 1
       and r.archived_at < now() - interval '48 hours'
     order by r.id
     limit greatest(p_limit, 0)
  )
  select count(*) into v_count from doomed;

  if p_dry_run or v_count = 0 then
    return v_count;
  end if;

  with ranked as (
    select h.id, h.archived_at,
           row_number() over (
             partition by h.user_id, (h.archived_at at time zone 'Asia/Baghdad')::date
             order by h.archived_at desc, h.id desc
           ) as rn
      from public.app_snapshots_history h
  )
  delete from public.app_snapshots_history d
   using (
     select r.id from ranked r
      where r.rn > 1
        and r.archived_at < now() - interval '48 hours'
      order by r.id
      limit greatest(p_limit, 0)
   ) x
   where d.id = x.id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function ops_private.thin_snapshot_history(boolean, integer) from public, anon, authenticated;

-- 05:00 بتوقيت بغداد، قبل تنظيف الأرشيف (06:35) وتنظيف أرشيف الأجزاء (06:45)،
-- فيحذف تنظيف الأجزاء ما صار بلا فهرس في نفس الليلة.
select cron.schedule(
  'thin-snapshot-history', '0 2 * * *',
  'select ops_private.thin_snapshot_history(false);' || chr(10) ||
  'select ops_private.ping(''thin-snapshot-history'');'
);
