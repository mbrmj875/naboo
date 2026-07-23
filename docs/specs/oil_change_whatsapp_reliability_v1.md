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
| **2** ✓ | Supabase حالة + مزامنة بين الأجهزة + شاشة QR |
| **3** | FCM للمالك + مراقبة Evolution webhook + queue معدّل |

---

# 🔧 سجل التشغيل والتشخيص (Operational Log)

> هذا القسم يوثّق ما توصّلنا إليه فعلياً على السيرفر الحيّ حتى **21 يوليو 2026**.
> الهدف: مرجع واحد لكل مشاكل واتساب، أسبابها، حلولها، وما تبقّى مفتوحاً.

## 🏗️ البنية الحالية (كيف تُرسَل الرسالة الآن؟)

تغيّر المسار جذرياً عمّا في الأعلى. **لم نعد نعتمد على n8n :5678 كمسار أساسي.**

```
تطبيق Flutter (بيانات جوّال أو Wi-Fi)
    │  HTTPS 443 (يعمل على كل الشبكات)
    ▼
Supabase Edge Function: whatsapp-gateway
    │  action: send_text  (JWT فقط — instance من الـ JWT، منع IDOR)
    ▼
Evolution API  (https://evo-nrwn.srv1769126.hstgr.cloud خلف Traefik)
    │
    ▼
WhatsApp (الجهاز المرتبط = هاتف المحل الذي مسح QR)
```

- **الأساسي:** التطبيق ينادي Supabase Gateway مباشرة عبر HTTPS.
- **Fallback:** إذا فشلت البوابة يجرّب التطبيق webhook n8n القديم.
- **سبب التغيير:** شبكات الجوّال تحجب المنفذ `5678` غير القياسي؛ HTTPS/443 لا يُحجب.

### مكوّنات السيرفر

| المكوّن | العنوان | الدور |
|---------|---------|------|
| Evolution API | `https://evo-nrwn.srv1769126.hstgr.cloud` | إرسال/ربط واتساب (Baileys) |
| Supabase Function | `whatsapp-gateway` | بوابة HTTPS آمنة بين التطبيق وEvolution |
| n8n | `https://n8n-nrwn.srv1769126.hstgr.cloud` | مسار fallback + الحملات |
| اسم الـ instance | `shop_<user_id بشرطات سفلية>` | جلسة واتساب لكل حساب (tenant) |

### ملفات السيرفر (Deno / Edge Functions)

| ملف | الدور |
|-----|------|
| `supabase/functions/whatsapp-gateway/index.ts` | المعالج: provision / qr / status / disconnect / report_disconnected / **send_text** |
| `supabase/functions/whatsapp-gateway/evolution.ts` | نداءات Evolution: حالة، QR، reset، **evolutionSendText**، تطبيع الأرقام، جلب رقم الجلسة |

### جداول Supabase

| جدول | الدور |
|------|------|
| `tenant_whatsapp_gateways` | حالة الجلسة لكل حساب (status / phone / آخر اتصال / آخر reset) |
| `whatsapp_gateway_audit` | سجل تدقيق لكل عملية (send_text / hard_reset / بلاغات الفصل) |

---

## ✅ المشاكل التي واجهناها والحلول (مُنجَزة)

| # | المشكلة | السبب الجذري | الحل المُطبَّق |
|---|---------|--------------|----------------|
| 1 | الرسائل لا تصل على **بيانات الجوّال** بينما تعمل على Wi-Fi | شبكات الجوّال تحجب منفذ n8n `5678` | تحويل المسار الأساسي إلى **Supabase Gateway عبر HTTPS/443** |
| 2 | «السيرفر لم يستجب» ثم لا شيء | n8n يُرجع body فارغ / JSON غير صالح عند `order_id` نصّي | إصلاح عقدة `Respond OK` لإنتاج JSON صالح دائماً |
| 3 | تأخّر/فشل الإرسال مع مرفق PDF | Evolution يُرجع HTTP 400 / تأخّر كبير مع PDF | **إرسال نصّي فقط** — إزالة مرفق PDF من الإشعار |
| 4 | انقطاع QR بسبب endpoint معلّق | `/instance/connect` علِق | إعادة تشغيل Evolution + منطق reset محكوم بمعدّل |
| 5 | HTTP بدل HTTPS لـ Evolution | لا شهادة TLS | Evolution خلف Traefik بـ HTTPS + إغلاق المنفذ 8080 العام |
| 6 | `SQLITE_READONLY` في n8n | صلاحيات ملف | إصلاح صلاحيات SQLite |
| 7 | بلاغات «واتساب منفصل» كاذبة | التطبيق يبلّغ فصلاً والجلسة مفتوحة | التحقق الحيّ من Evolution: `false_alarm` بدل كتابة «منفصل» |
| 8 | **إرسال لرقم المحل نفسه يُسجَّل «ناجح» وهو فاشل** | `connectionState` لا يُرجع رقم الجلسة فتفشل الحماية | جلب رقم الجلسة من `fetchInstances` (ownerJid) + منع + audit — **مُنفَّذ 21 يوليو** |

