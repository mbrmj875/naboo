-- المرحلة 0-د: استرجاع نسخة حساب من الأرشيف (14 نوفمبر 2026).
--
-- دالة للإدارة فقط (تُستدعى يدوياً من محرر SQL أو MCP، لا من التطبيق).
-- تجعل نسخة مؤرشفة هي النسخة الحالية للحساب، مع أجزائها إن كانت مقسّمة.
--
-- ماذا يحدث بعدها (من الكود، cloud_sync_service.dart: _pullLatestSnapshot
-- و_importSnapshot):
--   * تحديث app_snapshots يُبث لحظياً، فتسحب الأجهزة المتصلة النسخة وتدمجها.
--   * الدمج لا يحذف شيئاً من الجهاز: كل سطر بالمفتاح، والأحدث تاريخاً يفوز.
--   * إذن الاسترجاع يُعيد الأسطر الناقصة (جهاز جديد، جهاز مُسح، نسخة خادم
--     فقدت بيانات)، ولا يُلغي تعديلات أو حذفاً أحدث ما زال على جهاز.
--   * أول رفع من جهاز بعد ذلك يصطدم برقم النسخة، فيسحب ويدمج ثم يرفع المجموع.
--
-- الأمان:
--   * النسخة الحالية تُحفظ تلقائياً في الأرشيف قبل الاستبدال
--     (trg_archive_app_snapshot_before_update)، فالاسترجاع نفسه يُرجع بنفس الدالة.
--   * يقفل صف الحساب طوال العملية، فلا يتداخل مع رفع جارٍ.
--   * يرفض: نسخة غير موجودة، نسخة مقسّمة أجزاؤها ناقصة، رقم مخطط مختلف عن
--     النسخة الحالية، أو نسخة هي نفسها الحالية.
--   * المعاينة (الافتراضية) لا تكتب شيئاً.
--
-- الاستخدام:
--   select ops_private.restore_snapshot_from_history(<history_id>);          -- معاينة
--   select ops_private.restore_snapshot_from_history(<history_id>, false);   -- تنفيذ
--
-- الرجوع: 20261114_snapshot_restore.rollback.sql (حذف الدالة؛ لا تُستدعى إلا يدوياً).

create or replace function ops_private.restore_snapshot_from_history(
  p_history_id bigint,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  h public.app_snapshots_history%rowtype;
  cur public.app_snapshots%rowtype;
  v_chunked boolean;
  v_upload text;
  v_need integer;
  v_have integer;
  v_inserted integer := 0;
  v_new_version bigint;
begin
  select * into h from public.app_snapshots_history where id = p_history_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'history_not_found');
  end if;
  if h.payload is null then
    return jsonb_build_object('ok', false, 'reason', 'history_payload_null');
  end if;

  select * into cur from public.app_snapshots where user_id = h.user_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no_current_snapshot');
  end if;
  if cur.schema_version is distinct from h.schema_version then
    return jsonb_build_object('ok', false, 'reason', 'schema_mismatch',
      'current_schema', cur.schema_version, 'history_schema', h.schema_version);
  end if;
  if cur.payload is not distinct from h.payload then
    return jsonb_build_object('ok', false, 'reason', 'already_current');
  end if;

  v_chunked := coalesce(h.payload->>'chunked', '') = 'true';
  v_upload := coalesce(nullif(h.payload->>'upload_id', ''), nullif(h.upload_id, ''),
                       nullif(h.payload->>'sync_id', ''));
  if v_chunked then
    v_need := nullif(h.payload->>'chunk_count', '')::int;
    if v_upload is null or v_need is null then
      return jsonb_build_object('ok', false, 'reason', 'manifest_incomplete');
    end if;
    select count(*) into v_have from ops_private.snapshot_chunks_archive a
     where a.user_id = h.user_id and a.upload_id = v_upload
       and a.chunk_index between 0 and v_need - 1;
    if v_have <> v_need then
      return jsonb_build_object('ok', false, 'reason', 'chunks_missing',
        'need', v_need, 'have', v_have);
    end if;
  end if;

  if p_dry_run then
    return jsonb_build_object('ok', true, 'dry_run', true,
      'chunked', v_chunked, 'chunk_count', coalesce(v_need, 0),
      'history_archived_at', h.archived_at,
      'current_version', cur.content_version);
  end if;

  if v_chunked then
    insert into public.app_snapshot_chunks (user_id, sync_id, upload_id, chunk_index, chunk_data)
    select a.user_id, v_upload, v_upload, a.chunk_index, a.chunk_data
      from ops_private.snapshot_chunks_archive a
     where a.user_id = h.user_id and a.upload_id = v_upload
       and a.chunk_index between 0 and v_need - 1
    on conflict (user_id, sync_id, chunk_index) do nothing;
    get diagnostics v_inserted = row_count;
  end if;

  update public.app_snapshots set
    payload = h.payload,
    schema_version = h.schema_version,
    device_label = 'restore:' || h.id,
    idempotency_key = 'restore-' || h.id || '-' || floor(extract(epoch from clock_timestamp()))::bigint,
    upload_id = case when v_chunked then v_upload else h.upload_id end
  where user_id = h.user_id
  returning content_version into v_new_version;

  return jsonb_build_object('ok', true, 'dry_run', false,
    'chunked', v_chunked, 'chunks_inserted', v_inserted,
    'previous_version', cur.content_version, 'new_version', v_new_version,
    'history_archived_at', h.archived_at);
end;
$$;
revoke all on function ops_private.restore_snapshot_from_history(bigint, boolean) from public, anon, authenticated;
