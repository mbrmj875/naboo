-- مسار مزدوج: QR (Evolution/WAHA) + WhatsApp Cloud API الرسمي
-- نفّذ في Supabase SQL Editor قبل نشر Edge Functions المحدّثة.

ALTER TABLE public.tenant_whatsapp_gateways
  ADD COLUMN IF NOT EXISTS whatsapp_provider text NOT NULL DEFAULT 'waha',
  ADD COLUMN IF NOT EXISTS cloud_phone_number_id text,
  ADD COLUMN IF NOT EXISTS cloud_waba_id text,
  ADD COLUMN IF NOT EXISTS cloud_setup_status text NOT NULL DEFAULT 'none';

ALTER TABLE public.tenant_whatsapp_gateways
  DROP CONSTRAINT IF EXISTS tenant_whatsapp_gateways_provider_check;

ALTER TABLE public.tenant_whatsapp_gateways
  ADD CONSTRAINT tenant_whatsapp_gateways_provider_check
  CHECK (whatsapp_provider IN ('waha', 'evolution', 'cloud_api'));

ALTER TABLE public.tenant_whatsapp_gateways
  DROP CONSTRAINT IF EXISTS tenant_whatsapp_gateways_cloud_setup_check;

ALTER TABLE public.tenant_whatsapp_gateways
  ADD CONSTRAINT tenant_whatsapp_gateways_cloud_setup_check
  CHECK (cloud_setup_status IN ('none', 'pending', 'ready', 'error'));

COMMENT ON COLUMN public.tenant_whatsapp_gateways.whatsapp_provider IS
  'evolution=QR غير رسمي | cloud_api=Meta الرسمي | waha=احتياطي تقني';

COMMENT ON COLUMN public.tenant_whatsapp_gateways.cloud_setup_status IS
  'none=غير مفعّل | pending=بانتظار توثيق Meta | ready=جاهز للإرسال | error=فشل إعداد';
