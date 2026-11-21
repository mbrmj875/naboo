# Zain Cash v2 — دفع + تفعيل تلقائي | Spec v1.0

> **⚠️ مُدمَج في الوثيقة الشاملة:** [`naboo_payment_master_plan_v1.md`](./naboo_payment_master_plan_v1.md) — استخدمها كمرجع وحيد لموضوع الدفع.

> **Status: Plan only — لا تنفيذ في هذا المستند**  
> **Version: 1.0**  
> **Updated: 2026-06-16**  
> **Scope: Naboo — اشتراك مدفوع عبر Zain Cash Payment Gateway v2 مع إصدار JWT تلقائي**  
> **مرجع API:** Zain Cash Merchant Payment Gateway Integration Guide v1.0 (22 Jan 2026)  
> **يرتبط بـ:** `docs/specs/subscription_whatsapp_flow_v1.md`, `docs/specs/payment_gateways_iraq_v1.md`, `admin-web/app/api/actions/license-issue/route.ts`, `lib/services/license_service.dart`

### روابط رسمية (Zain Cash)

| الغرض | الرابط |
|-------|--------|
| تقديم حساب تاجر | https://zaincash.iq/business/payment-gateway-faq |
| الوثائق البرمجية | https://docs.zaincash.iq/ |
| مقارنة مع FIB + دمج مزدوج | `docs/specs/payment_gateways_iraq_v1.md` |

---

## 1. الهدف

استبدال (أو استكمال) التدفق اليدوي:

```
اختيار خطة → واتساب → دفع يدوي → إدارة تصدر JWT → العميل يلصق JWT
```

بتدفق آلي:

```
اختيار خطة → دفع Zain Cash → تأكيد تلقائي → إصدار JWT → تفعيل فوري في التطبيق
```

**مصدر الحقيقة للدفع:** Webhook (إنتاج) + Inquiry (احتياطي).  
**مصدر الحقيقة للتفعيل:** صف `licenses` في Supabase + JWT موقّع RS256 (نفس آلية v2 الحالية).

---

## 2. مبادئ معمارية (غير قابلة للتفاوض)

| # | المبدأ |
|---|--------|
| 1 | **لا أسرار ZainCash في Flutter** — `client_id`, `client_secret`, API key للتحقق من JWT تبقى على الخادم فقط (`admin-web` أو Edge Functions). |
| 2 | **لا ثقة بالـ redirect وحده** — تحقق JWT بـ HS256 + API key؛ في الإنتاج اعتمد Webhook؛ استخدم Inquiry عند الشك. |
| 3 | **Idempotency** — `externalReferenceId` فريد لكل محاولة دفع؛ `eventId` في Webhook يُعالَج مرة واحدة فقط. |
| 4 | **لا iframe** — فتح `redirectUrl` في متصفح النظام / Chrome Custom Tab / Safari (حسب المنصة). |
| 5 | **المبلغ بالدينار (IQD)** — عدد صحيح؛ يطابق `SubscriptionPlan.quote()` في Flutter. |
| 6 | **JWT الترخيص** — يُصدَر بنفس `license-issue` المنطق الحالي (RS256, `tenant_id`, `plan`, `max_devices`, `ends_at`). |
| 7 | **امتثال المتاجر** — الدفع الرقمي داخل تطبيق iOS/Android المنشور قد يخالف سياسات Apple/Google؛ الخطة تفصل «أين» يُعرض زر الدفع (انظر §8). |

---

## 3. البيئات Zain Cash

| البيئة | Base URL | ملاحظات |
|--------|----------|---------|
| UAT (اختبار) | `https://pg-api-uat.zaincash.iq` | بيانات اختبار من الوثائق؛ **Webhook غير مدعوم** |
| Production | يُسلَّم عند Onboarding | Webhook يُسجَّل عبر فريق ZainCash Business |

**Scopes مطلوبة:** `payment:read payment:write reverse:write`

---

## 4. المكوّنات في Naboo

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  Flutter App    │────▶│  Checkout API        │────▶│  Zain Cash v2   │
│  (اختيار خطة)   │     │  (admin-web / API)   │     │  PG API         │
└────────┬────────┘     └──────────┬───────────┘     └────────┬────────┘
         │                         │                          │
         │                         │◀──── redirect + webhook ─┘
         │                         ▼
         │              ┌──────────────────────┐
         │              │  Payment Orchestrator │
         │              │  (تحقق + idempotency)│
         │              └──────────┬───────────┘
         │                         │ SUCCESS
         │                         ▼
         │              ┌──────────────────────┐
         └─────────────▶│  license-issue       │
           (تفعيل)      │  + Supabase licenses │
                        └──────────────────────┘
