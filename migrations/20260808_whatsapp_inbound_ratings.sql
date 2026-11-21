-- التقاط ردود العملاء الواردة + تقييم الخدمة المنسوب للموظف
-- نفّذ في Supabase SQL Editor قبل نشر whatsapp-cloud-webhook المحدّث.

-- 1) ربط سجل الإرسال بالطلب والموظف (بدونهما لا يمكن إسناد التقييم)
ALTER TABLE public.whatsapp_message_logs
  ADD COLUMN IF NOT EXISTS order_ref text,
  ADD COLUMN IF NOT EXISTS employee_name text;

CREATE INDEX IF NOT EXISTS idx_whatsapp_message_logs_tenant_phone_created
  ON public.whatsapp_message_logs (tenant_user_id, to_phone, created_at DESC);

COMMENT ON COLUMN public.whatsapp_message_logs.order_ref IS
  'معرّف بطاقة غيار الزيت كما أرسله التطبيق — نص لأن المصدر قد يكون int محلي أو uuid';

COMMENT ON COLUMN public.whatsapp_message_logs.employee_name IS
  'اسم الفني وقت الإرسال — لقطة نصية لأن لا يوجد جدول موظفين';

-- 2) الرسائل الواردة الخام (تدقيق + منع التكرار)
CREATE TABLE IF NOT EXISTS public.whatsapp_inbound_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'cloud_api',
  provider_message_id text NOT NULL,
  from_phone text NOT NULL,
  body text,
  message_type text NOT NULL DEFAULT 'text',
  context_message_id text,
  raw jsonb,
  received_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_inbound_provider_message
  ON public.whatsapp_inbound_messages (provider_message_id);

CREATE INDEX IF NOT EXISTS idx_whatsapp_inbound_tenant_received
  ON public.whatsapp_inbound_messages (tenant_user_id, received_at DESC);

CREATE INDEX IF NOT EXISTS idx_whatsapp_inbound_context
  ON public.whatsapp_inbound_messages (context_message_id)
  WHERE context_message_id IS NOT NULL;

ALTER TABLE public.whatsapp_inbound_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS whatsapp_inbound_messages_own_select ON public.whatsapp_inbound_messages;
CREATE POLICY whatsapp_inbound_messages_own_select
  ON public.whatsapp_inbound_messages
  FOR SELECT
  TO authenticated
  USING (tenant_user_id = auth.uid());

COMMENT ON TABLE public.whatsapp_inbound_messages IS
  'ردود العملاء الواردة — تُكتب من Edge فقط';

-- 3) تقييم الخدمة
CREATE TABLE IF NOT EXISTS public.oil_change_service_ratings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  order_ref text,
  employee_name text,
  customer_phone text NOT NULL,
  score integer CHECK (score IS NULL OR (score BETWEEN 1 AND 10)),
  note text,
  source text NOT NULL DEFAULT 'reply_context'
    CHECK (source IN ('reply_context', 'recent_card', 'manual')),
  inbound_message_id uuid REFERENCES public.whatsapp_inbound_messages (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

-- تقييم رقمي واحد معتمد لكل بطاقة — التكرار يُحفظ كملاحظة بلا score
CREATE UNIQUE INDEX IF NOT EXISTS idx_oil_ratings_one_score_per_order
  ON public.oil_change_service_ratings (tenant_user_id, order_ref)
  WHERE order_ref IS NOT NULL AND score IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_oil_ratings_tenant_employee
  ON public.oil_change_service_ratings (tenant_user_id, employee_name, created_at DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_oil_ratings_tenant_created
  ON public.oil_change_service_ratings (tenant_user_id, created_at DESC)
  WHERE deleted_at IS NULL;

ALTER TABLE public.oil_change_service_ratings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS oil_change_service_ratings_own_select ON public.oil_change_service_ratings;
CREATE POLICY oil_change_service_ratings_own_select
  ON public.oil_change_service_ratings
  FOR SELECT
  TO authenticated
  USING (tenant_user_id = auth.uid());

COMMENT ON TABLE public.oil_change_service_ratings IS
  'تقييم العميل لخدمة غيار الزيت منسوباً للفني — يُكتب من Edge فقط';

COMMENT ON COLUMN public.oil_change_service_ratings.source IS
  'reply_context = ردّ مباشر على البطاقة (دقيق) · recent_card = إسناد لآخر بطاقة خلال 72 ساعة';

-- 4) ملخص تقييمات الموظفين للواجهة
CREATE OR REPLACE VIEW public.oil_change_employee_rating_summary
WITH (security_invoker = true) AS
SELECT
  tenant_user_id,
  COALESCE(NULLIF(btrim(employee_name), ''), 'غير محدد') AS employee_name,
  COUNT(*) FILTER (WHERE score IS NOT NULL) AS ratings_count,
  ROUND(AVG(score) FILTER (WHERE score IS NOT NULL), 2) AS average_score,
  COUNT(*) FILTER (WHERE score IS NULL AND note IS NOT NULL) AS notes_count,
  MAX(created_at) AS last_rating_at
FROM public.oil_change_service_ratings
WHERE deleted_at IS NULL
GROUP BY 1, 2;

COMMENT ON VIEW public.oil_change_employee_rating_summary IS
  'متوسط وعدد تقييمات كل فني — يرث RLS من الجدول الأساسي';
