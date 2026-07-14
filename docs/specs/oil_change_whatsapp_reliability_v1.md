# موثوقية واتساب غيار الزيت — Spec v1.0

> **النطاق:** كل الاحتمالات التي قد تفشل + تنبيه المستخدم + ترتيب الرسائل  
> **الحالة:** مرحلة 1 مُنفَّذة جزئياً في Flutter — مرحلة 2/3 مخططة  
> **مرتبط بـ:** `oil_change_n8n_whatsapp_setup_guide_ar.md`

---

## 🎯 الهدف

1. **لا تضيع رسالة بصمت** — كل فشل يظهر للموظف برسالة عربية واضحة.
2. **تنبيه المالك** عند انقطاع واتساب المحل (QR / جلسة Evolution).
3. **ترتيب وعدم إغراق** — لا إرسال عشوائي سريع يُسبب حظر واتساب.
4. **Fallback آمن** — فتح `wa.me` يدوياً عند الفشل.

---

## 📊 مصفوفة الاحتمالات (ماذا يحدث؟)

| # | الحالة | من يكتشفها؟ | ماذا يرى الموظف؟ | ماذا يرى المالك؟ | Fallback |
|---|--------|-------------|------------------|------------------|----------|
| 1 | **نجاح** | n8n + Evolution | «تم إرسال رسالة واتساب للزبون تلقائياً» | — | لا |
| 2 | **لا إنترنت** على جهاز NaBoo | Flutter `connectivity_plus` | «لا يوجد اتصال… فتح يدوي» | — | wa.me |
| 3 | **انقطاع واتساب المحل** (QR انفصل) | Evolution → n8n `reason` | «واتساب المحل غير متصل — أعد QR» | بانر في السجل + FCM (مرحلة 3) | wa.me |
| 4 | **هاتف المحل مغلق/بدون نت** طويلاً | Evolution | نفس (3) | تنبيه المالك | wa.me |
| 5 | **سيرفر n8n متوقف** | HTTP 5xx / timeout | «خطأ مؤقت… يدوي» | مراقبة VPS | wa.me |
| 6 | **Evolution متوقف** | n8n JS2 error | «تعذّر الإرسال من رقم المحل» | بانر منفصل | wa.me |
| 7 | **سر Webhook خاطئ** | HTTP 401/403 | «فشل التحقق — تواصل مع دعم نابو» | — | لا (لا يُفتح wa) |
| 8 | **رقم زبون فارغ/خاطئ** | Flutter | «رقم غير صالح» | — | لا |
| 9 | **إرسال كثير سريع** (rate limit) | Evolution / Meta | «انتظر قليلاً» | — | wa.me لاحقاً |
| 10 | **DeepSeek بطيء/معطّل** | n8n (fallback نص ثابت) | الزبون يستلم رسالة (أبسط) | — | — |
| 11 | **حفظ بطاقة بدون «واتساب بعد الحفظ»** | إعداد محلي | لا شيء | — | لا |
| 12 | **تعديل بطاقة قديمة** (`isEdit`) | Flutter | لا إرسال تلقائي | — | لا |
| 13 | **حساب بدون إعداد Webhook** | Flutter config | «غير مُعدّ — يدوي» | — | wa.me |
| 14 | **عدة أجهزة لنفس الحساب** | — | نفس السلوك على الكل | حالة الاتصال **مزامَنة** (مرحلة 2 Supabase) | — |

---

## 🔔 تنبيه انقطاع واتساب المحل

### الآن (مرحلة 1 — مُنفَّذ)

| المكان | السلوك |
|--------|--------|
| بعد فشل الإرسال | SnackBar عربي حسب السبب |
| سجل غيار الزيت | **MaterialBanner** أحمر إذا الحالة `disconnected` |
| إعدادات الغيار | نص تحذيري تحت مفتاح واتساب |
| التخزين | `biz.oil.whatsapp_gateway_status` لكل tenant محلياً |

### لاحقاً (مرحلة 2–3)

```
Evolution (حدث CONNECTION_UPDATE)
    → Webhook n8n
    → Supabase tenant_whatsapp.status
    → كل أجهزة الحساب تقرأ «منفصل»
    → FCM للمالك: «واتساب محلك انفصل — أعد QR»
```

