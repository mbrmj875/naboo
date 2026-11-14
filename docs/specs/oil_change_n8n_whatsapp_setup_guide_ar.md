# دليل إعداد واتساب تلقائي لقسم الزيوت — n8n + DeepSeek + Hostinger

> **الحالة:** دليل تنفيذي — خطوة بخطوة  
> **النطاق:** قسم غيار الزيت فقط (مرحلة أولى)  
> **الجمهور:** مشغّل NaBoo + أصحاب المحلات (~10 مستأجرين)  
> **المتطلبات:** Hostinger VPS KVM 2 + DeepSeek API + نطاق (مُفضّل)

---

## نظرة عامة

```
┌─────────────────┐     Webhook      ┌──────────────┐     DeepSeek     ┌─────────────┐
│ تطبيق NaBoo     │ ───────────────▶ │ n8n          │ ──────────────▶ │ رسالة عربية │
│ (قسم الزيوت)    │                  │ (Hostinger)  │                 └──────┬──────┘
└─────────────────┘                  └──────┬───────┘                        │
                                              │ Evolution API                   │
                                              ▼                                 ▼
                                       ┌──────────────┐              ┌─────────────┐
                                       │ رقم المحل    │ ────────────▶ │ هاتف الزبون │
                                       │ (QR مرة واحدة)│              └─────────────┘
                                       └──────────────┘
```

| من | ماذا يفعل | مرة واحدة أم يومياً؟ |
|----|-----------|----------------------|
| **أنت (مشغّل)** | VPS + n8n + Evolution + DeepSeek | مرة واحدة + صيانة |
| **صاحب المحل** | يمسح QR لرقم واتساب محله | مرة واحدة (+ إعادة عند انقطاع) |
| **الموظف** | يسجل سيارة → «حفظ وبيع» | يومياً — تلقائي بعدها |
| **الزبون** | يستقبل الرسالة | لا شيء |

---

## المرحلة 0 — تحقق قبل البدء

### قائمة التحقق

- [ ] Hostinger VPS KVM 2 **قيد التشغيل** (IP مثل `72.61.191.237`)
- [ ] اشتراك DeepSeek API (~5$) + مفتاح `sk-...`
- [ ] نطاق مربوط بـ Hostinger (مثل `naboo.iq`) — **مُفضّل للإنتاج**
- [ ] وصول SSH للـ VPS (من لوحة Hostinger → VPS → إدارة → SSH)

### معلومات سجّلها هنا (لا تشاركها علناً)

| الحقل | قيمتك |
|-------|-------|
| IP السيرفر | `72.61.191.237` |
| نطاق n8n | `n8n.yourdomain.com` |
| نطاق Evolution | `wa.yourdomain.com` |
| مفتاح DeepSeek | `sk-...` |
| مفتاح Evolution API | (تولّده أنت — 32 حرف عشوائي) |
| مفتاح Webhook سري | (تولّده أنت — لكل طلب من التطبيق) |

---

## المرحلة 1 — تثبيت n8n على Hostinger

### الخطوة 1.1 — من لوحة Hostinger

