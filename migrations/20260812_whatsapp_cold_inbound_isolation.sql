-- عزل الرقم المشترك: وارد بارد بلا مستأجر + سجل ردود النظام.
-- حساس أمنياً: لا ننسب رسالة غريب لمحل بدون رابط صادر سابق.

ALTER TABLE public.whatsapp_inbound_messages
  ALTER COLUMN tenant_user_id DROP NOT NULL;

ALTER TABLE public.whatsapp_inbound_messages
  ADD COLUMN IF NOT EXISTS resolution text;

COMMENT ON COLUMN public.whatsapp_inbound_messages.resolution IS
  'bound | cold_unmatched | unknown_number — نتيجة عزل المستأجر للرقم المشترك';

COMMENT ON COLUMN public.whatsapp_inbound_messages.tenant_user_id IS
  'مستأجر مربوط فقط عند وجود مراسلة صادرة سابقة لنفس الرقم؛ NULL للتواصل البارد';

CREATE TABLE IF NOT EXISTS public.whatsapp_cold_replies (
  provider_message_id text PRIMARY KEY,
  from_phone text NOT NULL,
  phone_number_id text,
  body text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_cold_replies_phone_created
  ON public.whatsapp_cold_replies (from_phone, created_at DESC);

ALTER TABLE public.whatsapp_cold_replies ENABLE ROW LEVEL SECURITY;

-- لا سياسة لـ authenticated: القراءة/الكتابة عبر service_role فقط (Edge).

COMMENT ON TABLE public.whatsapp_cold_replies IS
  'ردود نظام نابو للتواصل البارد على الرقم المشترك — dedupe per wamid';
