# محفظة رسائل واتساب — تشغيل سريع

## تم على الإنتاج (naboo-lic)

- [x] تطبيق SQL `wa_message_wallet_v1` على Supabase
- [x] نشر Edge Function `whatsapp-gateway` (v127+) مع `wallet.ts`
- [x] الإطلاق التدريجي: `enforce_wallet = false` حتى لا يتوقف إرسال المحلات بلا رصيد

## تفعيل الخصم الإجباري لاحقاً

عندما تبدأ البيع والشحن من لوحة الإدارة:

```sql
update public.wa_message_platform_settings
set enforce_wallet = true, updated_at = now(), updated_by = 'ops'
where id = 1;
```

## التطبيق

حدّث/ابنِ نسخة التطبيق التي فيها شاشة المحفظة وبلاطة «تفاصيل الإرسال».

## لوحة الإدارة (admin-web)

مسارات API الجديدة تحتاج نشر Vercel لـ `naboo-admin` (فشل التفويض من الـ CLI هنا — انشر من حسابك أو لوحة Vercel).

بعد النشر: الحسابات → CRM → **محفظة واتساب**.

## أسعار

- الوحدة: 25 د.ع/رسالة (الألف الشهري = 25,000)
- سنوي: 300,000 معلن — يدفع 250,000 (شهران مجاناً)
- رقم نابو الرسمي (dualhook): 30 رسالة مجانية مرة واحدة عند أول ربط

## تذكير بعد الغيار

- SQL: `migrations/20261022_wa_oil_followup_v1.sql`
- Edge: `submit_followup_template` على `whatsapp-gateway`
- Cron: `whatsapp-oil-followup-cron` — جدّوله في Supabase (كل 5–15 دقيقة) مع `CRON_SECRET`