---

## 🧪 نتائج التشخيص الحيّ (21 يوليو 2026)

فُحص حساب «العكيلي» (`shop_cb89edb1…`, الجلسة مربوطة بالرقم `9647884289711`).

### قاعدة التسليم المؤكَّدة من السجلات

| نوع وجهة الرسالة | مثال | النتيجة الفعلية |
|------------------|------|-----------------|
| **رقم هاتف** `@s.whatsapp.net` (زبون حقيقي) | `9647783802009` | ✅ تصل وتُقرأ (`DELIVERY_ACK`/`READ`) |
| **رقم هاتف = رقم المحل نفسه** | `9647884289711` | ❌ `ERROR` (إرسال للنفس مستحيل) |
| **عنوان LID** `@lid` | `55921313062937@lid` | الحالة `NONE` في سجل Evolution |

- 23 رسالة إلى أرقام هاتف حقيقية → وصلت (عدا رقم المحل نفسه).
- 25 رسالة إلى عناوين `@lid` ظهرت في سجل Evolution بحالة `NONE`.

### تحقق مصدر `@lid` (22 يوليو 2026) — قرار: لا نبني كشف `@lid`

السؤال: هل أي رسالة `@lid` فاشلة خرجت من مسار نابو الآلي (webhook n8n / gateway `send_text` برقم هاتف)؟

| المصدر | الدليل | النتيجة |
|--------|--------|---------|
| **Supabase Gateway `send_text`** (مسار التطبيق الأساسي) | 24 صف تدقيق لحساب العكيلي في نافذة المشكلة — كل `remote_jid` كان `@s.whatsapp.net`، **صفر** `@lid` | المسار الآلي لم يستهدف `@lid` |
| **n8n Oil Change webhook** | تنفيذ واحد فقط في نفس النافذة (`id=347`، `2026-07-21 19:02:19`) — أُجهِض بـ `missing_field: instance_name` قبل أي نداء Evolution؛ لا `@lid` في البيانات | n8n لم يُرسل أصلاً |
| رسائل `@lid` بنص يدوي (أسعار، روابط…) | محتوى غير قالب نابو | إرسال يدوي من الهاتف / لوحة Evolution |
| رسائل `@lid` بنص قالب نابو بنفس ثانية رسالة هاتف ناجحة | مثال: `18:53` هاتف→`DELIVERY_ACK` + `@lid`→`NONE` لنفس النص | ظلّ تخزين مزدوج في Evolution لنفس الإرسال الناجح إلى رقم الهاتف — **ليست محاولة إرسال فاشلة مستقلة** |

**القرار:** لا نبني كشف/تنبيه `@lid` في التطبيق الآن. المشكلة التشغيلية الظاهرة للمستخدم في تلك الليلة كانت إرسال لرقم المحل نفسه + فصل/ربط متكرر، وليست فشل مسار نابو عبر `@lid`.

---

## ⚠️ المشاكل المفتوحة الآن (غير محلولة بالكامل)

### 1) قيد `@lid` (خصوصية واتساب) — قيد خارجي / مراقبة فقط

- **الأعراض في سجل Evolution:** محادثات/مفاتيح `@lid` قد تظهر بحالة `NONE`.
- **التحقق (22 يوليو):** مسار نابو الآلي يرسل برقم هاتف ويُسجَّل `remote_jid` هاتفياً؛ ظهور `@lid` في الأرشيف كان يدوياً أو ظلاً لرسالة هاتف ناجحة.
- **القرار الحالي:** مراقبة فقط — **لا كشف ولا تنبيه في التطبيق** حتى يظهر دليل أن مساراً آلياً فشل بسبب `@lid`.
- ترقية Evolution/Baileys تبقى خياراً مستقبلياً منفصلاً إن تكررت أعراض تسليم حقيقية على المسار الآلي.

### 2) انقطاع الجلسة المفاجئ (الجهاز المرتبط)

- **الأعراض:** ينفصل QR فجأة ويطلب إعادة ربط.
- **السبب:** جلسة Evolution = «جهاز مرتبط» بواتساب. يطرده واتساب عند:
  1. استخدام نفس الواتساب يدوياً بكثافة على الهاتف بالتزامن.
  2. الفصل/إعادة الربط المتكرر (رُصد 10 مرات/يومين لحساب واحد).
  3. تكرار خطأ `stream error 515` (فشل استقرار الجلسة بعد المسح).