```

| المكوّن | الدور | ملاحظة |
|---------|------|--------|
| **Flutter** | عرض الخطة، السعر، بدء الدفع، استقبال التفعيل | لا يتصل بـ ZainCash مباشرة |
| **Checkout API** | OAuth2 token، `transaction/init`، تخزين طلب معلّق | `admin-web/app/api/...` |
| **Redirect handlers** | `successUrl` / `failureUrl` — UX فقط | صفحة ويب عربية |
| **Webhook handler** | `POST` + `webhook_token` JWT | إنتاج فقط |
| **Inquiry job** | استعلام دوري للطلبات `PENDING` | UAT + احتياطي |
| **License issuer** | إعادة استخدام منطق `license-issue` | داخلي — ليس endpoint عام |
| **Supabase** | `subscription_payments`, `licenses`, `profiles` | RLS حسب `tenant_id` / `auth.uid()` |

---

## 5. نموذج البيانات (مقترح)

### 5.1 جدول `subscription_payments`

| العمود | النوع | الوصف |
|--------|------|--------|
| `id` | UUID PK | معرّف داخلي |
| `tenant_id` | UUID | من جلسة المستخدم |
| `user_id` | UUID | `auth.uid()` — مالك الحساب |
| `order_id` | text UNIQUE | يُرسل لـ ZainCash كـ `orderId` (مثلاً `naboo-{uuid}`) |
| `external_reference_id` | UUID UNIQUE | idempotency key لـ ZainCash |
| `zain_transaction_id` | UUID nullable | من `transaction/init` |
| `billing_cycle` | `monthly` \| `annual` | |
| `computers` | int | عدد الحاسبات |
| `amount_iqd` | int | المبلغ المحسوب |
| `currency` | text | `IQD` |
| `status` | enum | انظر §5.3 |
| `zain_status` | text nullable | آخر حالة من البوابة |
| `license_id` | int nullable FK → `licenses.id` | بعد التفعيل |
| `customer_wallet_msisdn` | text nullable | من JWT نجاح الدفع (للدفعات التالية) |
| `paid_at` | timestamptz nullable | |
| `expires_checkout_at` | timestamptz | من `expiryTime` في init |
| `created_at` | timestamptz | |

### 5.2 جدول `subscription_payment_events` (idempotency)

| العمود | الوصف |
|--------|--------|
| `event_id` | من Webhook/redirect JWT — UNIQUE |
| `payment_id` | FK |
| `payload_hash` | للتدقيق |
| `processed_at` | |

### 5.3 حالات الطلب الداخلية

| الحالة الداخلية | معنى | إجراء |
|-----------------|------|--------|
| `checkout_created` | طُلِب init ولم يُدفع بعد | انتظار |
| `awaiting_customer` | `PENDING` / `OTP_SENT` / `CUSTOMER_AUTHENTICATION_REQUIRED` | انتظار |
| `paid` | `SUCCESS` مؤكد | إصدار JWT |
| `failed` | `FAILED` / `EXPIRED` | إغلاق؛ السماح بمحاولة جديدة |
| `refunded` | `REFUNDED` | إبطال/تقصير الترخيص (سياسة لاحقة) |
| `activation_error` | دفع ناجح لكن فشل إصدار JWT | تنبيه ops + إعادة محاولة آلية |

---

## 6. تدفق الدفع والتفعيل (تفصيلي)

### المرحلة A — بدء الدفع (من التطبيق)

1. المستخدم مسجّل دخول (Google / OTP) وله `tenant_id`.
2. يختار: شهري/سنوي + عدد حاسبات → التطبيق يعرض السعر من `SubscriptionPlan.quote()` محلياً (للعرض فقط).
3. التطبيق يستدعي:  
   `POST /api/subscription/checkout`  
   Body: `{ billingCycle, computers }`  
   Headers: جلسة Supabase (Bearer).
4. الخادم:
   - يتحقق من المستخدم و`tenant_id`.
   - يحسب `amount_iqd` (نفس معادلات `subscription_pricing`).
   - ينشئ `subscription_payments` بحالة `checkout_created`.
   - يولّد `externalReferenceId` (UUID جديد).
   - يحصل على OAuth2 token (`POST /oauth2/token`).
   - يستدعي `POST /api/v2/payment-gateway/transaction/init`:
     - `language`: `Ar` (تطبيق Naboo `ar_SA`)
     - `serviceType`: قيمة ثابتة متفق عليها (مثلاً `NABOO_SUBSCRIPTION`)
     - `orderId`: من الجدول
     - `amount`: `{ value: "<int>", currency: "IQD" }`
     - `customer.phone`: اختياري — من آخر دفع ناجح في `profiles` أو `subscription_payments` (انظر best practices ZainCash)
     - `redirectUrls.successUrl` / `failureUrl`: على نطاقك (HTTPS)
   - يحفظ `zain_transaction_id`, `expires_checkout_at`, `redirectUrl`.
5. الرد للتطبيق: `{ paymentId, redirectUrl, amountIqd, expiresAt }`.
6. التطبيق يفتح `redirectUrl` في **متصفح خارجي** (ليس WebView مخفي).

### المرحلة B — دفع العميل (Zain Cash)

7. العميل يكمل الدفع + OTP على صفحة Zain Cash.
8. Zain Cash يعيد التوجيه إلى:
   - `successUrl?token=<JWT>` أو `failureUrl?token=<JWT>`

### المرحلة C — معالجة Redirect (UX)

9. صفحة `success` / `failure` على الخادم:
   - تتحقق من JWT بـ **API Secret Key + HS256**.
   - تستخرج: `transactionId`, `orderId`, `currentStatus`, `amount`, `customerMsisdn`.
   - تستدعي داخلياً **Payment Orchestrator** (نفس منطق Webhook).
   - تعرض للمستخدم صفحة عربية:
     - نجاح: «تم الدفع — جارٍ تفعيل اشتراكك…» + زر «العودة للتطبيق»
     - فشل: سبب مختصر + «حاول مرة أخرى»

### المرحلة D — Webhook (إنتاج — مصدر الحقيقة)

10. `POST /api/zaincash/webhook` — body: `{ "webhook_token": "<JWT>" }` أو `{ "token": "..." }` (حسب ما يرسله ZainCash فعلياً — توحيد عند التنفيذ).
11. تحقق JWT + idempotency على `eventId`.
12. عند `currentStatus === SUCCESS`:
    - انتقل إلى **المرحلة E**.
13. عند `FAILED` / `EXPIRED`: حدّث `subscription_payments.status`.

### المرحلة E — التفعيل التلقائي (إصدار JWT)

14. **شروط الإصدار (كلها مطلوبة):**
    - حالة ZainCash = `SUCCESS`
    - المبلغ في JWT = `amount_iqd` المسجّل (تحمل فرق 0)
    - `orderId` يطابق صف `subscription_payments`
    - لم يُصدر `license_id` مسبقاً لنفس الدفع (idempotency)
15. استدعاء منطق إصدار الترخيص (مكافئ `license-issue`):
    - `tenant_id` من الطلب
    - `assigned_user_id` = `user_id`
    - `plan` = `monthly` | `annual`
    - `max_devices` = `1 + computers`
    - `ends_at` = الآن + 30 يوم (شهري) أو + 365 يوم (سنوي)
    - **ترقية/تجديد:** JWT **جديد** دائماً (لا تعديل JWT قديم)
16. حفظ `license_jwt` في `licenses` + ربط `subscription_payments.license_id`.
17. تحديث `profiles.zain_wallet_msisdn` من `customerMsisdn` (اختياري — للدفعات التالية).
18. تحديث `subscription_payments.status = paid`.

### المرحلة F — إيصال التفعيل للتطبيق

اختر **واحداً** (موصى به: B + C):

| خيار | الآلية | ملاحظة |
|------|--------|--------|
| **A** | Deep link `naboo://subscription/complete?paymentId=...` | الصفحة success تفتح الرابط |
| **B** | التطبيق ي poll `GET /api/subscription/payments/{id}` كل 2–3 ثوانٍ بعد العودة | بسيط وآمن |
| **C** | Supabase Realtime على `licenses` حيث `assigned_user_id = uid` | فوري بدون poll |
| **D** | `activateSignedToken(jwt)` مباشرة في الرد — **غير موصى به** | لا تمرّر JWT الترخيص في URL |

