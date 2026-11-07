-- شكر تلقائي للعميل بعد تقييمه؛ يمكن لكل محل إيقافه.
-- النص حر لا قالب: نافذة خدمة العملاء (24 ساعة) مفتوحة لأن العميل راسلنا للتو.

ALTER TABLE public.tenant_whatsapp_gateways
  ADD COLUMN IF NOT EXISTS rating_auto_reply boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.tenant_whatsapp_gateways.rating_auto_reply IS
  'إرسال شكر تلقائي بعد تقييم العميل — نص حر داخل نافذة الـ24 ساعة';