- **الحالة:** سلوك طبيعي للأجهزة المرتبطة — ليس عطلاً في السيرفر. يُخفَّف بالسلوك لا بالكود.
- **إرشاد المستخدم:** بعد الربط لا تُكثر الاستخدام اليدوي على الهاتف، ولا تُعِد الربط بلا داعٍ.

### 3) «ok» من البوابة ≠ «سُلِّمت» — مُعالَج جزئياً بصندوق التشخيص

- البوابة تُرجع `ok` عند قبول Evolution (HTTP 200).
- صندوق التشخيص يتتبع لاحقاً `delivered`/`read`/`error` عبر `whatsapp-events`، ويعلّم `none_timeout` بعد 15 دقيقة بلا تحديث.
- أداة `whatsapp:diagnose` تعرض الخلاصة دون اعتبار HTTP 200 نجاحاً نهائياً.

---

## 🩺 أوامر تشخيص سريعة (للدعم)

```bash
# حالة جلسة حساب
curl -s -H "apikey: $EVO_KEY" \
  "$EVO/instance/connectionState/shop_<uid>"

# هل الرقم على واتساب؟
curl -s -H "apikey: $EVO_KEY" -H 'Content-Type: application/json' \
  -d '{"numbers":["9647xxxxxxxxx"]}' \
  "$EVO/chat/whatsappNumbers/shop_<uid>"

# آخر الرسائل الصادرة وحالتها (PHONE=يصل، LID=لا يصل)
curl -s -H "apikey: $EVO_KEY" -H 'Content-Type: application/json' \
  -d '{"where":{"key":{"fromMe":true}},"limit":50}' \
  "$EVO/chat/findMessages/shop_<uid>"
```

سجل التدقيق في Supabase: جدول `whatsapp_gateway_audit` (فلترة بـ `user_id`).

---

## 🩺 صندوق أسود التشخيص (يوليو 2026)

> بلا شاشة مستخدم. السجل للدعم فقط عبر `service_role` + أمر محلي.

### القاعدة الذهبية
**HTTP 200 من البوابة ≠ تسليم.** النجاح النهائي فقط `delivered` / `read`. الحالات `accepted` / `server_ack` تعني «قُبلت» فقط حتى يأتي تحديث أو `none_timeout` بعد 15 دقيقة.

### الجدول
`whatsapp_diagnostic_events` — migration: `migrations/20260722_whatsapp_diagnostic_events.sql`  
حقول مهمة: `correlation_id`, `provider_message_id`, `shop_phone`, `recipient_phone`, `recipient_jid_type` (`phone|lid|unknown`), `outcome`, `reason_code`, `suggested_action`.  
**لا** يُخزَّن نص الرسالة / QR / tokens. احتفاظ 90 يوماً عبر `prune_whatsapp_diagnostic_events`.

### مصادر الأحداث
| المصدر | ماذا يكتب |
|--------|-----------|
| `whatsapp-gateway` | provision / QR / فصل / send_attempt / send_accepted |
| `whatsapp-events` | CONNECTION_UPDATE + MESSAGES_UPDATE + إنذار FCM عند فصل عفوي |
| `whatsapp-events` action=`sweep` | `none_timeout` للرسائل المعلقة +15د بلا delivered/error |
| `whatsapp-disconnect-notify` | فصل + FCM + سطر تشخيص |

### قاموس outcomes مختصر
`accepted` · `server_ack` · `delivered` · `read` · `error` · `none_timeout` · `same_as_shop_phone` · `invalid_phone` · `disconnected` · `removed`

### تشغيل التشخيص
```bash
cd admin-web
npm run whatsapp:diagnose -- --email user@gmail.com
npm run whatsapp:diagnose -- --phone 07715948175
npm run whatsapp:diagnose -- --lid-stats
```
اختياري في `.env.local`: `EVOLUTION_API_KEY` لفحص الحالة الحية.

### ضبط webhook للجلسات الحالية (مرة واحدة)
```bash
cd admin-web
# بعد تعيين WHATSAPP_EVENTS_WEBHOOK_SECRET في Supabase secrets و .env.local
npm run whatsapp:webhook-backfill
```

### مسح none_timeout (كل ~10 دقائق)
```bash
curl -s -X POST "$SUPABASE_URL/functions/v1/whatsapp-events" \
  -H "Content-Type: application/json" \
  -H "x-webhook-secret: $WHATSAPP_EVENTS_WEBHOOK_SECRET" \
  -d '{"action":"sweep"}'
```

### مقاييس LID أسبوعية
`select * from whatsapp_lid_failure_stats(7);` (service_role) أو `--lid-stats` في أمر التشخيص.

---

*آخر تحديث: 22 يوليو 2026 — صندوق أسود التشخيص + none_timeout + إنذار فصل + تتبع LID.*