**التفعيل في Flutter:**

19. عند `paid` + وجود `license_jwt` جاهز:
    - الخادم يعيد JWT **مرة واحدة** عبر endpoint محمي بالجلسة، أو
    - التطبيق يستدعي `LicenseService.activateSignedToken(jwt)` بعد جلب JWT من API.
20. رسالة نجاح عربية + تحديث `LicenseService` state — **بدون لصق يدوي**.

### المرحلة G — Inquiry (احتياطي)

21. Cron كل 1–5 دقائق (أو بعد redirect مباشرة):
    - `GET /api/v2/payment-gateway/transaction/inquiry/{transactionId}`
    - للطلبات `checkout_created` / `awaiting_customer` الأقدم من دقيقتين.
22. UAT: **الاعتماد الأساسي على redirect + inquiry** (لا Webhook).

---

## 7. حساب السعر وربط الخطة

| المدخل | المصدر | ZainCash |
|--------|--------|----------|
| `computers` | واجهة المستخدم | — |
| `billingCycle` | شهري/سنوي | — |
| `amount_iqd` | `computers × 15_000` (شهري) أو `× 150_000` (سنوي) | `amount.value` |
| `max_devices` | `1 + computers` | — |
| `orderId` | `naboo-{payment_uuid}` | `orderId` |
| `externalReferenceId` | `payment.id` | idempotency |

