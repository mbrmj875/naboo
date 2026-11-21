# تقرير متكامل — نظام واتساب NaBoo (Evolution + Gateway + n8n)

**تاريخ التقرير:** 2026-07-25  
**الغرض:** توثيق ما بُني، كيف تنتقل البيانات، أين تقع مشكلة **فصل الجلسة**، ومقارنتها بمن يقول «Evolution عندي لا ينفصل أبداً».  
**تحذير فرع الكود:** على فرع العمل الحالي (`feature/snapshot-race-guard-v2`) النسخة في القرص **أنحف** من النسخة التي راقبناها على الإنتاج. النسخة الكاملة (send_text + تشخيص + أقفال) موجودة في commit/cloud agent مثل `f4625cb`. هذا التقرير يصف **النظام التشغيلي المقصود + ما رُصد حياً**.

---

## 1) الخلاصة التنفيذية

| السؤال | الجواب من المراقبة |
|--------|---------------------|
| هل Evolution «لا يرسل» والجلسة شغّالة؟ | **لا كأساس.** لما الجلسة `open` كان الإرسال `accepted/ok`. |
| هل الجلسة تنفصل لوحدها؟ | **نعم — هذه المشكلة الأساسية.** مثال العقيلي: `close` + `disconnectionReasonCode: 401` (= `loggedOut`). |
| هل المشكلة في «أساس الربط»؟ | **محتملة جزئياً:** إعداد Evolution (بدون Redis، hard reset متكرر، عدم تثبيت webhook دائماً، تعدد أسماء instance، حالة سحابية وهمية). لكن `401` نفسه قرار من واتساب بإلغاء الجهاز المرتبط. |
| لماذا شخص آخر «لا يواجه فصل»؟ | غالباً: محل واحد، رقم ثابت، لا يعيد QR/hard reset، هاتف لا يحذف الأجهزة المرتبطة، وربما نسخة/إعداد Evolution مختلف، أو استخدام أخف. |

**حكم فني:** مشكلة العقيلي الأخيرة = **فصل جلسة مرتبطة (401)** وليست عطل إرسال مع جلسة سليمة.

---

## 2) مكوّنات النظام (ما بنيتم)

```
┌─────────────────────┐
│  تطبيق Flutter      │  حساب Google لكل محل
│  (NaBoo / غيار زيت) │
└─────────┬───────────┘
          │
          ├─① ربط QR / حالة ──► Supabase Edge: whatsapp-gateway
          │                         │
          │                         ▼
          │                    Evolution API v2.3.7  (VPS Hostinger)
          │                         │
          ├─② إرسال تلقائي ──► (المسار الغني) whatsapp-gateway action=send_text
          │                         │
          │                    أو (احتياطي/قديم) n8n webhook oil-change-notify
          │                         │
          │                         ▼
          │              POST /message/sendText/{instance}
          │                         │
          │                         ▼
          │                   واتساب (جهاز مرتبط)
          │
          └─③ جداول Supabase: tenant_whatsapp_gateways (+ audit/diagnostics في النسخة الغنية)
```

### 2.1 البنية على السيرفر (Evolution)

**الملف:** `infra/hostinger/docker-compose.evolution.yml`

| بند | قيمة |
|-----|------|
| الصورة | `evoapicloud/evolution-api:v2.3.7` |
| الحاوية | `naboo-evolution` |
| قاعدة | Postgres 15 `naboo-evolution-db` |
| المنفذ | `8080` |
| التكامل | WHATSAPP-BAILEYS (من Edge عند provision) |
| Redis | **معطّل** (`CACHE_REDIS_ENABLED=false`) — كاش محلي فقط |
| بيانات الجلسات | volume `evolution_data` → `/evolution/instances` |

> ملاحظة أمنية: ملف الـ compose في المستودع يحتوي مفاتيح/كلمات مرور — يجب تدويرها وعدم اعتبارها سرّاً آمناً بعد ظهورها في git.

### 2.2 اسم الـ instance (قاعدة ذهبية)

```
shop_ + user_id مع استبدال كل - بـ _
```

أمثلة حية:
- العقيلي: `shop_cb89edb1_a4d2_45fb_9ed3_f30a14126d6b`
- باقر: `shop_c0e7d4af_2c54_419f_9e6d_1e23c0dcdc14`

