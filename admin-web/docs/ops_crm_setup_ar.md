# Naboo Ops CRM — متغيرات البيئة

## مطلوب لتشغيل SQL
شغّل الملف مرة واحدة من Supabase SQL Editor:

`admin-web/supabase/ops_crm_v1.sql`

## متغيرات admin-web / الاستضافة

| المتغير | الغرض |
|---------|--------|
| `NABOO_OPS_WEBHOOK_SECRET` | سر استقبال webhook واتساب / قنوات |
| `NABOO_OPS_WA_SEND_URL` | (اختياري) عنوان إرسال واتساب الصادر |
| `NABOO_OPS_WA_SEND_TOKEN` | (اختياري) Bearer للإرسال |
| `DEEPSEEK_API_KEY` | اقتراحات AI في الصندوق |
| `NABOO_OPS_CONTEXT_SECRET` | (اختياري) استدعاء سياق المساعد |

## Webhook واتساب

`POST /api/ops/whatsapp-webhook`

```json
{
  "secret": "…",
  "channel": "whatsapp",
  "from_phone": "07701234567",
  "text": "مرحبا",
  "external_id": "wamid.…"
}
```

## قنوات لاحقة

`POST /api/ops/channels/ingress` — نفس السر؛ القنوات غير المفعّلة ترجع 202.