**الحد الأدنى:** تأكد من سياسة ZainCash للمبالغ الصغيرة (وثائق قديمة ذكرت 250 د.ع — تحقق مع UAT).

---

## 8. امتثال المتاجر (iOS / Android / Desktop)

| المنصة | ما يُسمح | التوصية |
|--------|----------|---------|
| **Windows / macOS Desktop** | زر «ادفع بـ Zain Cash» داخل التطبيق | ✅ المرحلة الأولى للتنفيذ |
| **Android (Play)** | تجنب بيع اشتراك رقمي ببوابة خارجية **داخل** التطبيق إن كان يخالف سياسة Google | عرض «إدارة الاشتراك على الويب» أو فتح `checkout.naboo.io` |
| **iOS (App Store)** | لا IAP bypass واضح | **لا زر دفع داخل التطبيق** — رابط «تجديد الاشتراك» يفتح Safari لصفحة ويب |
| **ويب** | صفحة checkout كاملة | ✅ الأنسب للجوال أيضاً |

**Phase 2a (مقترح):** Desktop + صفحة ويب للجوال.  
**Phase 2b:** توحيد تجربة الجوال عبر PWA checkout.  
**الاحتفاظ بـ WhatsApp** كقناة بديلة للعملاء الذين لا يستخدمون Zain Cash.

---

## 9. واجهات API (مقترح — admin-web)

| Method | Path | الغرض |
|--------|------|--------|
| POST | `/api/subscription/checkout` | إنشاء دفع + إرجاع `redirectUrl` |
| GET | `/api/subscription/payments/{id}` | حالة الدفع + هل JWT جاهز |
| GET | `/api/subscription/payments/{id}/license` | جلب JWT للتفعيل (مرة واحدة، مصادقة) |
| GET | `/payment/success` | redirect handler |
| GET | `/payment/failure` | redirect handler |
| POST | `/api/zaincash/webhook` | إشعارات ZainCash (prod) |
| POST | `/api/internal/subscription/reconcile` | ops — inquiry يدوي |

**لا endpoint عام لـ `license-issue` بدون تحقق دفع.**

---

## 10. الأمان

| البند | الإجراء |
|-------|---------|
| أسرار ZainCash | `ZAINCASH_CLIENT_ID`, `ZAINCASH_CLIENT_SECRET`, `ZAINCASH_API_KEY` في env الخادم فقط |
| OAuth token | cache في الذاكرة مع `expires_in` − هامش 60 ثانية |
| تحقق JWT ZainCash | HS256 + API key؛ رفض إن فشل التوقيع |
| JWT الترخيص | RS256 — المفتاح الخاص لا يغادر الخادم (كما هو اليوم) |
| RLS | المستخدم يرى `subscription_payments` الخاصة بـ `tenant_id` فقط |
| تسجيل | audit log: `payment_id`, `event_id`, `zain_transaction_id` — **بدون** أسرار أو JWT كامل في اللوغ |
| Replay | `event_id` UNIQUE؛ تجاهل المكرر بـ HTTP 200 |

---

## 11. التجديد والترقية

| السيناريو | السلوك |
|-----------|--------|
| **تجديد** | دفع جديد → JWT جديد بـ `ends_at` ممتد (من تاريخ الانتهاء الحالي أو من الآن — **قرار:** من `max(now, current_ends_at)`) |
| **ترقية حاسبات** | دفع بفرق السعر أو دفع كامل دورة جديدة — **قرار Phase 2:** دفع كامل دورة جديدة فقط (أبسط) |
| **فشل الدفع** | الطلب `failed`؛ المستخدم يبدأ checkout جديد بـ `externalReferenceId` جديد |
| **استرداد (reverse)** | يدوي من Merchant Dashboard أو API — **Phase 3:** تقصير `ends_at` أو `revoked` في `licenses` |

