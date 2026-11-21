-- Dualhook كمزود نقل رسمي (Graph عبر api.dualhook.com)
ALTER TABLE public.tenant_whatsapp_gateways
  DROP CONSTRAINT IF EXISTS tenant_whatsapp_gateways_provider_check;

ALTER TABLE public.tenant_whatsapp_gateways
  ADD CONSTRAINT tenant_whatsapp_gateways_provider_check
  CHECK (
    whatsapp_provider IN (
      'waha',
      'evolution',
      'cloud_api',
      'whats360',
      'ycloud',
      'dualhook'
    )
  );

COMMENT ON COLUMN public.tenant_whatsapp_gateways.provider_connection_id IS
  'معرّف الاتصال عند طبقة النقل (Dualhook/YCloud/غيره) — ليس للتطبيق';
