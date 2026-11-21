-- تاريخ لقطات app_snapshots — أرشيَفة قبل الاستبدال + استعادة يدوية.
-- طبّق على المشروع الحي بعد مراجعة. لا يحذف app_snapshot_chunks.

CREATE TABLE IF NOT EXISTS public.app_snapshots_history (
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

CREATE INDEX IF NOT EXISTS ix_app_snapshots_history_user_archived
  ON public.app_snapshots_history (user_id, archived_at DESC);

ALTER TABLE public.app_snapshots_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_snapshots_history_select_own ON public.app_snapshots_history;
CREATE POLICY app_snapshots_history_select_own
  ON public.app_snapshots_history
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- لا كتابة من الكلاينت — الإدراج عبر service role / SQL إداري فقط.
REVOKE INSERT, UPDATE, DELETE ON public.app_snapshots_history FROM authenticated, anon;

-- أرشف الصف الحالي قبل أي UPDATE على اللقطة الرسمية.
CREATE OR REPLACE FUNCTION public.fn_archive_app_snapshot_before_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

DROP TRIGGER IF EXISTS trg_archive_app_snapshot_before_update ON public.app_snapshots;
CREATE TRIGGER trg_archive_app_snapshot_before_update
  BEFORE UPDATE ON public.app_snapshots
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_archive_app_snapshot_before_update();