**مخاطر تسمية قديمة في مسارات أخرى:**
- افتراضي Flutter قديم: `shop_basra_1`
- n8n قديم قد يبني `tenant_{tenantId}` إن نقص `instance_name`

أي اختلاف اسم = إرسال لمكان خاطئ أو «يبدو فاشلاً» بينما الجلسة الأخرى سليمة.

### 2.3 جداول Supabase

**أساسي (موجود في migrations):** `migrations/20260705_tenant_whatsapp_gateway.sql`

- `tenant_whatsapp_gateways(user_id, evolution_instance_name, status, whatsapp_phone, last_connected_at, last_disconnected_at, …)`
- RLS: صاحب الحساب فقط

**في النسخة الغنية (مُنفَّذة على الإنتاج وفق المراقبة):**
- `migrations/20260718_whatsapp_gateway_lock_audit.sql` → أعمدة قفل + `whatsapp_gateway_audit` + RPC قفل
- `migrations/20260722_whatsapp_diagnostic_events.sql` → صندوق أسود `whatsapp_diagnostic_events` (service_role)

---

## 3) مسار الربط (QR) — خطوة بخطوة

**الشاشة:** `OilChangeWhatsappConnectScreen`

1. المستخدم مسجّل Google على حساب المحل.
2. التطبيق يستدعي Edge `whatsapp-gateway` بـ `action: provision`
   - ينشئ instance على Evolution إن لم يوجد (`integration: WHATSAPP-BAILEYS`)
   - في النسخة الغنية: يضبط webhook لأحداث الاتصال (`ensureEvolutionWebhook`)
   - يحدّث السحابة: `status=connecting`
3. إن لم تكن متصلة: `action: qr` → Evolution `/instance/connect/{instance}` → QR (base64) و/أو pairing code.
4. المستخدم يمسح من واتساب الهاتف → أجهزة مرتبطة.
5. التطبيق يستطلع `action: status` كل ~4 ثوانٍ حتى `open` → `connected`.
6. يخزّن محلياً + في السحابة أن المحل متصل.

**إعادة الربط / فصل:**
- في النسخة الغنية يوجد `hardResetEvolutionSession` = logout + restart قبل QR جديد (مع حد معدّل وقفل).
- الإفراط في hard reset يزيد احتمال اضطراب الجلسة (وهذا فرق مهم عمن «يربط مرة ويترك»).

---

## 4) مسار الإرسال بعد حفظ بطاقة غيار الزيت

### 4.1 المسار التشغيلي الغني (ما رُصد في audit: `source=client_notify`)

```
حفظ البطاقة في Flutter
  → OilChangeWhatsappNotifyService
  → يفضّل: functions.invoke('whatsapp-gateway', action: send_text)
       ├─ يتحقق live state = open
       ├─ يمنع same_as_shop_phone (رقم الزبون = رقم الجلسة)
       ├─ اختياري: whatsappNumbers للتحقق من وجود الرقم
       ├─ POST Evolution /message/sendText/{instance}
       ├─ يكتب whatsapp_gateway_audit + whatsapp_diagnostic_events
       └─ يرد { ok, reason, sent_to, correlation_id, … }
  → إن فشل بوابة: احتياطي n8n (إن بقي مفعّلاً)
  → Classifier → رسالة عربية للمستخدم + تحديث StatusStore
```

### 4.2 منطق `send_text` الجوهري (من النسخة الغنية)

```typescript
// مختصر منطقي — ليس الملف كاملاً
action === 'send_text':
  phone = normalizeIraq(customer_phone)   // → 964…
  text  = message_text
  live  = readEvolutionLiveState(instance)
  if (!live.connected) return 409 whatsapp_disconnected / instance_removed

  shopDigits = owner من fetchInstances
  if (shopDigits === phone) return 400 same_as_shop_phone

  sent = evolutionSendText({ instance, phone, text })
  audit + diagnostic
  return { ok: sent.ok, … }
```

### 4.3 مسار n8n (احتياطي / قديم / بعض الفروع)

**Webhook:** `POST …/webhook/oil-change-notify`

عقد نموذجية (تختلف قليلاً بين ملفات المستودع):

