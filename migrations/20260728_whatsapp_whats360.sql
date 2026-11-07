-- مزود واتس360 (API خارجي مؤقت) — توكن + instance لكل مستأجر
-- نفّذ في Supabase SQL Editor قبل نشر whatsapp-gateway المحدّث.

ALTER TABLE public.tenant_whatsapp_gateways
  ADD COLUMN IF NOT EXISTS whats360_instance_id text,
  ADD COLUMN IF NOT EXISTS whats360_access_token text;

ALTER TABLE public.tenant_whatsapp_gateways
  DROP CONSTRAINT IF EXISTS tenant_whatsapp_gateways_provider_check;

ALTER TABLE public.tenant_whatsapp_gateways
  ADD CONSTRAINT tenant_whatsapp_gateways_provider_check
  CHECK (whatsapp_provider IN ('waha', 'evolution', 'cloud_api', 'whats360'));

COMMENT ON COLUMN public.tenant_whatsapp_gateways.whats360_instance_id IS
  'معرّف الجهاز/الجلسة في whats360.live';

COMMENT ON COLUMN public.tenant_whatsapp_gateways.whats360_access_token IS
  'Access Token لـ whats360 — يُكتب عبر Edge فقط ولا يُعرض في التطبيق بعد الحفظ';
