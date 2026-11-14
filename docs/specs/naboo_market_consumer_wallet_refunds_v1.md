# Naboo Market — محفظة المستهلك · الإلغاء · الاسترداد
## Consumer Wallet & Refunds Master Plan v1.0

> **الحالة:** تخطيط — **لا كود**  
> **التاريخ:** 2026-06-20  
> **العملة:** IQD — تخزين داخلي `int fils` · عرض «**رصيد نابو**» أو «**نقاط**» (1 نقطة = 1 د.ع)  
> **مراجع:**  
> - [`naboo_market_master_plan_v1.md`](./naboo_market_master_plan_v1.md)  
> - [`naboo_ecosystem_master_plan_v1.md`](./naboo_ecosystem_master_plan_v1.md)  
> - [`naboo_pilot_90_days_v1.md`](./naboo_pilot_90_days_v1.md) — Pilot = COD فقط  

> ⚠️ **لا تستخدم** [`naboo_payment_master_plan_v1.md`](./naboo_payment_master_plan_v1.md) — ذلك لاشتراك ERP القديم.

---

## فهرس المحتويات

1. [الملخص — ماذا يريد المستخدم؟](#1-الملخص--ماذا-يريد-المستخدم)
2. [محفظتان — لا تخلط بينهما](#2-محفظتان--لا-تخلط-بينهما)
3. [رصيد نابو (Naboo Balance)](#3-رصيد-نابو-naboo-balance)
4. [الدفع الإلكتروني وربط البطاقة](#4-الدفع-الإلكتروني- وربط-البطاقة)
5. [حالات الطلب — متى يُلغى؟](#5-حالات-الطلب--متى-يلغى)
6. [جدول الإلغاء والاسترداد الكامل](#6-جدول-الإلغاء-والاسترداد-الكامل)
7. [تدفقات الاسترداد خطوة بخطوة](#7-تدفقات-الاسترداد-خطوة-بخطوة)
8. [السحب إلى البطاقة / المحفظة (3–7 أيام)](#8-السحب-إلى-البطاقة--المحفظة-37-أيام)
9. [بعد التسليم — الإرجاع (5 أيام)](#9-بعد-التسليم--الإرجاع-5-أيام)
10. [كيف تفعل Ozon · Amazon · Wildberries](#10-كيف-تفعل-ozon--amazon--wildberries)
11. [التكييف للسوق العراقي](#11-التكييف-للسوق-العراقي)
12. [واجهة المستخدم](#12-واجهة-المستخدم)
13. [نموذج البيانات](#13-نموذج-البيانات)
14. [البوابات والتكامل](#14-البوابات-والتكامل)
15. [الاحتيال والحدود](#15-الاحتيال-والحدود)
16. [مراحل الإطلاق](#16-مراحل-الإطلاق)
17. [معايير القبول](#17-معايير-القبول)

---

# 1. الملخص — ماذا يريد المستخدم؟

## 1.1 السينario الذي وصفته

```
1. المستخدم يدفع إلكترونياً (بطاقة / Zain Cash / FIB)
2. الطلب لم يُشحن بعد → يلغي → المال يرجع فوراً «محفظتي» (رصيد/نقاط)
3. الطلب شُحن → لا إلغاء حتى يصل لنقطة PVZ
4. وصل لنقطة PVZ → يمكن الإلغاء/الرفض مع خصم رسوم توصيل → الباقي للمحفظة
5. من المحفظة: شراء مجدداً فوراً، أو سحب إلى البطاقة خلال 3–7 أيام
```

## 1.2 المبدأ الذهبي (مثل الكبار)

> **استرداد فوري للمحفظة · استرداد بطيء للبطاقة**  
> Ozon و Wildberries يعطون رصيداً **لحظياً** — البطاقة تأخذ أياماً. هذا يقلل القلق ويزيد إعادة الشراء.

## 1.3 Pilot vs لاحقاً

| Pilot (90 يوم) | V2+ |
|----------------|-----|
| **COD فقط** — لا محفظة مستهلك | دفع إلكتروني + محفظة |
| إلغاء قبل التجهيز = لا مال (لم يدفع) | استرداد للمحفظة |
| — | سحب للبطاقة 3–7 أيام |

**هذه الوثيقة = تصميم V2** — تُبنى بعد نجاح Pilot COD.

---

# 2. محفظتان — لا تخلط بينهما

| | **محفظة التاجر** (ERP) | **محفظة المستهلك** (Market) |
|---|------------------------|----------------------------|
| **من** | صاحب المحل | المشتري |
| **الغرض** | خصم **عمولة** Naboo | **استرداد** · رصيد للشراء |
| **يشحنها** | التاجر (اختياري) | Naboo تلقائياً عند الإلغاء/الإرجاع |
| **يسحب منها** | — (أو settlement لاحق) | المستهلك → بطاقته |
| **Pilot** | COD خصم عمولة | **غير موجودة** |
| **جدول DB** | `merchant_wallet_*` | `consumer_wallet_*` |

---

# 3. رصيد نابو (Naboo Balance)

## 3.1 التسمية للمستخدم

```
┌─────────────────────────────────────┐
│  💰 محفظتي                          │
│  رصيدك:  10,000 نقطة               │
│  (= 10,000 د.ع — تسوّق بها فوراً)   │
└─────────────────────────────────────┘
```

| في الواجهة | في DB |
|------------|-------|
| «10,000 نقطة» أو «10,000 د.ع» | `balance_fils = 10000000` (إذا 1 fils = 0.001 د.ع) أو `10000000` fils = 10,000 IQD |

> **قرار:** 1 **نقطة = 1 دينار عراقي** — لا تحويل معقد. النقاط = واجهة UX؛ التخزين `int fils`.

## 3.2 مصادر الرصيد

| المصدر | فوري؟ |
|--------|-------|
| إلغاء قبل الشحن | ✅ فوري للمحفظة |
| إلغاء عند PVZ (بعد خصم توصيل) | ✅ فوري |
| إرجاع بعد التسليم (5 أيام) | ✅ فوري بعد موافقة |
| شحن يدوي (V3 — promo) | ✅ |
| استرداد بطاقة → فشل | ✅ يرجع للمحفظة |

## 3.3 استخدام الرصيد

| الاستخدام | مسموح |
|-----------|-------|
| دفع طلب كامل | ✅ |
| دفع جزئي + بطاقة | ✅ V2.5 |
| تحويل لصديق | ❌ |
| سحب نقدي من PVZ | ❌ |
| سحب للبطاقة | ✅ (قسم 8) |

## 3.4 صلاحية الرصيد

| السياسة | القيمة المقترحة |
|---------|-----------------|
| انتهاء | **لا ينتهي** (مثل Ozon Wallet) — أو 24 شهر inactivity (V3) |
| حد أقصى | 5,000,000 د.ع (5M) — anti-money-laundering |

---

# 4. الدفع الإلكتروني وربط البطاقة

## 4.1 طرق الدفع (V2)

| الطريقة | ربط | استرداد للمصدر |
|---------|-----|-----------------|
| **Zain Cash** | رقم محفظة | 1–3 أيام |
| **FIB** | حساب FIB | 1–3 أيام |
| **Visa / Mastercard** | **token** — لا تخزين PAN | 3–7 أيام |
| **رصيد نابو** | — | فوري |
| **COD** | — | لا ينطبق |

## 4.2 ربط البطاقة (Tokenization)

```
Checkout:
  ○ Zain Cash
  ○ FIB
  ○ بطاقة بنكية
      → WebView / SDK بوابة الدفع
      → يعود token: card_token_xxx
      → نخزن: last4, brand, expiry — **لا** رقم كامل

«احفظ بطاقتي للدفعات القادمة» ☑
```

**PCI:** كل معالجة على **الخادم + بوابة** — لا `service_role` في Flutter.

## 4.3 أول شراء vs شراء لاحق

| | أول مرة | مرات لاحقة |
|---|---------|------------|
| بطاقة | إدخال كامل عبر بوابة | «**** 4532» one-click |
| Zain | OTP | رقم محفظة محفوظ |
| رصيد | — | يُعرض تلقائياً إن وُجد |

---

# 5. حالات الطلب — متى يُلغى؟

## 5.1 آلة الحالات (Order State Machine)

```
pending ──→ accepted ──→ ready_to_ship ──→ in_transit ──→ at_pickup_point ──→ delivered
   │            │              │               │                  │
   └ cancelled  └ cancelled    └ cancelled*    │                  │
   (فوري)       (فوري)         (فوري*)         │                  │
                                               ❌ لا إلغاء        cancel/refuse**
                                               حتى PVZ            (خصم توصيل)
                                                                    │
                                                               returned (5d)
```

\* `ready_to_ship`: إلغاء مسموح **فقط** إذا لم يُسجّل «خرج من المحل» بعد  
\*\* `at_pickup_point`: رفض الاستلام = إلغاء مع خصم توصيل

## 5.2 تعريف «شُحن»

| الحالة | «شُحن»؟ | إلغاء ذاتي؟ |
|--------|---------|-------------|
| `pending` | ❌ | ✅ كامل |
| `accepted` | ❌ | ✅ كامل |
| `ready_to_ship` | ❌* | ✅ كامل* |
| `in_transit` | ✅ | ❌ **ممنوع** |
| `at_pickup_point` | ✅ | ⚠️ رفض + خصم توصيل |
| `delivered` | — | إرجاع (5 أيام) — ليس «إلغاء» |

---

# 6. جدول الإلغاء والاسترداد الكامل

## 6.1 قبل الشحن (pending · accepted · ready_to_ship*)

| البند | السياسة |
|-------|---------|
| **من يلغي** | المستهلك (ذاتي) أو التاجر (رفض) |
| **استرداد المنتج** | **100%** |
| **رسوم توصيل** | **0** — لم تُنفّذ |
| **أين يذهب المال** | **محفظة نابو فوراً** (افتراضي) |
| **بديل** | «استرداد للبطاقة» — 3–7 أيام |
| **وقت المحفظة** | **≤ 60 ثانية** |

**مثال:** دفع 45,000 د.ع → ألغى قبل الشحن → محفظة +45,000 نقطة فوراً.

## 6.2 أثناء الشحن (`in_transit`)

| البند | السياسة |
|-------|---------|
| إلغاء ذاتي | **❌ ممنوع** — مثل Ozon بعد dispatch |
| **السبب** | البضاعة في الطريق — تكلفة لوجستية |
| **استثناء** | دعم Naboo (طرد ضائع، تأخير >72h) — يدوي |

**UX:** زر «إلغاء» **معطّل** + «تواصل مع الدعم».

## 6.3 عند نقطة PVZ (`at_pickup_point`)

| البند | السياسة |
|-------|---------|
| **رفض الاستلام** | مسموح — مثل Ozon «لم أستلم» |
| **استرداد المنتج** | 100% قيمة البضاعة |
| **خصم توصيل** | **رسوم الشحن ثابتة** — لا تُسترد |
| **أين الباقي** | محفظة فوراً |

**مثال:**

```
قيمة منتجات:     40,000 د.ع
رسوم توصيل/PVZ:   3,000 د.ع  ← تُستقطع
─────────────────────────────
يعود للمحفظة:    37,000 د.ع  (فوري)
```

| سينario | خصم توصيل |
|---------|------------|
| PVZ pickup — رفض عند الاستلام | 3,000 د.ع (أو `delivery_fee_fils` من الطلب) |
| توصيل منزلي (V3) | 5,000–8,000 د.ع |

## 6.4 بعد التسليم (`delivered`)

| البند | السياسة |
|-------|---------|
| «إلغاء» | ❌ — يُسمّى **إرجاع** |
| نافذة | **5 أيام** من `delivered_at` |
| فحص | PVZ أو التاجر |
| استرداد | محفظة بعد قبول الإرجاع |
| خصم توصيل | **لا** — إذا لم يُسلّم أصلاً (إرجاع كامل) |
| منتجات استخدام | سياسة فئة (ملابس ✓ · بقالة مفتوحة ✗) |

---

# 7. تدفقات الاسترداد خطوة بخطوة

## 7.1 إلغاء قبل الشحن — دفع بطاقة

```
1. المستخدم: «إلغاء الطلب» → تأكيد
2. Edge Function: cancel_order
   - status → cancelled
   - payment_status → refund_pending_wallet
3. consumer_wallet: balance += order.total_fils
4. wallet_ledger: type=refund_cancel, ref=order_id
5. Push: «تم إلغاء طلبك — 45,000 نقطة في محفظتك»
6. ≤ 60 ثانية
```

## 7.2 إلغاء قبل الشحن — يريد البطاقة لا المحفظة

```
1. نفس الخطوات — لكن:
2. balance += 0
3. refund_to_gateway(order_id, amount, card_token)
4. status: refund_processing
5. Push: «استرداد 45,000 د.ع — يصل خلال 3–7 أيام»
6. Webhook بوابة → refund_completed
```

**افتراضي UI:** محفظة أولاً — «أسرع». خيار ثانوي: «إلى بطاقتي».

## 7.3 رفض عند PVZ

```
1. المستخدم في «طلباتي» → «لن أستلم» (at_pickup_point فقط)
2. أو الموظف يسجّل «رفض» في ERP
3. refund_amount = total - delivery_fee_fils
4. wallet += refund_amount
5. الطرد يرجع للتاجر (reverse logistics — V2.5)
6. Push + إيصال
```

## 7.4 مخطط قرار الاسترداد

```
                    ┌─ قبل in_transit ─→ 100% → محفظة (فوري)
                    │
دفع إلكتروني ───────┼─ in_transit ──────→ ❌ لا إلغاء
                    │
                    ├─ at_pickup_point ─→ total - delivery_fee → محفظة
                    │
                    └─ delivered (<5d) ─→ إرجاع → فحص → محفظة
```

---

# 8. السحب إلى البطاقة / المحفظة (3–7 أيام)

## 8.1 من محفظتي → بطاقتي

```
┌─────────────────────────────────────┐
│  سحب الرصيد                         │
│  الرصيد: 37,000 نقطة                │
│  المبلغ: [________] د.ع             │
│  إلى: Visa **** 4532                │
│  ⏱ يصل خلال 3–7 أيام عمل           │
│  [ تأكيد السحب ]                    │
└─────────────────────────────────────┘
```

## 8.2 قواعد السحب

| القاعدة | القيمة |
|---------|--------|
| حد أدنى | 5,000 د.ع |
| حد أقصى/عملية | 1,000,000 د.ع |
| حد يومي | 2,000,000 د.ع |
| رسوم سحب | **0** في V2 (جذب) — 1% في V3+ |
| زمن الوصول | **3–7 أيام** بطاقة · **1–3** Zain/FIB |
| مصدر السحب | **نفس** طريقة آخر دفع أو البطاقة المحفوظة |

## 8.3 حالات السحب

| الحالة | UX |
|--------|-----|
| `withdrawal_pending` | «قيد المعالجة» |
| `withdrawal_sent` | «أُرسل للبنك — 3–7 أيام» |
| `withdrawal_completed` | «وصل» |
| `withdrawal_failed` | «فشل — الرصيد عاد لمحفظتك» |

## 8.4 لماذا 3–7 أيام؟

| المنصة | بطاقة | محفظة داخلية |
|--------|-------|--------------|
| **Amazon** | 3–5 أيام | gift balance فوري |
| **Ozon** | 3–10 أيام | Ozon Wallet **فوري** |
| **Wildberries** | 5–10 أيام | WB Balance **فوري** |
| **Naboo** | **3–7 أيام** | **فوري ≤60s** |

> **استراتيجية:** اعرض المحفظة **افتراضياً** — 80% يبقون ويشترون مجدداً (مثل Ozon).

---

# 9. بعد التسليم — الإرجاع (5 أيام)

## 9.1 تدفق

```
1. delivered → within 5 days → «طلب إرجاع»
2. اختيار سبب + صور (اختياري)
3. status: return_requested
4. المستخدم يُعيد لـ PVZ أو مندوب يستلم (V2.5)
5. التاجر/PVZ يفحص → return_accepted | return_rejected
6. accepted → wallet += amount (full if defective)
7. rejected → دعم + dispute
```

## 9.2 فئات الإرجاع

| الفئة | إرجاع | ملاحظة |
|-------|-------|--------|
| إلكترونيات (عيب) | ✅ كامل | فحص |
| ملابس (لم يُلبس) | ✅ | بطاقة معلّقة |
| بقالة | ❌ | except defective |
| مستحضرات مفتوحة | ❌ | |

---

# 10. كيف تفعل Ozon · Amazon · Wildberries

## 10.1 جدول مقارن

| الموضوع | **Ozon** | **Amazon** | **Wildberries** | **Naboo (مقترح)** |
|---------|----------|------------|-----------------|-------------------|
| محفظة داخلية | Ozon Wallet | Gift balance | WB Balance | **رصيد نابو** |
| إلغاء قبل الشحن | فوري للمحفظة | فوري/بطاقة | فوري للرصيد | **فوري محفظة** |
| بعد الشحن | لا إلغاء | لا إلغاء | لا إلغاء | **لا إلغاء** |
| PVZ رفض | خصم delivery | — | pickup refuse | **خصم delivery_fee** |
| استرداد بطاقة | 3–10 أيام | 3–5 أيام | 5–10 أيام | **3–7 أيام** |
| one-click pay | ✅ | ✅ | ✅ | ✅ V2 |
| نقاط ولاء | Ozon Points | Prime | кешбэк | ⏳ V3 |

## 10.2 ما نأخذه حرفياً

1. **Instant wallet refund** — أهم ميزة ثقة  
2. **No cancel in transit** — industry standard  
3. **Pickup refusal fee** — عادل للوجستics  
4. **Default to wallet, optional to card** — يزيد retention  
5. **Clear timeline** — «3–7 أيام» ظاهر قبل تأكيد السحب  

## 10.3 ما لا ننسخه

| Ozon/WB | لماذا لا للعراق Pilot |
|---------|----------------------|
| إرجاع 14–30 يوم | **5 أيام** — PVZ محدود |
| بنك/Ozon Card | تعقيد تنظيمي |
| اشتراك Prime | Naboo مجاني |

---

# 11. التكييف للسوق العراقي

## 11.1 COD vs إلكتروني

| | COD | إلكتروني + محفظة |
|---|-----|------------------|
| Pilot | ✅ 100% | ❌ |
| إلغاء قبل الشحن | «تم الإلغاء» — لا مال | استرداد محفظة |
| ثقة | «لم أدفع بعد» | **المحفظة الفورية** = بديل ثقة |
| رفض عند PVZ | لا يدفع — لا استرداد | خصم delivery |

## 11.2 بوابات عراقية

| بوابة | استرداد API | أولوية |
|-------|-------------|--------|
| **Zain Cash** | refund endpoint | 1 |
| **FIB** | web payments refund | 2 |
| **Qi Card / Switch** | acquirer dependent | 3 |
| **Visa/MC** | عبر aggregator | 3 |

## 11.3 ثقة المستهلك

| الخوف العراقي | رد Naboo |
|---------------|----------|
| «دفعت واختفى المال» | محفظة **≤60 ثانية** + إشعار |
| «البطاقة بطيئة» | خيار محفظة **افتراضي** |
| «COD أأمن» | Pilot COD — V2 نبني ثقة إلكتروني |
| «التاجر لا يرد» | Naboo وسيط — استرداد من المنصة |

## 11.4 نصوص عربية واضحة (UX)

```
قبل الدفع:
  «يمكنك الإلغاء مجاناً قبل شحن الطرد —
   يُعاد المبلغ فوراً إلى محفظتك»

عند in_transit:
  «الطرد في الطريق — الإلغاء غير متاح.
   سيتواصل معك عند وصوله لنقطة الاستلام»

عند PVZ:
  «يمكنك رفض الاستلام — تُخصم رسوم التوصيل 3,000 د.ع فقط»
```

---

# 12. واجهة المستخدم

## 12.1 شاشات

| الشاشة | المحتوى |
|--------|---------|
| **محفظتي** | رصيد · سجل · سحب · شحن (promo) |
| **تفاصيل طلب** | زر إلغاء (حسب الحالة) · timeline |
| **إلغاء — تأكيد** | «45,000 د.ع → محفظتك فوراً» |
| **سحب** | مبلغ · بطاقة · ETA 3–7 أيام |
| **Checkout** | رصيد نابو · بطاقة · Zain · FIB |

## 12.2 زر الإلغاء — حسب الحالة

| status | الزر |
|--------|------|
| pending / accepted / ready_to_ship | 🟢 «إلغاء الطلب — استرداد فوري» |
| in_transit | 🔴 معطّل + «في الطريق» |
| at_pickup_point | 🟡 «لن أستلم — خصم 3,000 د.ع توصيل» |
| delivered | «طلب إرجاع» (≤5 أيام) |

## 12.3 سجل المحفظة (Ledger)

```
+ 45,000  استرداد — إلغاء #NAB-042      اليوم
- 12,000  شراء — طلب #NAB-051           أمس
+  3,000  promo — أول طلب               —
- 37,000  سحب — Visa ****4532 (قيد...)  —
```

---

# 13. نموذج البيانات

## 13.1 consumer_wallets

```sql
CREATE TABLE consumer_wallets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL UNIQUE REFERENCES marketplace_customers(id),
  balance_fils    INTEGER NOT NULL DEFAULT 0 CHECK (balance_fils >= 0),
  currency        TEXT NOT NULL DEFAULT 'IQD',
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 13.2 consumer_wallet_ledger

```sql
CREATE TABLE consumer_wallet_ledger (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id       UUID NOT NULL REFERENCES consumer_wallets(id),
  type            TEXT NOT NULL,
  -- refund_cancel | refund_pickup_refuse | refund_return
  -- purchase | withdrawal | withdrawal_reversal | promo
  amount_fils     INTEGER NOT NULL,  -- + or -
  balance_after   INTEGER NOT NULL,
  order_id        UUID REFERENCES marketplace_orders(id),
  withdrawal_id   UUID,
  idempotency_key TEXT UNIQUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 13.3 consumer_payment_methods

```sql
CREATE TABLE consumer_payment_methods (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL,
  provider        TEXT NOT NULL,  -- zaincash | fib | card
  token_ref       TEXT NOT NULL,  -- gateway token — NOT PAN
  display_last4   TEXT,
  display_brand   TEXT,
  is_default      BOOLEAN DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 13.4 consumer_withdrawals

```sql
CREATE TABLE consumer_withdrawals (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id       UUID NOT NULL,
  amount_fils     INTEGER NOT NULL,
  payment_method_id UUID NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending',
  -- pending | sent | completed | failed
  gateway_ref     TEXT,
  eta_business_days INTEGER DEFAULT 5,
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 13.5 حقول إضافية على marketplace_orders

```sql
ALTER TABLE marketplace_orders ADD COLUMN IF NOT EXISTS
  refund_destination TEXT,  -- wallet | card | zaincash
  refund_amount_fils INTEGER DEFAULT 0,
  delivery_fee_non_refundable_fils INTEGER DEFAULT 0,
  cancelled_at TIMESTAMPTZ,
  cancel_reason TEXT;
```

---

# 14. البوابات والتكامل

## 14.1 Edge Functions

| Function | دور |
|----------|-----|
| `cancel_order` | تحقق status · حساب refund · wallet/gateway |
| `refuse_pickup` | at_pickup_point · خصم delivery |
| `request_return` | delivered · 5d window |
| `process_withdrawal` | سحب → gateway payout |
| `payment_webhook` | refund_completed |

## 14.2 Idempotency

```
كل refund/withdrawal = idempotency_key
  → منع استرداد مزدوج (critical للمال)
```

## 14.3 ترتيب الأولوية عند الإلغاء

```
1. idempotency check
2. lock order row
3. verify status allows cancel
4. credit wallet (transaction)
5. ledger entry
6. notify user
7. async: gateway refund if requested to card instead
8. notify merchant ERP
```

---

# 15. الاحتيال والحدود

| التهديد | Mitigation |
|---------|------------|
| إلغاء وإعادة شراء loop | max 3 cancels/30d — review |
| سحب فوري بعد refund | hold 24h on wallet-to-card first time |
| بطاقة مسروقة | 3DS / OTP بوابة |
| collusion تاجر-مشتري | audit cancel rate per store |
| غسل أموال | KYC >500K cumulative withdrawal |

---

# 16. مراحل الإطلاق

| المرحلة | المحفظة | الدفع | الإلغاء |
|---------|---------|-------|---------|
| **Pilot** | ❌ | COD | إلغاء بدون مال |
| **V2a** | ✅ | Zain + FIB | قبل ship → wallet |
| **V2b** | ✅ | + بطاقة token | + سحب 3–7d |
| **V2.5** | ✅ | — | رفض PVZ + reverse logistics |
| **V3** | ✅ | partial pay | إرجاع 5d كامل |

---

# 17. معايير القبول

### محفظة
- [ ] إلغاء قبل `in_transit` → رصيد +≤60s
- [ ] ledger دقيق — `balance = sum(ledger)`
- [ ] idempotency — لا استرداد مزدوج

### PVZ
- [ ] رفض at_pickup → total - delivery_fee
- [ ] in_transit → زر إلغاء معطّل

### سحب
- [ ] min 5,000 د.ع
- [ ] ETA 3–7 أيام ظاهر
- [ ] failed → رصيد يعود

### عراق
- [ ] Zain refund UAT
- [ ] FIB refund stage
- [ ] نصوص عربية RTL

---

## الخاتمة

```
دفع إلكتروني → إلغاء قبل الشحن  → 100% محفظة فوراً
              → شُحن            → لا إلغاء
              → وصل PVZ         → رفض − رسوم توصيل → محفظة
              → محفظة           → شراء فوري أو سحب 3–7 أيام للبطاقة
```

**مثل Ozon/Wildberries:** ثقة = **سرعة المحفظة** · **وضوح القواعد** · **بطاقة للصبر**.

**Pilot:** COD فقط — هذه الوثيقة تُنفَّذ في **V2** بعد نجاح 3+ طلبات COD.

---

**نهاية الوثيقة**

*الإصدار: 1.0 | 2026-06-20 | تخطيط — لا كود*

*مرجع: [`naboo_market_master_plan_v1.md`](./naboo_market_master_plan_v1.md) §12*