1. **Webhook** يستقبل JSON من التطبيق  
2. **Validate Payload** — يطابق `webhook_secret` مع `$env.WEBHOOK_SECRET` (+ OLD أحياناً)  
3. يطبيع الهاتف إلى `964…` ويأخذ `instance_name` من الجسم  
4. **Build Message** — إما `message_text` من التطبيق أو توليد (DeepSeek في بعض النسخ)  
5. أحياناً **Wait 10–20s** (خطر مع timeout التطبيق 30s)  
6. **Evolution Send** — `POST …/message/sendText/{{instanceName}}` مع `apikey`  
7. **Respond** `{ ok: true/false, … }`

**عيوب n8n التاريخية التي عالجتموها جزئياً:**
- Respond كان يعيد نص تعبير خام `={{ $json.ok }}` → التطبيق يظن فشلاً/نجاحاً خاطئاً  
- منافذ/DNS الجوال إلى n8n قد تُحظر → لذلك فُضّل مسار HTTPS عبر Supabase Gateway  
- تجاهل `message_text` في بعض الـ workflows وإعادة كتابة الرسالة

---

## 5) أحداث الفصل والتشخيص

### 5.1 ما رُصد للعقيلي (مثال حي)

| وقت (تقريبي بغداد) | الحدث |
|--------------------|--------|
| 22:17 | instance اختفت/`404` ثم provision جديد |
| 22:18–22:26 | عدة `send_accepted` من رقم جلسة `9647783802009` |
| ~22:27 | `CONNECTION.UPDATE` + Evolution `close` + **reason 401** |
| لاحقاً | سحابة أحياناً `connected` وهمي بينما الحيّ `close` |
| اليوم ~16:26 | محاولة `provision/connecting` بدون إكمال مسح QR |

### 5.2 معنى 401

في Baileys/Evolution: **`401 = loggedOut`**  
= واتساب ألغى تفويض الجهاز المرتبط.  
لا يُعاد الاتصال تلقائياً (بخلاف 408/428). الحل: QR/رمز ربط من جديد.

أسباب شائعة: حذف الجهاز من الهاتف، تسجيل خروج، تعارض جلسات، hard reset متكرر، أو إلغاء من واتساب بعد أحداث بروتوكول (أحياناً بعد 515).

### 5.3 لماذا «شخص آخر لا ينفصل أبداً»؟

ليس دليلاً أن إعدادكم «خاطئ بالضرورة»، بل غالباً اختلاف بيئة:

| عامل | عندكم (متعدد محلات / تجربة مكثفة) | عنده (غالباً) |
|------|-----------------------------------|---------------|
| عدد الـ instances | عدة محلات على نفس Evolution | instance واحد |
| إعادة QR / hard reset | متكررة أثناء التشخيص | نادرة |
| Redis | معطّل عندكم في compose | قد يكون مفعّلاً |
| استخدام يدوي على الهاتف | حذف أجهزة مرتبطة / تبديل أرقام | ثابت |
| نسخة Evolution | v2.3.7 | قد تختلف |
| مراقبة دقيقة | ترون كل 401 | قد لا يلاحظ انقطاعاً قصيراً |

---

## 6) خريطة الملفات (مرجع)

### Infra
- `infra/hostinger/docker-compose.evolution.yml`
- `infra/hostinger/n8n-oil-change-workflow.json`
- `infra/hostinger/n8n-oil-change-campaign-workflow.json` (إن وُجد في الفرع الغني)
- `infra/hostinger/evolution-send-node.js`
- `infra/hostinger/n8n.env.example`
- `infra/hostinger/deploy-evolution-https.sh`

### Edge (نسخة غنية)
- `supabase/functions/whatsapp-gateway/index.ts` — actions: `provision|qr|status|report_disconnected|disconnect|send_text`
- `supabase/functions/whatsapp-gateway/evolution.ts` — fetch, webhook, hardReset, sendText, ownerDigits
- `supabase/functions/whatsapp-gateway/diagnostics.ts`
- `supabase/functions/whatsapp-events/index.ts` — webhooks Evolution + FCM/sweep
- `supabase/functions/whatsapp-disconnect-notify/index.ts`