---

## 12. مراحل التنفيذ المقترحة

### Phase 2.1 — Backend + UAT (2–3 أسابيع)

- [ ] جداول Supabase + RLS
- [ ] Checkout API + OAuth + init
- [ ] Redirect handlers (صفحات عربية)
- [ ] Orchestrator + idempotency
- [ ] ربط `license-issue` الداخلي
- [ ] Inquiry cron
- [ ] اختبار UAT بمحافظ الاختبار من الوثائق

### Phase 2.2 — Desktop Flutter (1 أسبوع)

- [ ] زر «ادفع بـ Zain Cash» في `subscription_plans_screen`
- [ ] فتح `redirectUrl` + poll حالة الدفع
- [ ] `activateSignedToken` تلقائي
- [ ] إخفاء/تقليل لصق JWT اليدوي (يبقى للطوارئ)

### Phase 2.3 — صفحة ويب checkout (1 أسبوع)

- [ ] `checkout.naboo.io` — نفس API، مناسب لـ iOS/Android (Safari/Chrome)
- [ ] deep link للعودة للتطبيق

### Phase 2.4 — Production (بعد Onboarding ZainCash)

- [ ] بيانات prod + `serviceType` رسمي
- [ ] تسجيل Webhook URL مع فريق ZainCash
- [ ] مراقبة + تنبيهات (فشل activation_error)
- [ ] Merchant Dashboard كنسخة احتياطية للتسوية

### Phase 2.5 — تحسينات

- [ ] حفظ `customer_wallet_msisdn` لتجربة دفع أسرع
- [ ] إشعار push/email «تم تفعيل اشتراكك»
- [ ] تقارير admin-web: مدفوعات / إيراد / فشل

---

## 13. اختبار القبول (Acceptance)

| # | السيناريو | النتيجة المتوقعة |
|---|-----------|------------------|
| 1 | checkout شهري — 1 حاسوب — UAT نجاح | JWT صالح، `max_devices=2`, `ends_at` +30 يوم |
| 2 | نفس `externalReferenceId` مرتين | لا ترخيص مكرر |
| 3 | Webhook مكرر بنفس `eventId` | معالجة مرة واحدة |
| 4 | redirect نجاح لكن inquiry لا يزال PENDING | انتظار حتى SUCCESS أو EXPIRED |
| 5 | مبلغ JWT ≠ المسجل | رفض التفعيل + `activation_error` |
| 6 | مستخدم B يحاول جلب JWT لدفع مستخدم A | 403 |
| 7 | فشل OTP | `failureUrl` + لا JWT |
| 8 | Desktop: دورة كاملة بدون لصق يدوي | ✅ |
| 9 | iOS: فتح Safari → دفع → عودة للتطبيق | تفعيل تلقائي |

---

## 14. مخاطر وقرارات مفتوحة

| # | الموضوع | خيارات | توصية |
|---|---------|--------|--------|
| 1 | بداية `ends_at` عند التجديد | من الآن vs من انتهاء الحالي | من `max(now, current_ends_at)` |
| 2 | ترقية الحاسبات | دفع فرق vs دورة كاملة | دورة كاملة في v1 |
| 3 | مكان Checkout API | admin-web فقط vs Supabase Edge | admin-web (يوجد `license-issue`) |
| 4 | إبقاء واتساب | نعم/لا | نعم — بديل |
| 5 | `serviceType` | قيمة داخلية | `NABOO_SUBSCRIPTION` — تأكيد مع ZainCash |
| 6 | Webhook body shape | `token` vs `webhook_token` | توحيد عند أول تكامل prod |

---

## 15. مراجع داخل المشروع

- `docs/specs/subscription_whatsapp_flow_v1.md` — التسعير والقيود
- `admin-web/app/api/actions/license-issue/route.ts` — إصدار JWT
- `admin-web/lib/plan-presets.ts` — خطط وأسعار
- `lib/models/subscription_pricing.dart` — معادلات Flutter
- `lib/services/license_service.dart` — `activateSignedToken`

---

*هذا المستند خطة فقط. التنفيذ يبدأ بموافقة صريحة على Phase 2.1.*
