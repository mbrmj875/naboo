-- نسخة حرفية من rpc_push_snapshot ومحفزاتها على الإنتاج، لتشغيلها على Postgres
-- محلي معزول فقط. auth.uid() بديل يقرأ المعرف من إعداد الجلسة.
DROP SCHEMA IF EXISTS public CASCADE;
DROP SCHEMA IF EXISTS auth CASCADE;
CREATE SCHEMA public;
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

CREATE TABLE public.app_snapshots (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_label text,
  schema_version integer NOT NULL DEFAULT 1,
  payload jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  idempotency_key text,
  content_version bigint NOT NULL DEFAULT 1,
  upload_id text
);
CREATE UNIQUE INDEX ux_app_snapshots_user ON public.app_snapshots (user_id);

CREATE TABLE public.app_snapshots_history (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL,
  archived_at timestamptz NOT NULL DEFAULT now(),
  source_updated_at timestamptz,
  content_version bigint,
  schema_version integer,
  device_label text,
  idempotency_key text,
  upload_id text,
  payload jsonb,
  note text
);

CREATE TABLE public.app_snapshot_chunks (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sync_id text NOT NULL,
  chunk_index integer NOT NULL,
  chunk_data text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  upload_id text,
  UNIQUE (user_id, sync_id, chunk_index)
);

CREATE OR REPLACE FUNCTION public.fn_archive_app_snapshot_before_update()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.app_snapshots_history (
    user_id, source_updated_at, content_version, schema_version,
    device_label, idempotency_key, upload_id, payload, note
  ) VALUES (
    OLD.user_id, OLD.updated_at, OLD.content_version, OLD.schema_version,
    OLD.device_label, OLD.idempotency_key, OLD.upload_id, OLD.payload,
    'auto_archive_before_update'
  );
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bump_snapshot_version()
 RETURNS trigger LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.content_version := COALESCE(OLD.content_version, 0) + 1;
  NEW.updated_at := now();   -- server clock, never client clock
  RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.fn_init_snapshot_version()
 RETURNS trigger LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.content_version := 1;
  NEW.updated_at := now();
  RETURN NEW;
END $function$;

CREATE TRIGGER trg_archive_app_snapshot_before_update BEFORE UPDATE ON public.app_snapshots FOR EACH ROW EXECUTE FUNCTION fn_archive_app_snapshot_before_update();
CREATE TRIGGER trg_bump_snapshot_version BEFORE UPDATE ON public.app_snapshots FOR EACH ROW EXECUTE FUNCTION fn_bump_snapshot_version();
CREATE TRIGGER trg_init_snapshot_version BEFORE INSERT ON public.app_snapshots FOR EACH ROW EXECUTE FUNCTION fn_init_snapshot_version();

CREATE OR REPLACE FUNCTION public.rpc_push_snapshot(p_expected_version bigint, p_payload jsonb, p_schema_version integer, p_device_label text, p_idempotency_key text, p_upload_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_row public.app_snapshots%ROWTYPE;
BEGIN
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
