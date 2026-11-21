-- معيار التعلّم المتوسط للمساعد: تقييمات + أمثلة معتمدة (بدون fine-tuning).
-- يتطلب: وجود app_current_tenant_id() من 20260507_rls_tenant.sql

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'app_current_tenant_id'
  ) THEN
    RAISE EXCEPTION
      'Missing app_current_tenant_id(). Run 20260507_rls_tenant.sql first.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_assistant_tenant_id_from_jwt()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_tenant text;
BEGIN
  v_tenant := public.app_current_tenant_id();
  IF v_tenant IS NULL OR v_tenant = '' THEN
    RAISE EXCEPTION 'tenant_missing: refusing insert without authenticated tenant'
      USING errcode = 'P0001';
  END IF;
  NEW.tenant_id := v_tenant;
  RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.assistant_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id text NOT NULL,
  user_id uuid NULL REFERENCES auth.users (id) ON DELETE SET NULL,
  role_key text NOT NULL DEFAULT 'staff',
  route_id text NOT NULL DEFAULT '',
  question_hash text NOT NULL,
  question_text text NOT NULL,
  answer_text text NOT NULL,
  rating smallint NOT NULL CHECK (rating IN (-1, 1)),
  source text NOT NULL DEFAULT 'ai',
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.assistant_feedback IS
  'تقييمات ردود مساعد الإرشاد (مفيد/غير مفيد) — نصوص منظّفة بلا أسرار';

CREATE INDEX IF NOT EXISTS idx_assistant_feedback_tenant_created
  ON public.assistant_feedback (tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_assistant_feedback_tenant_qhash
  ON public.assistant_feedback (tenant_id, question_hash, rating);

CREATE TABLE IF NOT EXISTS public.assistant_approved_examples (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id text NOT NULL,
  topic_key text NOT NULL DEFAULT 'general',
  question text NOT NULL,
  answer text NOT NULL,
  question_hash text NOT NULL,
  source_feedback_ids uuid[] NOT NULL DEFAULT '{}',
  active boolean NOT NULL DEFAULT true,
  approved_by uuid NULL REFERENCES auth.users (id) ON DELETE SET NULL,
  approved_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, question_hash)
);

COMMENT ON TABLE public.assistant_approved_examples IS
  'أمثلة سؤال→جواب معتمدة تُحقن كـ few-shot في guide-assistant';

CREATE INDEX IF NOT EXISTS idx_assistant_examples_tenant_active
  ON public.assistant_approved_examples (tenant_id, active)
  WHERE active = true;

ALTER TABLE public.assistant_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assistant_approved_examples ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS assistant_feedback_select_tenant ON public.assistant_feedback;
CREATE POLICY assistant_feedback_select_tenant
  ON public.assistant_feedback
  FOR SELECT
  USING (tenant_id = public.app_current_tenant_id());

DROP POLICY IF EXISTS assistant_feedback_insert_tenant ON public.assistant_feedback;
CREATE POLICY assistant_feedback_insert_tenant
  ON public.assistant_feedback
  FOR INSERT
  WITH CHECK (
    tenant_id = public.app_current_tenant_id()
    AND (user_id IS NULL OR user_id = auth.uid())
  );

DROP POLICY IF EXISTS assistant_feedback_update_own ON public.assistant_feedback;
CREATE POLICY assistant_feedback_update_own
  ON public.assistant_feedback
  FOR UPDATE
  USING (
    tenant_id = public.app_current_tenant_id()
    AND user_id = auth.uid()
  )
  WITH CHECK (
    tenant_id = public.app_current_tenant_id()
    AND user_id = auth.uid()
  );

DROP POLICY IF EXISTS assistant_examples_select_tenant ON public.assistant_approved_examples;
CREATE POLICY assistant_examples_select_tenant
  ON public.assistant_approved_examples
  FOR SELECT
  USING (tenant_id = public.app_current_tenant_id());

DROP POLICY IF EXISTS assistant_examples_insert_tenant ON public.assistant_approved_examples;
CREATE POLICY assistant_examples_insert_tenant
  ON public.assistant_approved_examples
  FOR INSERT
  WITH CHECK (tenant_id = public.app_current_tenant_id());

DROP POLICY IF EXISTS assistant_examples_update_tenant ON public.assistant_approved_examples;
CREATE POLICY assistant_examples_update_tenant
  ON public.assistant_approved_examples
  FOR UPDATE
  USING (tenant_id = public.app_current_tenant_id())
  WITH CHECK (tenant_id = public.app_current_tenant_id());

DROP TRIGGER IF EXISTS trg_assistant_feedback_tenant ON public.assistant_feedback;
CREATE TRIGGER trg_assistant_feedback_tenant
  BEFORE INSERT ON public.assistant_feedback
  FOR EACH ROW
  EXECUTE FUNCTION public.set_assistant_tenant_id_from_jwt();

DROP TRIGGER IF EXISTS trg_assistant_examples_tenant ON public.assistant_approved_examples;
CREATE TRIGGER trg_assistant_examples_tenant
  BEFORE INSERT ON public.assistant_approved_examples
  FOR EACH ROW
  EXECUTE FUNCTION public.set_assistant_tenant_id_from_jwt();
