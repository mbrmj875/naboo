-- ذاكرة محادثة العميل + حقول البطاقة، ليجيب الرد التلقائي عن أسئلة الزبون
-- بدل أن يعامل كل رسالة كأنها تقييم.

-- 1) نص الرسالة الصادرة: بدونه لا يعرف الرد التالي ما قلناه للزبون قبل قليل
ALTER TABLE public.whatsapp_message_logs
  ADD COLUMN IF NOT EXISTS body text,
  ADD COLUMN IF NOT EXISTS card_payload jsonb;

COMMENT ON COLUMN public.whatsapp_message_logs.body IS
  'نص الرسالة الصادرة — يُقرأ لبناء سياق المحادثة في الرد التلقائي';

COMMENT ON COLUMN public.whatsapp_message_logs.card_payload IS
  'حقول بطاقة الغيار وقت الإرسال (سيارة، زيت، فلاتر، مبالغ) — مرجع الرد على أسئلة الزبون';

-- 2) الردود التلقائية تُقرأ كثيراً بالهاتف والوقت
CREATE INDEX IF NOT EXISTS idx_whatsapp_message_logs_tenant_phone_body
  ON public.whatsapp_message_logs (tenant_user_id, to_phone, created_at DESC)
  WHERE body IS NOT NULL;

-- 3) رسائل الزبون تُقرأ بنفس الترتيب لبناء السياق
CREATE INDEX IF NOT EXISTS idx_whatsapp_inbound_tenant_phone_received
  ON public.whatsapp_inbound_messages (tenant_user_id, from_phone, received_at DESC);
