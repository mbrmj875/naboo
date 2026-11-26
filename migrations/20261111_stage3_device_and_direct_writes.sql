-- المرحلة 3، البند 3.2: حماية صف الجهاز ومنع الكتابة المباشرة على جداول المزامنة.
-- يعتمد على جدولي sync_guard_config وsync_guard_violations من 20261111_stage3_sync_allowlist.sql،
-- فيُطبَّق بعده. يبدأ بالتسجيل فقط مثله.
--
-- ما وُجد عند الدراسة (2026-11-11):
-- - التطبيق يكتب app_snapshots عبر rpc_push_snapshot فقط منذ v2.2.36 (520a7f1).
--   سجل 24 ساعة: لا POST ولا PATCH مباشر على الجدول. لكن 30 جهازاً نشطاً بلا app_version،
--   فلا نعرف يقيناً أن لا نسخة أقدم تكتب مباشرة. لذلك نسجّل أولاً ثم نسحب الصلاحية.
-- - device_uuid_migrator.dart يكتب account_devices مباشرة (إلغاء الصف القديم، وupsert
--   صف جديد بحالة active). الـ upsert يتخطى حد الأجهزة الذي تفرضه app_register_device.
--   الكود يلتقط أي خطأ ويعيد المحاولة لاحقاً، فالرفض لا يكسر التشغيل.
-- - anon وauthenticated يملكان TRUNCATE وTRIGGER وREFERENCES على الجداول الثلاثة.
--   TRUNCATE لا يمر على RLS. لا يصل إليه أحد عبر REST اليوم، لكن لا حاجة له إطلاقاً.
--
-- الرجوع:
--   drop trigger if exists trg_guard_direct_snapshot_write on public.app_snapshots;
--   drop function if exists public.fn_guard_direct_snapshot_write();
--   drop trigger if exists trg_guard_device_direct_insert on public.account_devices;
--   drop function if exists public.fn_guard_device_direct_insert();
--   أعد rpc_push_snapshot من النسخة الاحتياطية (الفرق الوحيد سطر set_config).
--   grant truncate, trigger, references on public.app_snapshots, public.app_snapshot_chunks, public.account_devices to anon, authenticated;
--   grant all on public.app_snapshots, public.app_snapshot_chunks, public.account_devices to anon;

-- 1) صلاحيات لا يحتاجها أحد.
revoke truncate, trigger, references on public.app_snapshots, public.app_snapshot_chunks, public.account_devices
  from anon, authenticated;
-- anon بلا هوية، وRLS يرفضه أصلاً (auth.uid() = user_id). السحب يغلق الباب مرتين.
revoke all on public.app_snapshots, public.app_snapshot_chunks, public.account_devices from anon;

-- 2) rpc_push_snapshot تعلن أنها المصدر، ليميّز الحارس الكتابة المباشرة.
create or replace function public.rpc_push_snapshot(
  p_expected_version bigint, p_payload jsonb, p_schema_version integer,
  p_device_label text, p_idempotency_key text, p_upload_id text default null::text)
returns jsonb
language plpgsql
as $function$
DECLARE
  v_row public.app_snapshots%ROWTYPE;
