-- معمارية قنوات الإشعار + واتساب الرسمي (YCloud كـ Transport فقط)
-- نفّذ في Supabase SQL Editor قبل نشر Edge المحدّث.

-- 1) اتصال: مزود ycloud + معرّفات Cloud (بدون أعمدة قالب)
ALTER TABLE public.tenant_whatsapp_gateways
  ADD COLUMN IF NOT EXISTS provider_connection_id text,
  ADD COLUMN IF NOT EXISTS ycloud_from_phone text;

ALTER TABLE public.tenant_whatsapp_gateways
  DROP CONSTRAINT IF EXISTS tenant_whatsapp_gateways_provider_check;

ALTER TABLE public.tenant_whatsapp_gateways
  ADD CONSTRAINT tenant_whatsapp_gateways_provider_check
  CHECK (whatsapp_provider IN ('waha', 'evolution', 'cloud_api', 'whats360', 'ycloud'));

COMMENT ON COLUMN public.tenant_whatsapp_gateways.provider_connection_id IS
  'معرّف الاتصال عند طبقة النقل (YCloud/غيره) — ليس للتطبيق';

COMMENT ON COLUMN public.tenant_whatsapp_gateways.ycloud_from_phone IS
  'رقم المرسل E.164 لطبقة النقل الرسمية';

-- 2) قوالب لكل مستأجر (منفصلة عن صف الاتصال)
CREATE TABLE IF NOT EXISTS public.tenant_whatsapp_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'ycloud',
  template_key text NOT NULL,
  template_name text NOT NULL,
  template_id text,
  language text NOT NULL DEFAULT 'ar',
  category text NOT NULL DEFAULT 'utility'
    CHECK (category IN ('utility', 'marketing', 'authentication')),
  status text NOT NULL DEFAULT 'none'
    CHECK (status IN ('none', 'pending', 'approved', 'rejected', 'disabled')),
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_user_id, provider, template_name, language)
);

CREATE INDEX IF NOT EXISTS idx_tenant_whatsapp_templates_tenant
  ON public.tenant_whatsapp_templates (tenant_user_id, status);

ALTER TABLE public.tenant_whatsapp_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tenant_whatsapp_templates_own_select ON public.tenant_whatsapp_templates;
CREATE POLICY tenant_whatsapp_templates_own_select
  ON public.tenant_whatsapp_templates
  FOR SELECT
  TO authenticated
  USING (tenant_user_id = auth.uid());

-- الكتابة عبر service_role / Edge فقط
COMMENT ON TABLE public.tenant_whatsapp_templates IS
  'قوالب واتساب لكل مستأجر — الحالة الداخلية؛ الواجهة ترى ready_state المحسوب فقط';

-- 3) أسرار النقل (لا يقرأها العميل)
CREATE TABLE IF NOT EXISTS public.whatsapp_provider_secrets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  provider text NOT NULL,
  secret_kind text NOT NULL,
  secret_value text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_user_id, provider, secret_kind)
);

ALTER TABLE public.whatsapp_provider_secrets ENABLE ROW LEVEL SECURITY;
-- لا سياسات authenticated — Edge بمفتاح service_role فقط

COMMENT ON TABLE public.whatsapp_provider_secrets IS
  'أسرار مزودي واتساب — service_role فقط';

-- 4) سجل الإرسال عبر NotificationDispatcher
CREATE TABLE IF NOT EXISTS public.whatsapp_message_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  channel text NOT NULL DEFAULT 'whatsapp',
  provider text,
  template_key text,
  to_phone text,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'sent', 'delivered', 'failed', 'rejected')),
  provider_message_id text,
  error text,
  idempotency_key text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_message_logs_tenant_created
  ON public.whatsapp_message_logs (tenant_user_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_message_logs_idempotency
  ON public.whatsapp_message_logs (tenant_user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL AND idempotency_key <> '';

ALTER TABLE public.whatsapp_message_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS whatsapp_message_logs_own_select ON public.whatsapp_message_logs;
CREATE POLICY whatsapp_message_logs_own_select
  ON public.whatsapp_message_logs
  FOR SELECT
  TO authenticated
  USING (tenant_user_id = auth.uid());

COMMENT ON TABLE public.whatsapp_message_logs IS
  'سجل إشعارات واتساب — يُكتب من Edge فقط';
