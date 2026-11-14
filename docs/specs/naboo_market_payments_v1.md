# Naboo Market — الدفع الإلكتروني (V2)
## Market Payments v1.0 | Zain Cash · FIB · بطاقة

> **الحالة:** تخطيط — **ليس Pilot** (Pilot = COD فقط)  
> **التاريخ:** 2026-06-20  
> **المراجع:**  
> - [`naboo_market_consumer_wallet_refunds_v1.md`](./naboo_market_consumer_wallet_refunds_v1.md)  
> - [`naboo_market_master_plan_v1.md`](./naboo_market_master_plan_v1.md)  
> - [`payment_gateways_iraq_v1.md`](./payment_gateways_iraq_v1.md)  

> ⚠️ **لا تستخدم** [`naboo_payment_master_plan_v1.md`](./naboo_payment_master_plan_v1.md) — اشتراك ERP قديم.

---

## 1. متى تُبنى؟

```
Pilot (الآن):     COD فقط
V2a (شهر 4–6):   Zain Cash + FIB + محفظة نابو
V2b (شهر 6–8):   Visa/Mastercard (token)
```

**شرط البدء:** ≥3 طلبات COD مُسلّمة · ≥10 تجار · رفض COD ≤40%

---

## 2. طرق الدفع

| الطريقة | الأولوية | استرداد |
|---------|----------|---------|
| **COD** | Pilot ✅ | — |
| **رصيد نابو** | V2a | فوري — انظر wallet doc |
| **Zain Cash** | V2a | 1–3 أيام أو محفظة فوري |
| **FIB** | V2a | 1–3 أيام أو محفظة فوري |
| **Visa / Mastercard** | V2b | 3–7 أيام أو محفظة فوري |

---

## 3. Checkout V2

```
الخطوة 1 — PVZ
الخطوة 2 — الدفع:
  ○ نقد عند الاستلام (COD)
  ○ رصيد نابو (إن وُجد)
  ○ Zain Cash
  ○ FIB
  ○ بطاقة ****4532 [+ ربط بطاقة جديدة]
الخطوة 3 — تأكيد
```

**افتراضي عراق:** COD يبقى **أول خيار** — الإلكتروني تحته.

---

## 4. ربط البطاقة (Tokenization)

```
Market → POST /payments/checkout?provider=card
      → redirect/WebView بوابة (Qi / Switch / FIB)
      → token_ref يعود للخادم
      → consumer_payment_methods
```

| يُخزّن | لا يُخزّن |
|--------|-----------|
| token_ref | PAN كامل |
| last4, brand | CVV |
| expiry | |

---

## 5. Zain Cash (V2a)

| البند | القيمة |
|-------|--------|
| API | Payment Gateway v2 — UAT ثم prod |
| تدفق | redirect → OTP → callback webhook |
| جدول | `marketplace_payments` |
| refund | API refund → محفظة أو محفظة Zain |

**مرجع تقني قديم (اشتراك):** [`zaincash_auto_activation_v1.md`](./zaincash_auto_activation_v1.md) — استخدم **أنماط** webhook/idempotency فقط.

### 5.1 Edge Functions

| Function | دور |
|----------|-----|
| `create_market_payment` | order_id + provider → redirectUrl |
| `zaincash_market_webhook` | verify JWT → mark paid → confirm order |
| `zaincash_market_refund` | cancel/refund |

---

## 6. FIB (V2a)

| البند | القيمة |
|-------|--------|
| API | FIB Web Payments |
| تدفق | مشابه Zain — server-side secrets |
| refund | حسب وثائق FIB integrations |

---

## 7. البطاقة (V2b)

| البند | القيمة |
|-------|--------|
| Aggregator | Qi Card / Switch / FIB acquiring — **تفاوض تاجر** |
| 3DS | إلزامي حيث متوفر |
| refund | 3–7 أيام — أو محفظة فوري |

---

## 8. جدول `marketplace_payments`

```sql
CREATE TABLE marketplace_payments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id        UUID NOT NULL REFERENCES marketplace_orders(id),
  user_id         UUID NOT NULL,
  provider        TEXT NOT NULL,  -- cod | zaincash | fib | card | wallet
  amount_fils     INTEGER NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending',
  -- pending | authorized | captured | failed | refunded
  gateway_ref     TEXT,
  idempotency_key TEXT UNIQUE,
  created_at      TIMESTAMPTZ DEFAULT now(),
  captured_at     TIMESTAMPTZ
);
```

---

## 9. استرداد — ملخص

| حالة | COD | إلكتروني |
|------|-----|----------|
| إلغاء قبل شحن | لا مال | **100% محفظة ≤60s** |
| in_transit | — | لا إلغاء |
| رفض PVZ | لا دفع | total − delivery_fee → محفظة |
| سحب لبطاقة | — | 3–7 أيام |

**التفاصيل:** [`naboo_market_consumer_wallet_refunds_v1.md`](./naboo_market_consumer_wallet_refunds_v1.md)

---

## 10. أمان

- أسرار بوابات على **admin-web** فقط  
- لا `service_role` في Market Flutter  
- idempotency على كل دفع واسترداد  
- audit log للعمليات المالية  
- RLS: مستخدم يرى مدفوعاته فقط  

---

## 11. امتثال المتاجر

| المتجر | ملاحظة |
|--------|--------|
| Google Play | منتجات مادية + COD + بوابات خارجية — مسموح |
| Apple | نفس المبدأ — لا IAP لسلع مادية |

---

## 12. خارطة تنفيذ

| أسبوع | مهام |
|-------|------|
| 1–2 | `marketplace_payments` · Zain UAT |
| 3 | FIB stage · محفظة consumer |
| 4 | checkout V2 · refund cancel |
| 5–6 | بطاقة token · سحب 3–7d |
| 7 | اختبار E2E · أمن |

---

## 13. معايير قبول V2

- [ ] دفع Zain 10,000 د.ع UAT — طلب مؤكد  
- [ ] إلغاء قبل شحن — محفظة +≤60s  
- [ ] refund idempotent — لا مزدوج  
- [ ] COD ما زال يعمل  
- [ ] أسرار ليست في Flutter  

---

*الإصدار: 1.0 | 2026-06-20 | V2 — بعد Pilot COD*
