# Naboo — خطة الدفع والاشتراك الشاملة | Master Plan v1.0

> **الوثيقة المرجعية الوحيدة لموضوع الدفع**  
> **Status:** خطة — لا تنفيذ في هذا المستند  
> **Updated:** 2026-06-16  
> **العملة الرسمية:** **الدينار العراقي (IQD) فقط** — لا دولار في الواجهة ولا في الفواتير  
> **قاعدة دائمة:** **واتساب يبقى متاحاً دائماً** كقناة بديلة بجانب أي بوابة دفع  

**يحل محل / يجمع:** `subscription_whatsapp_flow_v1.md`, `zaincash_auto_activation_v1.md`, `payment_gateways_iraq_v1.md` (للقراءة السريعة استخدم هذا الملف فقط).

---

## فهرس المحتويات

1. [الأهداف والمبادئ الثابتة](#1-الأهداف-والمبادئ-الثابتة)
2. [التسعير بالدينار العراقي](#2-التسعير-بالدينار-العراقي)
3. [نظرة عامة — ثلاث قنوات دفع](#3-نظرة-عامة--ثلاث-قنوات-دفع)
4. [القناة الدائمة: واتساب + تفعيل يدوي](#4-القناة-الدائمة-واتساب--تفعيل-يدوي)
5. [Zain Cash Payment Gateway v2](#5-zain-cash-payment-gateway-v2)
6. [FIB — المصرف العراقي الأول](#6-fib--المصرف-العراقي-الأول)
7. [المعمارية الموحدة والتفعيل التلقائي](#7-المعمارية-الموحدة-والتفعيل-التلقائي)
8. [واجهة المستخدم المستهدفة](#8-واجهة-المستخدم-المستهدفة)
9. [تدفق الإدارة (admin-web)](#9-تدفق-الإدارة-admin-web)
10. [البيانات — JWT و Supabase](#10-البيانات--jwt-و-supabase)
11. [الأمان](#11-الأمان)
12. [امتثال App Store و Google Play](#12-امتثال-app-store-و-google-play)
13. [واجهات API المقترحة](#13-واجهات-api-المقترحة)
14. [خارطة الطريق](#14-خارطة-الطريق)
15. [قوائم التقديم للتجار](#15-قوائم-التقديم-للتجار)
16. [معايير القبول](#16-معايير-القبول)
17. [مراجع الكود](#17-مراجع-الكود)

---

## 1. الأهداف والمبادئ الثابتة

### 1.1 الأهداف

| # | الهدف |
|---|--------|
| 1 | اشتراك مدفوع بسعر واضح بالدينار: **15,000 د.ع / حاسوب / شهر** |
| 2 | تجربة **15 يوم** مجانية (هاتف + حاسوب) — تلقائية بدون دفع |
| 3 | **واتساب دائماً** — لمن لا يستخدم المحافظ أو البنوك الرقمية |
| 4 | **Zain Cash + FIB** — دفع آلي + تفعيل JWT تلقائي (مراحل لاحقة) |
| 5 | امتثال سياسات Apple/Google — لا تجاوز IAP بشكل مخالف |

### 1.2 مبادئ لا تتغير

```
┌────────────────────────────────────────────────────────────┐
│  💰 العملة: IQD فقط — عرض، فواتير، بوابات دفع              │
│  📱 واتساب: قناة بديلة دائمة — لا تُزال أبداً               │
│  🔐 الأسرار: على الخادم فقط (admin-web)                    │
│  🎫 التفعيل: JWT RS256 — نفس نظام الترخيص v2 الحالي        │
│  🔄 التجديد/الترقية: JWT جديد دائماً — لا تعديل JWT قديم   │
└────────────────────────────────────────────────────────────┘
```

### 1.3 لماذا IQD فقط (وليس USD)

| السبب | التفصيل |
|-------|---------|
| بوابات العراق | Zain Cash و FIB يتعاملان بـ **IQD** |
| وضوح للعميل العراقي | «15,000 د.ع» أوضح من تحويل يومي |
| محاسبة | سجل واحد: `amount_iqd` لكل دفعة |
| استقرار الأرباح | مراجعة سعرية **ربع سنوية يدوية** — لا ربط تلقائي بسعر الصرف |

---

## 2. التسعير بالدينار العراقي

### 2.1 الوحدة

| العنصر | القيمة |
|--------|--------|
| سعر الوحدة | **15,000 د.ع / حاسوب / شهر** |
| الهاتف | **واحد مضمّن** — لا يُحسب في السعر |
| سقف الحاسبات | بدون حد (العميل يختار) |
| `max_devices` في JWT | `1 + عدد_الحاسبات` |

### 2.2 شهري (`monthly`)

```
السعر الشهري (د.ع) = عدد_الحاسبات × 15,000
```

| حاسبات | أجهزة (هاتف + حاسبات) | شهري (د.ع) |
|--------|------------------------|------------|
| 1 | 2 | 15,000 |
| 2 | 3 | 30,000 |
| 3 | 4 | 45,000 |
| N | N + 1 | N × 15,000 |

### 2.3 سنوي (`annual`)

```
السعر السنوي (د.ع) = السعر_الشهري × 10
الصلاحية          = 12 شهراً (ادفع 10 أشهر — شهران مجاناً)
```

| حاسبات | سنوي (د.ع) | الصلاحية |
|--------|------------|----------|
| 1 | 150,000 | 12 شهراً |
| 2 | 300,000 | 12 شهراً |
| N | N × 150,000 | 12 شهراً |

### 2.4 خطط legacy (تراخيص قديمة فقط)

| المفتاح | أجهزة | ملاحظة |
|---------|-------|--------|
| `basic` | 2 | لا تُعرض للعملاء الجدد |
| `pro` | 3 | لا تُعرض للعملاء الجدد |
| `unlimited` | 0 | غير محدود — legacy فقط |

### 2.5 عرض السعر في الواجهة

- دائماً: `{المبلغ} د.ع` مع فواصل آلاف عربية/غربية حسب `intl` و `ar_SA`
- لا رمز `$` ولا تحويل USD
- الملفات المرجعية: `lib/models/subscription_pricing.dart`, `admin-web/lib/plan-presets.ts`

---

## 3. نظرة عامة — ثلاث قنوات دفع

```
                    ┌─────────────────────┐
                    │   Naboo — خطط     │
                    │   (شهري/سنوي + N)   │
                    └──────────┬──────────┘
           ┌───────────────────┼───────────────────┐
           ▼                   ▼                   ▼
   ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
   │  📱 واتساب    │  │  Zain Cash    │  │     FIB       │
   │  دائماً ✅    │  │  Phase 2a     │  │   Phase 2b    │
   │  يدوي + JWT   │  │  آلي + JWT    │  │  آلي + JWT    │
   └───────┬───────┘  └───────┬───────┘  └───────┬───────┘
           │                  │                  │
           └──────────────────┼──────────────────┘
                              ▼
                   ┌─────────────────────┐
                   │  License JWT (RS256) │
                   │  تفعيل في التطبيق   │
                   └─────────────────────┘
```

| القناة | التفعيل | متى |
|--------|---------|-----|
| **واتساب** | إدارة تصدر JWT → العميل يلصق (أو يُرسل له) | **دائماً** |
| **Zain Cash** | تلقائي بعد `SUCCESS` | بعد تكامل Phase 2a |
| **FIB** | تلقائي بعد `SUCCESS` | بعد تكامل Phase 2b |

**تجربة 15 يوم:** لا تمر بأي قناة دفع — تفعيل تلقائي محلي.

---

## 4. القناة الدائمة: واتساب + تفعيل يدوي

> **هذه القناة لا تُلغى** عند تفعيل Zain Cash أو FIB. تبقى للعملاء الذين يفضّون التحويل اليدوي، أو عند عطل البوابة، أو لطلبات خاصة.

### 4.1 التدفق

```
تجربة 15 يوم (تلقائية)
        ↓
اختيار: شهري/سنوي + عدد حاسبات + ملخص بالدينار
        ↓
زر «تواصل للاشتراك عبر واتساب» (رسالة مُعبّأة)
        ↓
العميل يدفع يدوياً (ZainCash رقم / تحويل / FIB — خارج التطبيق)
        ↓
الإدارة: تأكيد الإيصال → إصدار JWT من admin-web
        ↓
العميل: يلصق JWT في حقل التفعيل (أو يستلمه على واتساب)
```

### 4.2 واجهة شاشة الاشتراك

**الملف:** `lib/screens/license/subscription_plans_screen.dart`

#### القسم 1 — التجربة المجانية
- 15 يوم — هاتف + حاسوب — مجاناً
- بدون واتساب

#### القسم 2 — بناء الاشتراك

```
┌─────────────────────────────────────────┐
│  اشتراك مدفوع                          │
├─────────────────────────────────────────┤
│  دورة الفوترة: ○ شهري  ○ سنوي         │
│  عدد الحاسبات: [ − ] [ 1 ] [ + ]       │
│  ─────────────────────────────────────  │
│  ملخص: هاتف + N حاسوب                  │
│  السعر: {X} د.ع / {شهر|سنة}            │
│  ─────────────────────────────────────  │
│  [ ادفع بـ Zain Cash ]    (Phase 2+)   │
│  [ ادفع بـ FIB ]          (Phase 2+)   │
│  [ 📱 تواصل عبر واتساب ]  (دائماً)     │
└─────────────────────────────────────────┘
```

- زر واتساب: `#25D366`
- بعد فتح واتساب: «بعد الدفع ستستلم رمز التفعيل»

#### القسم 3 — تفعيل JWT (يبقى دائماً)
- حقل لصق JWT (LTR)
- زر «تفعيل الرمز» → `LicenseService.activateSignedToken`
- **مطلوب حتى مع الدفع الآلي** — كاحتياطي إن فشل التفعيل التلقائي

### 4.3 قالب رسالة واتساب (عربي)

```
السلام عليكم،
أريد الاشتراك في Naboo:

👤 الاسم: {displayName}
📧 البريد: {email}
📦 الخطة: {شهري|سنوي}
💻 عدد الحاسبات: {N} (يشمل هاتفاً واحداً)
💰 المبلغ: {priceFormatted} د.ع / {شهر|سنة}
📱 الأجهزة: هاتف + {N} حاسوب

أرجو تأكيد طريقة الدفع وتفعيل الاشتراك.
شكراً.
```

### 4.4 فتح واتساب

- الرابط: `https://wa.me/9647884289711?text={urlEncodedMessage}`
- الرقم المرجعي: `07884289711` (عرض: `0780 428 9711`)

### 4.5 بيانات تُجمع تلقائياً

| الحقل | المصدر |
|-------|--------|
| الاسم | `AuthProvider.displayName` |
| البريد | Supabase Auth |
| دورة الفوترة | اختيار العميل |
| عدد الحاسبات | عداد الواجهة |
| السعر (د.ع) | `SubscriptionPlan.quote()` |

### 4.6 حالات خاصة

| الحالة | السلوك |
|--------|--------|
| غير مسجّل | توجيه لتسجيل الدخول قبل واتساب |
| لا بريد | حقل بريد إلزامي |
| ترقية نشط | «أريد ترقية من X إلى Y حاسوب» |
| تجديد منتهٍ | «أريد تجديد اشتراكي» |

### 4.7 رد الإدارة على واتساب

```
مرحباً {الاسم}،
المبلغ: {price} د.ع للاشتراك {شهري|سنوي} (هاتف + {N} حاسوب).

طرق الدفع:
• ZainCash: [رقم المحفظة]
• FIB تحويل: [تفاصيل]
• تحويل بنكي: [IBAN]

بعد التحويل أرسل لقطة الإيصال.
```

ثم إصدار JWT من admin-web وإرساله للعميل.

### 4.8 متى يُفضَّل واتساب على البوابة

- عميل لا يملك محفظة Zain أو تطبيق FIB
- مبلغ كبير / عدد حاسبات كبير — تفاوض يدوي
- عطل في بوابة الدفع
- **iOS App Store** — الاستفسار عبر واتساب مسموح؛ زر «ادفع هنا» قد لا يكون

---

## 5. Zain Cash Payment Gateway v2

**مرجع API:** Integration Guide v1.0 (22 Jan 2026)

### 5.1 روابط رسمية

| الغرض | الرابط |
|-------|--------|
| تقديم حساب تاجر | https://zaincash.iq/business/payment-gateway-faq |
| الوثائق البرمجية | https://docs.zaincash.iq/ |
| UAT | `https://pg-api-uat.zaincash.iq` |
| Production | يُسلَّم عند Onboarding |

### 5.2 تدفق الدفع (Zain Cash)

```
1. العميل يختار Zain Cash في Naboo
2. الخادم: POST /oauth2/token (client_credentials)
3. الخادم: POST /api/v2/payment-gateway/transaction/init
4. التطبيق يفتح redirectUrl (متصفح — لا iframe)
5. العميل يدفع + OTP
6. redirect → successUrl/failureUrl?token=JWT
7. Webhook (إنتاج) + Inquiry (احتياطي)
8. SUCCESS → إصدار JWT Naboo تلقائياً
```

### 5.3 OAuth2 — Get Access Token

```
POST /oauth2/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
client_id=...
client_secret=...
scope=payment:read payment:write reverse:write
```

### 5.4 Create Payment — transaction/init

| الحقل | مطلوب | Naboo |
|-------|--------|-------|
| `language` | نعم | `Ar` |
| `externalReferenceId` | نعم UUID | idempotency — فريد لكل محاولة |
| `orderId` | نعم | `naboo-{payment_uuid}` |
| `serviceType` | نعم | `NABOO_SUBSCRIPTION` (تأكيد مع ZainCash) |
| `amount.value` | نعم | السعر بالدينار (نص أو رقم) |
| `amount.currency` | نعم | `IQD` |
| `customer.phone` | اختياري | آخر محفظة ناجحة |
| `redirectUrls.successUrl` | نعم | HTTPS |
| `redirectUrls.failureUrl` | نعم | HTTPS |

**الرد:** `redirectUrl` — لا تُنشئه يدوياً.

### 5.5 حالات Zain Cash

| الحالة | معنى |
|--------|------|
| `SUCCESS` | دفع ناجح — أصدر JWT |
| `FAILED` | فشل |
| `PENDING` / `OTP_SENT` | انتظار |
| `EXPIRED` | انتهى وقت الجلسة |
| `REFUNDED` | استرداد |

### 5.6 Redirect Callback

- `successUrl?token=JWT` أو `failureUrl?token=JWT`
- تحقق JWT: **HS256 + API Secret Key**
- لا تثق بالبيانات دون تحقق التوقيع

### 5.7 Webhook (إنتاج فقط)

- `POST` إلى URL منفصل عن success/failure
- Body: `webhook_token` أو `token` (JWT)
- **لا يعمل في UAT** — في الاختبار: redirect + inquiry
- `eventId` — idempotency؛ HTTP 200 للمكرر

### 5.8 Inquiry (احتياطي)

```
GET /api/v2/payment-gateway/transaction/inquiry/{transactionId}
Authorization: Bearer {access_token}
```

### 5.9 Reverse (استرداد)

```
POST /api/v2/payment-gateway/transaction/reverse
{ "transactionId": "...", "reason": "..." }
```

Phase 3: ربط الاسترداد بتقصير `ends_at` في الترخيص.

### 5.10 بيانات اختبار UAT (من الوثائق)

**تاجر:** MSISDN `9647829744545` — Client ID/Secret من دليل ZainCash  
**عملاء:** محافظ اختبار + PIN `1111` + OTP `111111`

---

## 6. FIB — المصرف العراقي الأول

### 6.1 روابط رسمية

| الغرض | الرابط |
|-------|--------|
| بوابة المطورين | https://fib.iq/all-integrations/ |
| Web Payments | https://fib.iq/integrations/web-payments/ |
| Payment Gateway | https://fib.iq/fib-payment-gateway/ |
| QR Payments | https://fib.iq/qr-payments/ |
| حساب تاجر | https://fib.iq/business-corporate-account/ |
| SDK Flutter (GitHub) | https://github.com/First-Iraqi-Bank/fib-flutter-payment-sdk |
| pub.dev | https://pub.dev/packages/fib_iraq_payment |

### 6.2 ميزات FIB لـ Naboo

| الميزة | الفائدة |
|--------|---------|
| دفع عبر تطبيق FIB | QR + deep link — سريع على الجوال |
| بطاقات فيزا/ماستر | عملاء بدون محفظة Zain |
| رسوم إعداد | مجاناً (حسب إعلان البنك) |
| عمولة | ~0.5%–1.5% (تفاوض) |

### 6.3 تدفق FIB المقترح

```
1. POST /api/subscription/checkout?provider=fib
2. الخادم: createPayment(amount IQD, description, callbackUrl)
3. يرجع: paymentId, qrCode, personalAppLink, businessAppLink
4. التطبيق: عرض QR أو فتح تطبيق FIB
5. callback / poll checkPaymentStatus
6. SUCCESS → نفس Orchestrator → JWT
```

### 6.4 تحذير أمني — SDK Flutter

مثال `fib_iraq_payment` يضع `clientId` و `clientSecret` في التطبيق — **ممنوع في Naboo**.

| صحيح | خطأ |
|------|-----|
| إنشاء الدفع من **admin-web** | أسرار في `main.dart` |
| Flutter يعرض QR / يفتح رابط فقط | `createPayment` من العميل |

---

## 7. المعمارية الموحدة والتفعيل التلقائي

### 7.1 مخطط المعمارية

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter (واجهة فقط)                       │
│   اختيار: [واتساب] [Zain Cash] [FIB]                       │
└───────────────────────────┬─────────────────────────────────┘
                            │
┌───────────────────────────▼─────────────────────────────────┐
│              PaymentProvider (واجهة مجردة)                    │
│   startCheckout() · pollStatus() · provider: manual|zain|fib │
└───────┬─────────────────┬─────────────────┬───────────────────┘
        ▼                 ▼                 ▼
 ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
 │ ManualProvider│ │ZainProvider │  │ FibProvider │
 │ (واتساب)     │  │ (REST)      │  │ (REST)      │
 └──────┬──────┘  └──────┬──────┘  └──────┬──────┘
        │                └────────┬────────┘
        │                         ▼
        │              ┌──────────────────────┐
        │              │ Payment Orchestrator  │
        │              │ تحقق مبلغ + idempotency│
        │              └──────────┬───────────┘
        │                         │ SUCCESS (بوابات فقط)
        ▼                         ▼
 ┌─────────────┐         ┌──────────────────────┐
 │ admin يدوي  │         │ License Issuer (JWT)  │
 │ license-issue│         │ نفس RS256 الحالي      │
 └──────┬──────┘         └──────────┬───────────┘
        │                           │
        └─────────────┬─────────────┘
                      ▼
           LicenseService.activateSignedToken
```

### 7.2 جدول `subscription_payments`

| العمود | الوصف |
|--------|--------|
| `id` | UUID |
| `tenant_id` | عزل المستأجر |
| `user_id` | `auth.uid()` |
| `provider` | `manual` \| `zaincash` \| `fib` \| `whatsapp` |
| `order_id` | معرّف Zain/FIB |
| `external_reference_id` | idempotency |
| `provider_transaction_id` | transactionId / paymentId |
| `billing_cycle` | monthly \| annual |
| `computers` | int |
| `amount_iqd` | **int — دينار فقط** |
| `currency` | `IQD` ثابت |
| `status` | انظر أدناه |
| `license_id` | بعد التفعيل |
| `customer_wallet_msisdn` | من callback ناجح |
| `paid_at` | timestamptz |

**حالات:** `checkout_created` → `awaiting_customer` → `paid` | `failed` | `activation_error`

### 7.3 شروط إصدار JWT التلقائي

1. `provider` = zaincash أو fib
2. حالة البوابة = `SUCCESS`
3. `amount` في callback = `amount_iqd` المسجّل
4. لم يُصدر `license_id` لنفس الدفع
5. استدعاء منطق `license-issue`:
   - `max_devices` = `1 + computers`
   - `ends_at` = +30 يوم (شهري) أو +365 (سنوي)
   - **تجديد:** من `max(now, current_ends_at)`

### 7.4 إيصال التفعيل للتطبيق

| الآلية | الاستخدام |
|--------|-----------|
| Poll `GET /api/subscription/payments/{id}` | موصى به |
| Supabase Realtime على `licenses` | فوري |
| Deep link `naboo://subscription/complete?paymentId=` | بعد صفحة success |
| لصق JWT يدوي | **احتياطي دائم** |

---

## 8. واجهة المستخدم المستهدفة

### 8.1 ترتيب الأزرار (من الأعلى للأأسفل)

1. **ادفع بـ Zain Cash** — عند توفر Phase 2a (Desktop / ويب)
2. **ادفع بـ FIB** — عند توفر Phase 2b
3. **تواصل عبر واتساب** — **دائماً ظاهر**
4. **تفعيل برمز (JWT)** — **دائماً ظاهر**

### 8.2 شاشات مرتبطة

| الملف | الدور |
|-------|--------|
| `subscription_plans_screen.dart` | خطط + دفع + JWT |
| `account_subscription_screen.dart` | حالة الاشتراك + رابط الخطط |

---

## 9. تدفق الإدارة (admin-web)

### 9.1 تحديد العميل

**المفتاح:** بريد Google من واتساب أو من جلسة الدفع.

| التبويب | الاستخدام |
|---------|-----------|
| المستخدمون | أول اشتراك — UUID |
| التراخيص | تجديد / ترقية |
| بحث عام | بريد، UUID، جهاز |

`tenant_id` في JWT = UUID المستخدم في Supabase.

### 9.2 إصدار JWT v2 (يدوي — واتساب)

1. تبويب التراخيص → «إصدار ترخيص v2»
2. `tenant_id`, `plan`, `max_devices`, `ends_at`
3. إرسال JWT للعميل على واتساب

### 9.3 إصدار JWT (آلي — بوابات)

نفس الحقول — يُستدعى من Orchestrator داخلياً بعد `SUCCESS`.

### 9.4 ترقية / تجديد

| العملية | JWT |
|---------|-----|
| ترقية | جديد — `max_devices` أكبر |
| تجديد | جديد — `ends_at` أبعد |

---

## 10. البيانات — JWT و Supabase

| حقل JWT | الوصف |
|---------|--------|
| `tenant_id` | UUID مستخدم |
| `plan` | monthly \| annual |
| `max_devices` | 1 + computers |
| `ends_at` | نهاية الصلاحية |
| `assigned_user_id` | في `licenses` — مطابقة `auth.uid()` |

**فرض الحد:** `app_user_max_devices()` في Supabase.

---

## 11. الأمان

| # | قاعدة |
|---|--------|
| 1 | أسرار Zain/FIB في env الخادم فقط |
| 2 | تحقق كل JWT callback (Zain: HS256 + API key) |
| 3 | Idempotency — `externalReferenceId`, `eventId` |
| 4 | مطابقة `amount_iqd` قبل إصدار الترخيص |
| 5 | HTTPS لكل redirect و webhook |
| 6 | RLS على `subscription_payments` |
| 7 | Audit log — بدون JWT كامل أو أسرار |
| 8 | تنبيه `activation_error` (دفع ناجح، فشل JWT) |
| 9 | لا iframe لـ Zain |
| 10 | لا `client_secret` في Flutter — حتى مع FIB SDK |

---

## 12. امتثال App Store و Google Play

### مسموح

- تجربة 15 يوم
- زر **«تواصل للاشتراك»** / واتساب (استفسار)
- JWT بعد دفع خارج التطبيق
- Desktop: بوابات دفع
- **واتساب دائماً**

### ممنوع (خاصة iOS)

- «سعر أرخص خارج التطبيق»
- زر «ادفع بالتحويل» داخل تطبيق المتجر لاشتراك رقمي
- تجاوز IAP بشكل مخالف

### التوصية حسب المنصة

| المنصة | Zain/FIB | واتساب |
|--------|----------|--------|
| Desktop | ✅ داخل التطبيق | ✅ |
| Android | صفحة ويب checkout | ✅ |
| iOS | Safari → checkout.naboo.io | ✅ |

---

## 13. واجهات API المقترحة

| Method | Path | الغرض |
|--------|------|--------|
| POST | `/api/subscription/checkout` | `?provider=zaincash\|fib` |
| GET | `/api/subscription/payments/{id}` | حالة الدفع |
| GET | `/api/subscription/payments/{id}/license` | JWT للتفعيل (مرة، مصادقة) |
| GET | `/payment/success` | redirect Zain |
| GET | `/payment/failure` | redirect Zain |
| POST | `/api/zaincash/webhook` | إنتاج |
| POST | `/api/fib/webhook` | callback FIB |
| POST | `/api/internal/subscription/reconcile` | ops |

**لا `license-issue` عام بدون تحقق دفع** (البوابات) أو صلاحية admin (واتساب).

---

## 14. خارطة الطريق

| المرحلة | المحتوى | واتساب |
|---------|---------|--------|
| **Phase 1** | واتساب + JWT يدوي + تسعير IQD | ✅ أساسي |
| **Phase 2a** | Zain Cash v2 + تفعيل آلي | ✅ يبقى |
| **Phase 2b** | FIB + تفعيل آلي | ✅ يبقى |
| **Phase 2c** | الثلاثة معاً + checkout ويب | ✅ يبقى |
| **Phase 3** | استرداد، تقارير، إشعارات | ✅ يبقى |

### Phase 2a — Zain Cash (تفصيل)

- [ ] جداول Supabase + RLS
- [ ] Checkout API + OAuth + init
- [ ] Redirect + Orchestrator + license-issue
- [ ] Inquiry cron (UAT)
- [ ] Flutter Desktop + poll + تفعيل آلي
- [ ] **واتساب + JWT يدوي — بدون تغيير**

### Phase 2b — FIB

- [ ] نفس Orchestrator مع `provider=fib`
- [ ] QR / deep link في Flutter
- [ ] **واتساب — بدون تغيير**

### Phase 2c — إنتاج

- [ ] Webhook Zain (prod)
- [ ] credentials FIB prod
- [ ] `checkout.naboo.io` للجوال

---

## 15. قوائم التقديم للتجار

### Zain Cash
- [ ] https://zaincash.iq/business/payment-gateway-faq
- [ ] `client_id`, `client_secret`, API key
- [ ] UAT: `pg-api-uat.zaincash.iq`
- [ ] Webhook URL (prod) مع فريق Business

### FIB
- [ ] https://fib.iq/business-corporate-account/
- [ ] `client_id`, `client_secret`
- [ ] مراجعة https://fib.iq/integrations/web-payments/

---

## 16. معايير القبول

### واتساب (دائم)
- [ ] زر واتساب يفتح رسالة مُعبّأة بالدينار
- [ ] حقل JWT يعمل بعد الإصدار اليدوي
- [ ] يبقى متاحاً بعد تفعيل Zain/FIB

### Zain Cash
- [ ] دفع UAT 15,000 د.ع — JWT تلقائي
- [ ] لا ترخيص مكرر (idempotency)
- [ ] فشل OTP — لا JWT

### FIB
- [ ] دفع stage — JWT تلقائي
- [ ] أسرار على الخادم فقط

### عام
- [ ] كل الأسعار بالدينار فقط
- [ ] RTL + اختبار ثلاث مقاسات

---

## 17. مراجع الكود

| الملف | الدور |
|-------|--------|
| `lib/screens/license/subscription_plans_screen.dart` | واجهة الخطط |
| `lib/services/license_service.dart` | `quote()`, `activateSignedToken` |
| `lib/models/subscription_pricing.dart` | معادلات IQD |
| `admin-web/lib/plan-presets.ts` | خطط admin |
| `admin-web/app/api/actions/license-issue/route.ts` | إصدار JWT |

---

## ملخص تنفيذي (للمالك)

1. **العملة:** دينار عراقي فقط — 15,000 د.ع / حاسوب / شهر.  
2. **واتساب:** قناة دائمة — لا تُزال أبداً.  
3. **Zain Cash ثم FIB:** دفع آلي + تفعيل فوري — على Desktop والويب أولاً.  
4. **JWT:** نفس نظام الترخيص الحالي — يدوي (واتساب) أو آلي (بوابات).  
5. **الأمان:** أسرار على الخادم؛ تحقق كل callback؛ مطابقة المبلغ بالدينار.

---

*آخر تحديث: 2026-06-16 — الوثيقة المرجعية الوحيدة لدفع Naboo.*
