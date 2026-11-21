# نشر المرحلة 2–3 — واتساب المحل (Supabase + QR + FCM)

## 1) قاعدة البيانات

في **Supabase → SQL Editor** نفّذ:

`migrations/20260705_tenant_whatsapp_gateway.sql`

---

## 2) أسرار Edge Functions

في **Supabase → Edge Functions → Secrets**:

| السر | القيمة |
|------|--------|
| `EVOLUTION_API_KEY` | مفتاح Evolution |
| `EVOLUTION_BASE_URL` | `http://72.61.191.237:8080` |
| `WHATSAPP_DISCONNECT_WEBHOOK_SECRET` | نفس `WEBHOOK_SECRET` أو سر جديد |
| `FCM_SERVICE_ACCOUNT_JSON` | موجود مسبقاً لـ owner alerts |

---

## 3) نشر الدوال

```bash
supabase functions deploy whatsapp-gateway
supabase functions deploy whatsapp-disconnect-notify
```

---

## 4) التطبيق (Flutter)

- سجّل دخول **Google / سحابي**
- ادخل **سجل غيار الزيت → إعدادات → ربط واتساب المحل**
- امسح QR من هاتف المحل
- كل الأجهزة ترى «متصل»

---

## 5) n8n — إشعار FCM عند الانفصال (مرحلة 3)

بعد عقدة WhatsApp JS2، إذا `ok === false` و `reason === whatsapp_disconnected`، أضف عقدة **HTTP Request**:

```
POST https://PROJECT.supabase.co/functions/v1/whatsapp-disconnect-notify
Header: x-webhook-secret: YOUR_SECRET
Body: {
  "instance_name": "{{ $('Code in JavaScript1').item.json.instanceName }}",
  "local_tenant_id": 1
}
```

---

## 6) instance لكل محل

| الحساب | اسم Evolution |
|--------|---------------|
| UUID المالك | `shop_{uuid_with_underscores}` |

مثال: `shop_a1b2c3d4_e5f6_...`

---

## 7) اختبار

1. ربط QR من التطبيق
2. حفظ بطاقة زيت → رسالة للزبون
3. افتح التطبيق على **حاسوب ثانٍ** → يظهر «متصل»
4. اقطع Evolution → بانر أحمر + (بعد n8n) إشعار FCM للمالك

---

*مرجع موثوقية: `oil_change_whatsapp_reliability_v1.md`*
