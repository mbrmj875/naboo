-- فصل دائم/مؤقت: حقول إصلاح وإعادة تشغيل (توافق خلفي — لا تغيّر قيم status)
-- نفّذ في Supabase SQL Editor قبل/مع نشر whatsapp-events و whatsapp-health-check.

ALTER TABLE public.tenant_whatsapp_gateways
  ADD COLUMN IF NOT EXISTS restart_attempts INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_restart_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS repair_needed BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS disconnect_cause TEXT;

COMMENT ON COLUMN public.tenant_whatsapp_gateways.restart_attempts IS
  'عدد محاولات restart التلقائي بعد فصل مؤقت (حدّه RESTART_MAX_ATTEMPTS على Edge)';
COMMENT ON COLUMN public.tenant_whatsapp_gateways.last_restart_at IS
  'آخر محاولة restart تلقائي — للـ cooldown/backoff';
COMMENT ON COLUMN public.tenant_whatsapp_gateways.repair_needed IS
  'true = يحتاج QR/إصلاح يدوي؛ لا يُعاد تشغيل الجلسة تلقائياً (منفصل عن status)';
COMMENT ON COLUMN public.tenant_whatsapp_gateways.disconnect_cause IS
  'سبب خام من Evolution (device_removed, 401, 515, …) للتشخيص';

CREATE INDEX IF NOT EXISTS idx_twg_health_temp_disc
  ON public.tenant_whatsapp_gateways (updated_at)
  WHERE status = 'disconnected' AND COALESCE(repair_needed, false) = false;