BEGIN
  PERFORM set_config('app.snapshot_source', 'rpc_push_snapshot', true);

  SELECT * INTO v_row FROM public.app_snapshots
    WHERE user_id = auth.uid() FOR UPDATE;

  IF NOT FOUND THEN
    IF p_expected_version <> 0 THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'not_found',
                                'current_version', 0);
    END IF;
    INSERT INTO public.app_snapshots
      (user_id, payload, schema_version, device_label, idempotency_key, upload_id)
    VALUES (auth.uid(), p_payload, p_schema_version, p_device_label,
            p_idempotency_key, p_upload_id)
    RETURNING content_version, updated_at INTO v_row.content_version, v_row.updated_at;
    RETURN jsonb_build_object('ok', true, 'new_version', v_row.content_version,
                              'updated_at', v_row.updated_at);
  END IF;

  -- Idempotent retry of the SAME push (network retry): report success, no rewrite
  IF v_row.idempotency_key IS NOT DISTINCT FROM p_idempotency_key THEN
    RETURN jsonb_build_object('ok', true, 'new_version', v_row.content_version,
                              'updated_at', v_row.updated_at, 'idempotent', true);
  END IF;

  IF v_row.content_version <> p_expected_version THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'version_conflict',
                              'current_version', v_row.content_version,
                              'updated_at', v_row.updated_at);
  END IF;

  UPDATE public.app_snapshots SET
    payload = p_payload,
    schema_version = p_schema_version,
    device_label = p_device_label,
    idempotency_key = p_idempotency_key,
    upload_id = p_upload_id
  WHERE user_id = auth.uid();   -- trigger bumps version + updated_at

  SELECT content_version, updated_at INTO v_row.content_version, v_row.updated_at
    FROM public.app_snapshots WHERE user_id = auth.uid();
  RETURN jsonb_build_object('ok', true, 'new_version', v_row.content_version,
                            'updated_at', v_row.updated_at);
END $function$;

-- 3) الكتابة المباشرة على app_snapshots من التطبيق: تُسجَّل، وتُرفض في وضع enforce.
--    الخادم ولوحة الإدارة (service_role، أو بلا هوية) يمرّان.
create or replace function public.fn_guard_direct_snapshot_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- داخل security definer يكون current_user هو المالك، فنقرأ دور الطلب من JWT.
  if coalesce(auth.role(), '') not in ('anon', 'authenticated') then
    return coalesce(new, old);
  end if;
  if coalesce(current_setting('app.snapshot_source', true), '') = 'rpc_push_snapshot' then
    return coalesce(new, old);
  end if;
  if public.sync_guard_log('direct_snapshot_write', jsonb_build_object(
       'op', tg_op,
       'device_label', case when tg_op = 'DELETE' then old.device_label else new.device_label end)) then
    raise exception 'sync_guard: write app_snapshots through rpc_push_snapshot' using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function public.fn_guard_direct_snapshot_write() from public, anon, authenticated;

drop trigger if exists trg_guard_direct_snapshot_write on public.app_snapshots;
create trigger trg_guard_direct_snapshot_write
  before insert or update or delete on public.app_snapshots
  for each row execute function public.fn_guard_direct_snapshot_write();

-- 4) صف جهاز جديد يُكتب مباشرة (لا عبر app_register_device) فوق حد الخطة.
create or replace function public.fn_guard_device_direct_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max int;
  v_active int;
begin
  if coalesce(auth.role(), '') not in ('anon', 'authenticated') or auth.uid() is null then
    return new;
  end if;
  if coalesce(current_setting('app.device_source', true), '') like 'rpc:%' then
    return new;
  end if;
  if lower(coalesce(new.access_status, 'active')) = 'revoked' then
    return new;
  end if;
  -- upsert لجهاز معروف يمر هنا أيضاً قبل on conflict؛ ليس جهازاً جديداً.
  if exists (select 1 from public.account_devices d
              where d.user_id = new.user_id and d.device_id = new.device_id) then
    return new;
  end if;

  v_max := coalesce(public.app_user_max_devices(), 0);
  if v_max = 0 then return new; end if;
  select count(*)::int into v_active
    from public.account_devices d
   where d.user_id = new.user_id
     and lower(coalesce(d.access_status, 'active')) <> 'revoked';
  if v_active >= v_max then
    if public.sync_guard_log('device_insert_over_limit', jsonb_build_object(
         'active', v_active, 'max', v_max, 'platform', new.platform)) then
      raise exception 'DEVICE_LIMIT_REACHED: active=% max=%', v_active, v_max using errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.fn_guard_device_direct_insert() from public, anon, authenticated;

drop trigger if exists trg_guard_device_direct_insert on public.account_devices;
create trigger trg_guard_device_direct_insert
  before insert on public.account_devices
  for each row execute function public.fn_guard_device_direct_insert();
