-- Snapshot race guard (البند 1) — additive, backward-safe.
-- Apply to live ONLY after explicit confirmation (Step 0 + review).
-- Do NOT revoke direct table INSERT/UPDATE for authenticated in this phase.
-- TODO PHASE 2: after all installed clients use rpc_push_snapshot, revoke direct
-- INSERT/UPDATE on public.app_snapshots (and chunk write policy as needed)
-- for the authenticated role so legacy upsert cannot bypass the guard.

-- 1. Version column (additive; old clients unaffected)
ALTER TABLE public.app_snapshots
  ADD COLUMN IF NOT EXISTS content_version bigint NOT NULL DEFAULT 1;

-- 2. Upload namespace for chunked snapshots
ALTER TABLE public.app_snapshots
  ADD COLUMN IF NOT EXISTS upload_id text;
ALTER TABLE public.app_snapshot_chunks
  ADD COLUMN IF NOT EXISTS upload_id text;
CREATE INDEX IF NOT EXISTS ix_snapshot_chunks_upload
  ON public.app_snapshot_chunks (user_id, upload_id);

-- 3. Trigger: EVERY update bumps the version, regardless of writer.
--    This is what keeps legacy direct-upsert clients visible to the guard.
CREATE OR REPLACE FUNCTION public.fn_bump_snapshot_version()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.content_version := COALESCE(OLD.content_version, 0) + 1;
  NEW.updated_at := now();   -- server clock, never client clock
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_bump_snapshot_version ON public.app_snapshots;
CREATE TRIGGER trg_bump_snapshot_version
  BEFORE UPDATE ON public.app_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.fn_bump_snapshot_version();

-- On INSERT ensure version starts at 1 and updated_at is server time
CREATE OR REPLACE FUNCTION public.fn_init_snapshot_version()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.content_version := 1;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_init_snapshot_version ON public.app_snapshots;
CREATE TRIGGER trg_init_snapshot_version
  BEFORE INSERT ON public.app_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.fn_init_snapshot_version();

-- 4. Atomic push RPC (SECURITY INVOKER: RLS still applies)
CREATE OR REPLACE FUNCTION public.rpc_push_snapshot(
  p_expected_version bigint,
  p_payload jsonb,
  p_schema_version integer,
  p_device_label text,
  p_idempotency_key text,
  p_upload_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER AS $$
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
END $$;
