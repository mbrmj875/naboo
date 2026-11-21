# بوابات الدفع العراقية — Zain Cash + FIB | Spec v1.0

> **⚠️ مُدمَج في الوثيقة الشاملة:** [`naboo_payment_master_plan_v1.md`](./naboo_payment_master_plan_v1.md) — استخدمها كمرجع وحيد لموضوع الدفع.

> **Status: Plan only — لا تنفيذ**  
> **Updated: 2026-06-16**  
> **Scope: Naboo — مقارنة، روابط رسمية، دمج مزدوج، تسعير IQD، أمان**  
> **يرتبط بـ:** `docs/specs/zaincash_auto_activation_v1.md`, `docs/specs/subscription_whatsapp_flow_v1.md`

---

## 1. الروابط الرسمية — Zain Cash

| الغرض | الرابط |
|-------|--------|
| **تقديم حساب تاجر** | [zaincash.iq/business/payment-gateway-faq](https://zaincash.iq/business/payment-gateway-faq) |
| **الوثائق البرمجية (API v2)** | [docs.zaincash.iq](https://docs.zaincash.iq/) |
| **UAT API** | `https://pg-api-uat.zaincash.iq` |
| **خطة التفعيل التلقائي في Naboo** | `docs/specs/zaincash_auto_activation_v1.md` |

**ملاحظة للمطور:** التكامل الكامل موثّق في دليل v2 (OAuth2 + `transaction/init` + redirect JWT + webhook). Webhook **لا يعمل في UAT**.

---

## 2. الروابط الرسمية — FIB (First Iraqi Bank)

| الغرض | الرابط |
|-------|--------|
| **بوابة المطورين / التكاملات** | [fib.iq/all-integrations/](https://fib.iq/all-integrations/) |
| **Web Payments** | [fib.iq/integrations/web-payments/](https://fib.iq/integrations/web-payments/) |
| **Payment Gateway (عام)** | [fib.iq/fib-payment-gateway/](https://fib.iq/fib-payment-gateway/) |
| **QR Payments** | [fib.iq/qr-payments/](https://fib.iq/qr-payments/) |
| **حساب شركات / تاجر** | [fib.iq/business-corporate-account/](https://fib.iq/business-corporate-account/) |
| **SDK Flutter (GitHub رسمي)** | [github.com/First-Iraqi-Bank/fib-flutter-payment-sdk](https://github.com/First-Iraqi-Bank/fib-flutter-payment-sdk) |
| **حزمة pub.dev (مجتمعية)** | [pub.dev/packages/fib_iraq_payment](https://pub.dev/packages/fib_iraq_payment) |

---

## 3. مقارنة سريعة — Zain Cash vs FIB

| المعيار | Zain Cash v2 | FIB Payment Gateway |
|---------|--------------|---------------------|
| **جمهور العراق** | محافظ زين — انتشار واسع | تطبيق بنكي رقمي + بطاقات فيزا/ماستر |
| **طريقة الدفع** | Redirect + OTP على صفحة Zain | QR + deep link لتطبيق FIB + بطاقات |
| **تكامل Flutter** | **خادم فقط** (REST + redirect) — لا SDK رسمي في التطبيق | SDK Flutter موجود — **لكن الأسرار يجب أن تبقى على الخادم** |
| **Webhook** | نعم (إنتاج فقط) | callback URL (تحقق من وثائق FIB) |
| **رسوم الإعداد** | حسب العقد | مجاناً حسب ما يُعلَن للتجار |
| **عمولة تقريبية** | حسب العقد | ~0.5%–1.5% (تفاوض) |
| **ملاءمة Naboo Desktop** | ✅ ممتاز | ✅ جيد (QR على شاشة كبيرة) |
| **ملاءمة Naboo Mobile** | ✅ redirect | ✅ فتح تطبيق FIB |
| **نضج حزمة pub.dev** | N/A (server-side) | `fib_iraq_payment` ^0.0.2 — **منخفض التحميل**؛ يُفضَّل GitHub الرسمي أو API مباشرة من الخادم |

**التوصية:** التقديم على **الاثنين بالتوازي**. لا تعتمد على بوابة واحدة في العراق.

---

## 4. معمارية مزدوجة (Clean Architecture — خطة فقط)

```
                    ┌─────────────────────────┐
                    │  Flutter (واجهة فقط)   │
                    │  اختيار: Zain | FIB    │
                    └───────────┬─────────────┘
                                │
                    ┌───────────▼─────────────┐
                    │  PaymentProvider (abstract) │
                    │  startCheckout()          │
                    │  pollStatus()             │
                    └───────────┬─────────────┘
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
     ┌────────────────┐ ┌──────────────┐ ┌──────────────────┐
     │ ZainCashProvider│ │ FibProvider  │ │ ManualProvider   │
     │ (server API)    │ │ (server API) │ │ (WhatsApp — Phase1)│
     └────────┬─────────┘ └──────┬───────┘ └──────────────────┘
              │                  │
              └────────┬─────────┘
                       ▼
            ┌──────────────────────┐
            │ Payment Orchestrator │
            │ (تحقق + idempotency)│
            └──────────┬───────────┘
                       ▼ SUCCESS
            ┌──────────────────────┐
            │ License Issuer (JWT)   │
            └──────────────────────┘
```

### جدول `subscription_payments` (توسيع)

| عمود إضافي | القيمة |
|------------|--------|
| `provider` | `zaincash` \| `fib` \| `manual` |
| `provider_transaction_id` | `transactionId` أو `paymentId` |
| `provider_payload` | jsonb للتدقيق (بدون أسرار) |

**مبدأ واحد لكل البوابات:** Flutter لا يحمل `client_secret` — حتى لو وثائق FIB SDK تعرضه في المثال.

---

## 5. تدفق FIB المقترح (متوازٍ لـ Zain Cash)

| خطوة | FIB | Zain Cash |
|------|-----|-----------|
| 1 | `POST /api/subscription/checkout?provider=fib` | `provider=zaincash` |
| 2 | الخادم يستدعي FIB create payment | الخادم OAuth + init |
| 3 | يرجع `qrCode` + `personalAppLink` + `paymentId` | يرجع `redirectUrl` |
| 4 | التطبيق يعرض QR أو يفتح رابط FIB | يفتح redirect في متصفح |
| 5 | callback / poll status | redirect JWT + webhook + inquiry |
| 6 | `SUCCESS` → إصدار JWT Naboo | نفس المنطق |

---

## 6. التسعير: دينار عراقي فقط (لا دولار في الواجهة)

### القرار الموصى به لـ Naboo

| البند | القرار |
|-------|--------|
| **عملة العرض** | **IQD فقط** في التطبيق والفواتير والمتاجر |
| **التسعير الداخلي** | `15,000 د.ع / حاسوب / شهر` (موجود في `subscription_pricing`) |
| **لماذا لا USD؟** | بوابتا Zain وFIB تتعاملان بـ **IQD**؛ عرض الدولار يضيف تقلب سعر صرف ومتطلبات قانونية/ضريبية |
| **استقرار الأرباح** | راجع السعر **ربع سنوياً** بالدينار؛ لا ربط تلقائي بسعر الصرف في Phase 2 |
| **App Store** | لا تعرض مقارنة «أرخص خارج التطبيق» — انظر `subscription_whatsapp_flow_v1.md` |
| **الفوترة** | احتفظ بسجل: `amount_iqd`, `provider`, `paid_at` لكل دفعة |

### عند ارتفاع سعر الصرف

- قرار تجاري: زيادة سعر الدينار (مثلاً 15,000 → 17,000) بإصدار جديد — **ليس** تحويل تلقائي يومي.

---

## 7. أمان الدفع (ملخص تنفيذي)

| # | قاعدة |
|---|--------|
| 1 | **أسرار البوابة على الخادم فقط** — لا `client_secret` في Flutter ولا في git |
| 2 | **تحقق كل callback** — Zain: HS256 + API key؛ FIB: حسب وثائقهم |
| 3 | **Idempotency** — لا ترخيص مكرر لنفس الدفع |
| 4 | **مطابقة المبلغ** — مبلغ البوابة = `amount_iqd` المسجّل |
| 5 | **HTTPS** لكل redirect وwebhook |
| 6 | **RLS** — المستخدم يرى مدفوعاته فقط |
| 7 | **Audit log** — بدون JWT كامل أو أسرار |
| 8 | **تنبيه ops** — حالة `activation_error` (دفع ناجح، فشل JWT) |
| 9 | **لا iframe** لـ Zain (ممنوع رسمياً) |
| 10 | **اختبار UAT** بمحافظ الاختبار قبل الإنتاج |

---

## 8. خارطة طريق مقترحة

| المرحلة | Zain Cash | FIB | WhatsApp |
|---------|-----------|-----|----------|
| **Phase 1 (حالي)** | رقم محفظة يدوي | — | ✅ |
| **Phase 2a** | تكامل v2 كامل + تفعيل JWT | — | بديل |
| **Phase 2b** | — | تكامل + تفعيل JWT | بديل |
| **Phase 2c** | ✅ | ✅ | احتياطي |

**البدء الموصى به:** Zain Cash 2a (الوثائق لديك كاملة) → FIB 2b بالتوازي مع طلب حساب تاجر.

---

## 9. قائمة تقديم للتاجر (افعلها الآن)

### Zain Cash
- [ ] تقديم عبر [payment-gateway-faq](https://zaincash.iq/business/payment-gateway-faq)
- [ ] طلب `client_id`, `client_secret`, API key, `serviceType`
- [ ] اختبار UAT على `pg-api-uat.zaincash.iq`
- [ ] تسجيل Webhook URL (إنتاج) مع فريق Business

### FIB
- [ ] فتح [business-corporate-account](https://fib.iq/business-corporate-account/)
- [ ] طلب `client_id`, `client_secret` + بيئة `stage`/`prod`
- [ ] مراجعة [web-payments](https://fib.iq/integrations/web-payments/)
- [ ] تقييم SDK الرسمي vs REST من الخادم

---

## 10. إجابة سؤالك: ماذا نناقش لاحقاً؟

| الموضوع | التوصية المختصرة |
|---------|-------------------|
| **IQD vs USD** | **IQD فقط** في المنتج؛ مراجعة سعرية دورية يدوية |
| **أمان الدفع** | الخادم يملك الأسرار؛ webhook + تحقق مبلغ؛ انظر §7 |
| **الدمج المزدوج** | `PaymentProvider` abstraction — §4 |
| **Flutter SDK FIB** | استخدمه للـ UX (QR) فقط إن لزم؛ **إنشاء الدفع من الخادم** |

---

## 11. مراجع

- `docs/specs/zaincash_auto_activation_v1.md`
- `docs/specs/subscription_whatsapp_flow_v1.md`
- `lib/models/subscription_pricing.dart`
- `admin-web/lib/plan-presets.ts`
