-- البند 5.1: الحارس يفحص اللقطة المقسّمة أيضاً.
--
-- اللقطة الأكبر من 350 كيلوبايت تُرفع مضغوطة على أجزاء، وغلافها 224 بايت، فلم
-- يكن الحارس يرى جداولها ولا حجمها.
-- - الحجم: مجموع أجزاء الرفع نفسه في app_snapshot_chunks (يعمل مع الإصدارات
--   القديمة أيضاً)، أو raw_bytes من الغلاف، أيهما أكبر.
-- - الجداول: table_names من الغلاف. الإصدارات القديمة لا تكتبه فلا يُفحص.
-- قيمة غير متوقعة في الغلاف لا ترفع خطأ، فلا يتوقف رفع بسبب الحارس نفسه.
--
-- الرجوع: إعادة تعريف الدالة السابقة (migrations/20261111_stage3_sync_allowlist.sql).

create or replace function public.fn_guard_snapshot_payload()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_cfg public.sync_guard_config%rowtype;
  v_size bigint;
  v_chunks bigint;
  v_upload text;
  v_names jsonb;
  v_unknown text[];
begin
  if new.payload is null then return new; end if;
  if tg_op = 'UPDATE' and new.payload is not distinct from old.payload then return new; end if;
  select * into v_cfg from public.sync_guard_config where id;
  if not found then return new; end if;

  v_size := pg_column_size(new.payload);
  if new.payload->>'chunked' = 'true' then
    if jsonb_typeof(new.payload->'raw_bytes') = 'number' then
      v_size := greatest(v_size, floor((new.payload->>'raw_bytes')::numeric)::bigint);
    end if;
    v_upload := coalesce(nullif(new.payload->>'upload_id', ''), nullif(new.payload->>'sync_id', ''));
    if v_upload is not null then
      select coalesce(sum(length(c.chunk_data)), 0) into v_chunks
        from public.app_snapshot_chunks c
       where c.user_id = new.user_id
         and (c.upload_id = v_upload or c.sync_id = v_upload);
      v_size := greatest(v_size, v_chunks);
    end if;
  end if;

  if v_size > v_cfg.max_payload_bytes then
    if public.sync_guard_log('payload_too_large', jsonb_build_object('bytes', v_size)) then
      raise exception 'sync_guard: payload too large (% bytes)', v_size using errcode = 'P0001';
    end if;
  end if;

  if jsonb_typeof(new.payload->'tables') = 'object' then
    select coalesce(jsonb_agg(k), '[]'::jsonb) into v_names
      from jsonb_object_keys(new.payload->'tables') k;
  elsif jsonb_typeof(new.payload->'table_names') = 'array' then
    v_names := new.payload->'table_names';
  end if;

  if v_names is not null then
    select array_agg(e) into v_unknown
      from jsonb_array_elements_text(v_names) e
     where not exists (select 1 from public.sync_guard_allowed_tables a where a.table_name = e);
    if v_unknown is not null then
      if public.sync_guard_log('unknown_tables', jsonb_build_object('tables', to_jsonb(v_unknown))) then
        raise exception 'sync_guard: unknown tables %', v_unknown using errcode = 'P0001';
      end if;
    end if;
  end if;
  return new;
end;
$function$;