**قاعدة:** ربط QR **مرة واحدة للحساب** — ليس لكل جهاز NaBoo.

---

## 📬 ترتيب الرسائل وعدم الإغراق

### في n8n (مطلوب تحديث يدوي)

1. **انتظار 10–20 ثانية** عشوائياً بين DeepSeek والإرسال (موجود في workflow المستورد).
2. **لا أكثر من رسالة واحدة** لكل طلب Webhook (بطاقة واحدة = رسالة واحدة).
3. **Queue لاحقاً** إذا تجاوز 30 رسالة/ساعة لنفس instance → `rate_limited`.

### كود مقترح لعقدة WhatsApp (JS2) — يُرجع سبب الخطأ

```javascript
const prev = $input.first().json;
const instance = prev.instanceName || 'shop_basra_1';

let ok = false;
let reason = '';

try {
  await this.helpers.httpRequest({
    method: 'POST',
    url: `http://72.61.191.237:8080/message/sendText/${instance}`,
    headers: {
      apikey: 'Ev0_Naboo_...',
      'Content-Type': 'application/json',
    },
    body: { number: prev.phone, text: prev.message_text },
    json: true,
    timeout: 30000,
  });
  ok = true;
} catch (e) {
  const msg = (e.message || '').toLowerCase();
  if (msg.includes('disconnect') || msg.includes('not connected')) {
    reason = 'whatsapp_disconnected';
  } else if (msg.includes('timeout')) {
    reason = 'timeout';
  } else {
    reason = 'evolution_error';
  }
}

return [{ json: { ok, reason, sent_to: prev.phone } }];
```

### Respond to Webhook

```json
{
  "ok": {{ $json.ok }},
  "reason": "{{ $json.reason }}"
}
```

بهذا يفهم Flutter الفرق بين «الطلب وصل» و«واتساب فعلاً أُرسل».

---

## 📱 رسائل المستخدم (عربي)

| السبب | الرسالة |
|-------|---------|
| نجاح | تم إرسال رسالة واتساب للزبون تلقائياً |
| لا إنترنت | لا يوجد اتصال بالإنترنت — تم فتح واتساب يدوياً |
| واتساب منفصل | واتساب المحل غير متصل — أعد ربط QR من الإعدادات… |
| timeout | السيرفر لم يستجب… يدوي |
| rate limit | تم إرسال رسائل كثيرة — انتظر قليلاً |
| بانر السجل | واتساب المحل غير متصل — الرسائل التلقائية متوقفة… |

الكود: `oil_change_whatsapp_user_messages.dart`

---

## 🗂️ ملفات Flutter

| ملف | الدور |
|-----|------|
| `oil_change_whatsapp_notify_service.dart` | إرسال + تحديث الحالة |
| `oil_change_whatsapp_notify_classifier.dart` | تصنيف HTTP/JSON/شبكة |
| `oil_change_whatsapp_notify_outcome.dart` | نموذج النتيجة |
| `oil_change_whatsapp_user_messages.dart` | نصوص عربية |
| `oil_change_whatsapp_status_store.dart` | حالة connected/disconnected |
| `oil_change_order_form_screen.dart` | SnackBar + fallback |
| `oil_change_hub_screen.dart` | بانر + إعدادات |

---

## ✅ قائمة تحقق للمالك عند «واتساب منفصل»

1. افتح واتساب **هاتف المحل** — هل يعمل؟
2. الإعدادات → الأجهزة المرتبطة — هل NaBoo/Evolution ما زال مربوطاً؟
3. من تطبيق NaBoo (المالك) → أعد مسح QR (مرحلة 2).
4. جرّب حفظ بطاقة اختبار.

---

## 🛣️ خارطة الطريق

| مرحلة | المحتوى |
|-------|---------|
| **1** ✓ | تصنيف أخطاء + رسائل + بانر + fallback |
| **2** | Supabase حالة + مزامنة بين الأجهزة + شاشة QR |
| **3** | FCM للمالك + مراقبة Evolution webhook + queue معدّل |

---

*آخر تحديث: يوليو 2026*