### Flutter
- `lib/config/oil_change_whatsapp_config.dart`
- `lib/verticals/oil_change/services/oil_change_whatsapp_gateway_service.dart`
- `lib/verticals/oil_change/services/oil_change_whatsapp_gateway_repository.dart`
- `lib/verticals/oil_change/services/oil_change_whatsapp_notify_service.dart`
- `lib/verticals/oil_change/services/oil_change_whatsapp_status_store.dart`
- `lib/verticals/oil_change/screens/oil_change_whatsapp_connect_screen.dart`
- `lib/verticals/oil_change/utils/oil_change_whatsapp_notify_classifier.dart`

### Migrations
- `migrations/20260705_tenant_whatsapp_gateway.sql`
- `migrations/20260718_whatsapp_gateway_lock_audit.sql`
- `migrations/20260722_whatsapp_diagnostic_events.sql`

### أدوات دعم
- `admin-web/scripts/whatsapp-diagnose.mjs`
- `admin-web/scripts/whatsapp-webhook-backfill.mjs`

### وثائق سابقة
- `docs/specs/oil_change_whatsapp_reliability_v1.md`
- `docs/specs/oil_change_n8n_whatsapp_setup_guide_ar.md`

---

## 7) أين قد تكون «مشكلة أساس الربط/التثبيت»؟

مرتب حسب الأولوية العملية:

1. **بروتوكول الجهاز المرتبط نفسه** — أي Evolution Baileys معرض لـ 401؛ لا يوجد ضمان «أبداً لا ينفصل».  
2. **سلوك المحل على الهاتف** — حذف الأجهزة المرتبطة / تبديل رقم الجلسة.  
3. **Hard reset / مسح QR وهو متصل أو بعد كل خطأ** — يزعزع الجلسة.  
4. **حالة سحابية وهمية (`connected` بينما Evolution `close`)** — تضلل المستخدم فيعيد الربط بطريقة خاطئة.  
5. **Compose: Redis off + كاش محلي فقط** — قد يؤثر على استقرار بعض البيئات (يستحق مقارنة مع من «لا ينفصل»).  
6. **تعدد أسماء instance** (`shop_*` / `shop_basra_1` / `tenant_*`) — يخلق فشلاً يبدو كأنه Evolution.  
7. **انحراف الفرع:** بعض الأجهزة/الBuilds قد تكون على مسار n8n فقط بينما الإنتاج على Gateway — صعوبة تشخيص مزدوجة.  
8. **مفاتيح API غير متزامنة** بعد تدوير جزئي — 401 من Evolution API (مفتاح) يُخلط مع 401 loggedOut (جلسة).

---

## 8) قائمة فحص لخبير Evolution (أحمد أو غيره)

اطلب منه التحقق بالترتيب:

1. `GET /instance/connectionState/{instance}` و `fetchInstances` — `state` + `disconnectionReasonCode`  
2. هل webhook `CONNECTION_UPDATE` مضبوط ويحدّث السحابة فوراً؟  
3. هل تُنفَّذ `logout/restart` تلقائياً أكثر من اللازم؟  
4. مقارنة إعداد: Redis on/off، نسخة الصورة، عدد الـ instances  
5. هل نفس الرقم مربوط في مكانين (هاتف + سيرفرين)؟  
6. سجلات Docker عند لحظة 401: هل سبقها `515`؟  
7. عزل: instance تجريبي واحد، ربط مرة، إرسال يومي خفيف، **بدون** hard reset لأسبوع

---

## 9) ماذا نقول بصدق عن الحل؟

- **تثبيت أفضل لـ Evolution + انضباط تشغيل** يقلل الفصل؛ لا يلغيه 100٪ على مسار Baileys.  
- **مشكلة العقيلي الموثّقة** = فصل جلسة `401` بعد إرسال ناجح، وليست «Evolution لا يرسل».  
- من يدّعي «لا ينفصل أبداً» إما بيئة أبسط، أو لم يراقب بنفس دقة صندوقكم الأسود، أو يستخدم نمطاً مختلفاً (محل واحد / بدون إعادة ربط متكررة).

---

## 10) الحالة اللحظية عند كتابة التقرير (العقيلي)

- Evolution: **`close`**  
- سحابة: **`disconnected`** (بعد تصحيح سابق كانت وهمية connected)  
- يحتاج إكمال ربط QR من التطبيق ثم التحقق أن الحي يصبح **`open`**

---

*نهاية التقرير. للاستخدام الداخلي + مشاركة مع خبير Evolution بعد حذف أي أسرار من المرفقات.*