1. ادخل [hpanel.hostinger.com](https://hpanel.hostinger.com)
2. من القائمة: **أدوات المطور** → **VPS**
3. إن كان لديك VPS يعمل (`srv1769126`):
   - اضغط **إدارة**
   - ابحث عن **تطبيقات** أو **OS / إعادة تثبيت**
   - اختر قالب **n8n** على **Ubuntu 24.04**
   - أكمل التثبيت
4. إن كنت تنشئ VPS جديداً:
   - **أضف المزيد** → **استضافة n8n الذاتية** → **إعداد**
   - اختر **Ubuntu 24.04** + **n8n**
   - اضغط **التالي** وأكمل الدفع/الإعداد

> ⚠️ إعادة تثبيت القالب قد تمسح بيانات على السيرفر — احفظ نسخة إن وُجدت بيانات مهمة.

### الخطوة 1.2 — انتظر حتى يكتمل التثبيت

- الحالة في لوحة Hostinger: **قيد التشغيل** ✓
- انتظر 5–15 دقيقة بعد أول تثبيت

### الخطوة 1.3 — افتح n8n لأول مرة

1. من لوحة VPS → **إدارة** → ابحث عن **رابط n8n** أو **Application URL**
2. أو جرّب في المتصفح:
   ```
   http://72.61.191.237:5678
   ```
3. أنشئ حساب **Owner** (بريد + كلمة مرور قوية)
4. سجّل الدخول

### الخطوة 1.4 — تأمين n8n (إنتاج)

1. في n8n: **Settings** → **Users** — لا تشارك حساب Owner
2. **Settings** → **Variables** — أضف لاحقاً:
   - `DEEPSEEK_API_KEY`
   - `EVOLUTION_API_KEY`
   - `WEBHOOK_SECRET`
3. من Hostinger: فعّل **جدار ناري** — اسمح فقط:
   - `22` (SSH)
   - `80`, `443` (HTTPS)
   - أغلق `5678` من الإنترنت العام بعد ربط نطاق + HTTPS

### معيار نجاح المرحلة 1

- [ ] تفتح واجهة n8n وتسجّل الدخول
- [ ] الحالة: VPS يعمل

**عند الانتهاء:** أخبر المساعد «انتهيت من المرحلة 1» للانتقال للمرحلة 2.

---

## المرحلة 2 — نطاق + HTTPS (إنتاج)

### الخطوة 2.1 — إنشاء سجل DNS

في Hostinger → **النطاقات** → DNS:

| النوع | الاسم | القيمة | TTL |
|-------|-------|--------|-----|
| A | `n8n` | `72.61.191.237` | 3600 |
| A | `wa` | `72.61.191.237` | 3600 |

النتيجة:
- `https://n8n.yourdomain.com` → n8n
- `https://wa.yourdomain.com` → Evolution API

### الخطوة 2.2 — شهادة SSL

- Hostinger غالباً يوفّر SSL مجاني عبر **Traefik** أو **Nginx** في قالب n8n
- من لوحة VPS تحقق من تفعيل HTTPS للنطاق الفرعي
- إن لم يكن تلقائياً: استخدم **Certbot** على Ubuntu

### معيار نجاح المرحلة 2

- [ ] `https://n8n.yourdomain.com` يفتح n8n بدون تحذير SSL

---

## المرحلة 3 — تثبيت Evolution API (واتساب)

### الخطوة 3.1 — اتصل بالسيرفر عبر SSH

من لوحة Hostinger → VPS → **إدارة** → **SSH access** → افتح Terminal أو استخدم:

```bash
ssh root@72.61.191.237
```

### الخطوة 3.2 — ثبّت Docker (إن لم يكن مثبتاً)

```bash
apt update && apt install -y docker.io docker-compose-plugin
systemctl enable docker && systemctl start docker
```

### الخطوة 3.3 — أنشئ مجلد Evolution

```bash
mkdir -p /opt/evolution && cd /opt/evolution
```

### الخطوة 3.4 — ملف docker-compose

انسخ من المشروع: `infra/hostinger/docker-compose.evolution.yml`

أو أنشئ `/opt/evolution/docker-compose.yml`:

```yaml
services:
  evolution-api:
    image: atendai/evolution-api:latest
    container_name: evolution-api
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      AUTHENTICATION_API_KEY: "ضع_مفتاحاً_سرياً_قوياً_هنا"
      SERVER_URL: "https://wa.yourdomain.com"
    volumes:
      - evolution_data:/evolution/instances

volumes:
  evolution_data:
```

```bash
docker compose up -d
docker compose logs -f
```

### الخطوة 3.5 — تحقق

```bash
curl -H "apikey: مفتاحك_السري" http://localhost:8080/instance/fetchInstances
```

يجب أن يرجع `[]` (قائمة فارغة — طبيعي).

### معيار نجاح المرحلة 3

- [ ] Evolution يعمل على المنفذ 8080
- [ ] `EVOLUTION_API_KEY` مسجّل في دفترك

---

## المرحلة 4 — ربط أول محل (QR)

### الخطوة 4.1 — إنشاء instance لكل متجر

كل `tenant_id` في NaBoo = instance واحد في Evolution:

```bash
curl -X POST "http://localhost:8080/instance/create" \
  -H "apikey: مفتاحك" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "tenant_SHOP_UUID",
    "qrcode": true,
    "integration": "WHATSAPP-BAILEYS"
  }'
```

استبدل `SHOP_UUID` بـ UUID المستخدم من Supabase (نفس `tenant_id`).

### الخطوة 4.2 — الحصول على QR

```bash
curl "http://localhost:8080/instance/connect/tenant_SHOP_UUID" \
  -H "apikey: مفتاحك"
```

- صاحب المحل يمسح QR من **واتساب المحل** (الإعدادات → الأجهزة المرتبطة)
- تحقق من الاتصال:

```bash
curl "http://localhost:8080/instance/connectionState/tenant_SHOP_UUID" \
  -H "apikey: مفتاحك"
```

يجب أن يظهر `state: "open"`.

### الخطوة 4.3 — إرسال رسالة اختبار

```bash
curl -X POST "http://localhost:8080/message/sendText/tenant_SHOP_UUID" \
  -H "apikey: مفتاحك" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "9647XXXXXXXXX",
    "text": "اختبار من NaBoo — مركز غيار الزيت"
  }'
```

### معيار نجاح المرحلة 4

- [ ] رسالة اختبار وصلت لهاتف زبون تجريبي
- [ ] الرسالة ظهرت من **رقم المحل** وليس رقمك الشخصي

---

## المرحلة 5 — Workflow في n8n

### الخطوة 5.1 — استيراد Workflow

1. افتح n8n → **Workflows** → **Import from File**
2. اختر: `infra/hostinger/n8n-oil-change-workflow.json`
3. فعّل المتغيرات في **Settings → Variables**

### الخطوة 5.2 — مسار العمل

```
Webhook (POST /oil-change-notify)
  → التحقق من WEBHOOK_SECRET
  → Code: تحديد instanceName من tenant_id
  → HTTP: DeepSeek (صياغة رسالة)
  → HTTP: Evolution sendText
  → Respond: { ok: true, message_id }
```

### الخطوة 5.3 — رابط Webhook النهائي

بعد تفعيل Workflow:

```
https://n8n.yourdomain.com/webhook/oil-change-notify
```

احفظه — سيُستخدم في التطبيق.

### معيار نجاح المرحلة 5

- [ ] Postman يرسل POST للـ Webhook ويصل واتساب للزبون

---

## المرحلة 6 — ربط تطبيق NaBoo (Flutter)

### التغييرات المطلوبة (للمطور)

| الملف | التغيير |
|-------|---------|
| `oil_change_order_form_screen.dart` | بعد `completeFromOrder` → استدعاء Webhook |
| `oil_change_settings.dart` | `webhook_url`, `webhook_secret`, `auto_whatsapp_enabled` |
| `oil_change_hub_screen.dart` | شاشة حالة الربط + QR |
| جديد: `oil_change_whatsapp_notify_service.dart` | HTTP POST للـ Webhook |

### Payload من التطبيق

```json
{
  "tenant_id": "uuid-المحل",
  "order_id": 456,
  "customer_phone": "07801234567",
  "webhook_secret": "...",
  "order": {
    "customer_name": "أحمد",
    "vehicle": "كيا سورنتو",
    "plate": "بغداد 12345",
    "oil": "كاسترول 5W-30 — 4 لتر",
    "total_iqd": 45000,
    "paid_iqd": 20000,
    "remainder_iqd": 25000,
    "invoice_id": 123,
    "invoice_type": "credit",
    "store_name": "مركز النجوم"
  }
}
```

### Fallback

إن فشل Webhook → `wa.me` + القالب الحالي (`buildOilServiceWhatsAppMessage`).

---

## المرحلة 7 — إعداد 10 محلات

لكل محل جديد:

1. أنشئ `instance` باسم `tenant_{uuid}`
2. صاحب المحل يمسح QR
3. جرّب رسالة اختبار
4. فعّل «إرسال تلقائي» في التطبيق

**لا تحتاج** workflow منفصل لكل محل — workflow واحد يخدم الجميع عبر `tenant_id`.

---

## الأمان (إنتاج)

| القاعدة | التفاصيل |
|---------|----------|
| أسرار API | DeepSeek + Evolution + Webhook — في n8n Variables فقط |
| HTTPS | إلزامي — لا Webhook عبر HTTP في الإنتاج |
| Webhook Secret | كل طلب من التطبيق يحمل سراً — n8n يرفض بدونه |
| tenant_id | من JWT الجلسة — لا يُقبل من العميل بحرية |
| Rate limit | 30 رسالة/يوم/متجر في البداية |
| تأخير | 10–20 ثانية عشوائي بين الرسائل في n8n |
| السجلات | احفظ: tenant_id, order_id, phone, status, timestamp |

---

## استكشاف الأخطاء

| المشكلة | الحل |
|---------|------|
| n8n لا يفتح | تحقق من المنفذ 5678 + حالة VPS |
| QR لا يظهر | أعد `instance/create` + `connect` |
| الجلسة انقطعت | أعد مسح QR — تنبيه في التطبيق |
| الرسالة لم تصل | تحقق من صيغة الرقم `9647...` |
| DeepSeek فشل | Fallback للقالب الثابت |
| حظر الرقم | قلّل الحجم، زِد التأخير، رقم مخصص للحملات |

---

## التكلفة الشهرية

| البند | التكلفة |
|-------|---------|
| Hostinger VPS KVM 2 | مشمول باشتراكك |
| DeepSeek | ~5$ (استخدام فعلي أقل) |
| Evolution + n8n | 0 |
| 10 محلات × ~200 رسالة | 0 رسوم واتساب |
| **الإجمالي** | **~5–10$/شهر** |

---

## خارطة التقدم

| المرحلة | الوصف | الحالة |
|---------|-------|--------|
| 0 | تحقق المتطلبات | ⬜ |
| 1 | تثبيت n8n | ⬜ |
| 2 | نطاق + HTTPS | ⬜ |
| 3 | Evolution API | ⬜ |
| 4 | ربط أول محل QR | ⬜ |
| 5 | Workflow n8n + DeepSeek | ⬜ |
| 6 | ربط Flutter | ⬜ |
| 7 | توسيع لـ 10 محلات | ⬜ |

---

## المراجع في المشروع

- قالب الرسالة الحالي: `lib/verticals/oil_change/utils/oil_service_whatsapp_message.dart`
- بعد الحفظ: `lib/verticals/oil_change/screens/oil_change_order_form_screen.dart` → `_afterOilChangeSaved`
- Docker Evolution: `infra/hostinger/docker-compose.evolution.yml`
- Workflow n8n: `infra/hostinger/n8n-oil-change-workflow.json`
