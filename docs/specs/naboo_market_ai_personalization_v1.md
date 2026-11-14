# Naboo Market — خطة الذكاء الاصطناعي ومراقبة الاهتمامات
## AI Personalization & Behavioral Intelligence v1.0

> **الحالة:** تخطيط تفصيلي — **لا كود**  
> **التاريخ:** 2026-06-20  
> **المراجع:**  
> - [`naboo_market_master_plan_v1.md`](./naboo_market_master_plan_v1.md)  
> - [`naboo_ecosystem_master_plan_v1.md`](./naboo_ecosystem_master_plan_v1.md)  
> - [`naboo_pilot_90_days_v1.md`](./naboo_pilot_90_days_v1.md)  

---

## فهرس المحتويات

1. [الهدف — ماذا يفعل «الذكاء»؟](#1-الهدف--ماذا-يفعل-الذكاء)
2. [إشارات السلوك — ماذا نراقب بالضبط؟](#2-إشارات-السلوك--ماذا-نراقب-بالضبط)
3. [نموذج الاهتمامات (Interest Profile)](#3-نموذج-الاهتمامات-interest-profile)
4. [كيف تُبنى الصفحة الرئيسية المخصّصة](#4-كيف-تُبنى-الصفحة-الرئيسية-المخصصة)
5. [التوقف والتصفّح — Dwell & Scroll Intelligence](#5-التوقف-والتصفح--dwell--scroll-intelligence)
6. [البحث الذكي والنوايا](#6-البحث-الذكي-والنوايا)
7. [الإعلانات المستهدفة (نفس محرك الاهتمامات)](#7-الإعلانات-المستهدفة-نفس-محرك-الاهتمامات)
8. [المساعد الذكي (LLM) — مرحلة لاحقة](#8-المساعد-الذكي-llm--مرحلة-لاحقة)
9. [الخصوصية والموافقة](#9-الخصوصية-والموافقة)
10. [المعمارية التقنية](#10-المعمارية-التقنية)
11. [نموذج البيانات](#11-نموذج-البيانات)
12. [خط أنابيب المعالجة (Pipeline)](#12-خط-أنابيب-المعالجة-pipeline)
13. [مراحل الإطلاق — متى يُفعّل كل جزء](#13-مراحل-الإطلاق--متى-يُفعّل-كل-جزء)
14. [معايير الجودة والاختبار](#14-معايير-الجودة-والاختبار)
15. [مؤشرات النجاح (KPIs)](#15-مؤشرات-النجاح-kpis)
16. [ما لا نفعله](#16-ما-لا-نفعله)

---

# 1. الهدف — ماذا يفعل «الذكاء»؟

## 1.1 الفكرة بجملة واحدة

> **نظام يراقب — بموافقة المستخدم — كيف يتصفّح، ماذا يتوقف عنده، وماذا يشتري، ثم يُخصّص الصفحة الرئيسية والعروض والإعلانات accordingly — مثل Ozon و Wildberries.**

```
المستخدم يتصفّح
      ↓
  جمع إشارات (views · توقف · سلة · شراء)
      ↓
  بناء «ملف اهتمامات» (Interest Profile)
      ↓
  ┌─────────────────────────────────────┐
  │  الرئيسية المخصّصة                  │
  │  Push مستهدف                        │
  │  إعلانات تجار (لاحقاً)              │
  │  «منتجات مشابهة»                    │
  │  ترتيب نتائج البحث                  │
  └─────────────────────────────────────┘
```

## 1.2 ليس «ChatGPT في التطبيق» من اليوم الأول

| المرحلة | ما يُسمّاه المستخدم «AI» | ما يحدث تقنياً |
|---------|--------------------------|----------------|
| Pilot | «يعرف حيّي» | قواعد + trending محلي |
| V1 | «يفهم اهتماماتي» | تتبّع سلوك + scoring |
| V2 | «يفهم بحثي» | embeddings عربية |
| V3 | «يساعدني أختار» | LLM + RAG على catalog |
| V3+ | «إعلانات مناسبة» | استهداف شرائح |

## 1.3 المخرجات المرئية للمستخدم

| المخرج | مثال |
|--------|------|
| قسم رئيسية | «**لأنك مهتم بالبقالة**» |
| قسم رئيسية | «**توقفت عند هذه المنتجات**» |
| قسم رئيسية | «**شائع بين جيرانك في العشار**» |
| Push | «انخفض سعر [منتج توقفت عنده]» |
| بحث | نتائج مرتبة حسب اهتمامك لا فقط الكلمات |
| إعلان (لاحقاً) | تاجر ملابس يستهدف من يتصفّح ملابس |

---

# 2. إشارات السلوك — ماذا نراقب بالضبط؟

## 2.1 مبدأ: «إشارة = حدث + سياق + وزن»

كل تفاعل يُسجّل كحدث:

```
event_name + user_id + timestamp + payload + session_id + weight
```

**لا نخزّن:** محتوى رسائل · موقع GPS دقيق · لقطات شاشة · ميكروفون.

## 2.2 جدول الإشارات الكامل

### أ) التصفّح والمشاهدة

| الإشارة | الحدث | ماذا يعني | الوزن |
|---------|-------|-----------|-------|
| **فتح منتج** | `product_view` | اهتمام أولي | +1 |
| **مدة على صفحة المنتج** | `product_dwell` | `duration_ms` — كل 3+ ثوانٍ = اهتمام أقوى | +1 إلى +5 |
| **تمرير صور المنتج** | `product_image_swipe` | كل صورة إضافية = اهتمام | +0.5 لكل صورة |
| **تكبير صورة** | `product_image_zoom` | اهتمام عالي — يقارن التفاصيل | +3 |
| **قراءة الوصف** | `product_description_expand` | يريد معلومات قبل الشراء | +2 |
| **عودة لنفس المنتج** | `product_revisit` | اهتمام متكرر — قرار شراء | +4 |
| **مشاهدة بدون شراء** | `product_view_no_purchase` | intent ضعيف أو سعر عالي | +0.5 |

### ب) التوقف أثناء التمرير (Scroll Stop) — **ما طلبته صراحة**

| الإشارة | الحدث | كيف نكتشفها | الوزن |
|---------|-------|-------------|-------|
| **توقف على بطاقة منتج** | `product_card_impression_dwell` | البطاقة ≥50% ظاهرة ≥1.5 ثانية في feed | +2 |
| **توقف طويل** | `product_card_impression_dwell_long` | ≥4 ثوانٍ — «يقارن» | +4 |
| **توقف على قسم رئيسية** | `home_section_dwell` | `section_id` + `duration_ms` | يغذّي ترتيب الأقسام |
| **توقف على تصنيف** | `category_tile_dwell` | ≥2 ثانية على أيقونة «ملابس» | +3 لتصنيف ملابس |
| **تمرير سريع بدون توقف** | `feed_fast_scroll` | disinterest — **لا** نزيد وزن التصنيف | 0 أو -0.5 |

**تقنياً (Flutter — لاحقاً):**

```
VisibilityDetector + Timer
  → عندما visibleFraction >= 0.5 لمدة >= 1500ms
  → أرسل product_card_impression_dwell
  → debounce: لا تكرر نفس المنتج في نفس الجلسة خلال 30 ثانية
```

### ج) النقر والتفاعل

| الإشارة | الحدث | الوزن |
|---------|-------|-------|
| نقر تصنيف | `category_click` | +3 للتصنيف |
| نقر متجر | `store_click` | +2 للمتجر |
| نقر بانر | `banner_click` | +2 للحملة/التصنيف |
| «أضف للسلة» | `add_to_cart` | +8 |
| «احذف من السلة» | `remove_from_cart` | -3 |
| بدء checkout | `checkout_start` | +10 |
| إلغاء checkout | `checkout_abandon` | -5 |
| شراء | `purchase` | +20 |
| إرجاع | `return` | -15 |

### د) البحث

| الإشارة | الحدث | الوزن |
|---------|-------|-------|
| بحث | `search` | `query` + نتائج |
| نقر نتيجة #3 | `search_result_click` | position يدل على جودة الترتيب |
| بحث بدون نقر | `search_zero_click` | catalog gap |
| تصحيح اقتراح | `search_suggestion_click` | |

### هـ) السياق (Context) — يُرفق بكل حدث

| حقل | أمثلة | استخدام |
|-----|--------|---------|
| `neighborhood_id` | العشار | trending محلي |
| `hour_of_day` | 8 صباحاً | بقالة صباحاً |
| `day_of_week` | جمعة | عروض نهاية أسبوع |
| `device_type` | android | UX |
| `session_id` | uuid | ربط جلسة |
| `pvz_store_id` | متجر PVZ | قرب |
| `price_band` | منخفض/متوسط/عالي | حساسية سعر |

### و) Onboarding — بذرة الاهتمامات

| الإشارة | الحدث | الوزن ابتدائي |
|---------|-------|---------------|
| اختيار «بقالة» | `onboarding_interest` | +10 بقالة |
| اختيار «ملابس» | `onboarding_interest` | +10 ملابس |
| اختيار «إلكترونيات» | `onboarding_interest` | +10 إلكترونيات |

---

# 3. نموذج الاهتمامات (Interest Profile)

## 3.1 البنية

لكل مستخدم (أو `device_id` للزائر) ملف:

```
UserInterestProfile {
  user_id
  updated_at

  // تصنيفات (مجموع أوزان)
  category_scores: {
    "grocery": 45.2,
    "clothing": 12.0,
    "electronics": 8.5,
    ...
  }

  // ماركات
  brand_scores: { "Samsung": 5, ... }

  // متاجر مفضلة
  store_scores: { "store_uuid_1": 20, ... }

  // نطاق سعر مفضل (fils)
  price_p50: 1500000
  price_p90: 4500000

  // منتجات «توقف عندها» (آخر 30 يوم)
  dwell_products: [ product_global_id, score, last_at ]

  // embeddings (V2+)
  interest_vector: float[384]

  // شرائح للإعلانات
  segments: ["grocery_heavy", "price_sensitive", "evening_shopper"]
}
```

## 3.2 حساب الوزن — decay زمني

الاهتمام **يضعف** مع الوقت (مثل Ozon):

```
effective_weight = raw_weight × exp(-λ × days_since_event)

λ = 0.05  →  نصف العمر ~14 يوم
```

| حدث | raw_weight | بعد 7 أيام | بعد 30 يوم |
|-----|------------|------------|------------|
| product_view | 1 | 0.7 | 0.22 |
| dwell 4s+ | 4 | 2.8 | 0.88 |
| add_to_cart | 8 | 5.6 | 1.76 |
| purchase | 20 | 14 | 4.4 |

**الشراء يبقى أطول** — لا decay على `purchase_history` للإعادة الطلب.

## 3.3 شرائح جاهزة (Segments)

| الشريحة | الشرط | استخدام |
|---------|-------|---------|
| `grocery_heavy` | grocery score > 40% | بانر بقالة |
| `fashion_browser` | clothing dwell > 10/أسبوع | ملابس في الرئيسية |
| `price_sensitive` | 70% views تحت price_p50 | عروض خصم |
| `high_intent` | 3+ dwell_long بدون شراء | push «عرض خاص» |
| `cart_abandoner` | checkout_abandon ×2 | push سلة |
| `loyal_store_X` | store score > 25 | «جديد في متجرك المفضل» |
| `new_user` | < 5 أحداث | onboarding + trending |
| `evening_shopper` | 60% sessions بعد 6pm | push مسائي |

---

# 4. كيف تُبنى الصفحة الرئيسية المخصّصة

## 4.1 محرك التغذية (Feed Engine)

```
GET /feed/home?user_id=&neighborhood_id=

1. جلب UserInterestProfile (cache Redis/Supabase — TTL 5 د)
2. بناء قائمة «slots» (أقسام) بترتيب ديناميكي
3. لكل slot: استعلام منتجات + ranking
4. dedupe: لا نفس المنتج في قسمين
5. إرجاع JSON ordered sections
```

## 4.2 ترتيب الأقسام (Section Ordering)

**Pilot (P0):** ترتيب ثابت.

**V1 (P1):** ترتيب حسب `category_scores` الأعلى:

```
if grocery_score > clothing_score:
  order = [banner, grocery_shortcut, for_you_grocery, trending, stores, ...]
else:
  order = [banner, clothing_shortcut, for_you_fashion, ...]
```

**V2:** تعلم من `home_section_dwell` — الأقسام التي يتوقف عندها المستخدم ترتفع.

## 4.3 محتوى كل قسم

| section_id | العنوان العربي | مصدر المنتجات | تخصيص |
|------------|----------------|---------------|--------|
| `for_you` | **لك خصيصاً** | top categories × trending | ✅ كامل |
| `because_you_viewed` | **لأنك شاهدت** | similar to last 5 viewed | ✅ |
| `you_paused_here` | **توقفت عند هذه** | dwell_products list | ✅ **جديد** |
| `trending_hood` | **شائع في [الحي]** | neighborhood sales 7d | محلي |
| `repeat_buy` | **اشترِ مجدداً** | purchase history | ✅ |
| `new_in_fav_store` | **جديد في [متجر]** | store_id top | ✅ |
| `deals_for_you` | **عروض تناسبك** | promo × category_scores | ✅ |
| `explore` | **اكتشف** | cold start — تصنيفات لم يجرّب | تنويع |

## 4.4 معادلة Ranking داخل القسم

```
product_score =
    α × category_affinity(user, product.category)
  + β × dwell_similarity(user, product)      // V1+
  + γ × neighborhood_trend(product)
  + δ × store_affinity(user, product.store)
  + ε × rating
  - ζ × price_distance(user.price_p50, product.price)
  + η × freshness(new product boost)

// Pilot: α=0, β=0 — trending فقط
// V1: α=0.4, β=0.25, γ=0.2, ...
```

## 4.5 Cold Start (مستخدم جديد)

```
1. onboarding_interests (إن وُجد)
2. trending_hood (الحي)
3. best_rated stores
4. لا «لك خصيصاً» حتى ≥10 أحداث
```

---

# 5. التوقف والتصفّح — Dwell & Scroll Intelligence

> **هذا القلب — ما طلبته: «يراقب ما يشاهد ويقف عنده».**

## 5.1 مستويات الاهتمام من التوقف

```
┌────────────────────────────────────────────────────────────┐
│  مستوى 0: مرّ بسرعة (< 1.5s visible)     → تجاهل          │
│  مستوى 1: توقف قصير (1.5–4s)             → +2 interest    │
│  مستوى 2: توقف طويل (4–10s)              → +4 interest    │
│  مستوى 3: توقف + فتح المنتج              → +6 interest    │
│  مستوى 4: توقف + فتح + سلة               → +14 intent     │
│  مستوى 5: شراء                           → +20 confirmed    │
└────────────────────────────────────────────────────────────┘
```

## 5.2 قسم «توقفت عند هذه» — UX

```
┌─────────────────────────────────────────┐
│  توقفت عند هذه                          │
│  ─────────────────────────────────────  │
│  [منتج1] [منتج2] [منتج3] → scroll      │
│  «لا زال متوفراً — أضف للسلة؟»          │
└─────────────────────────────────────────┘
```

**قواعد العرض:**
- يظهر بعد **≥3** منتجات بـ `dwell_long` في 7 أيام
- max 12 منتج — الأحدث أولاً
- إخفاء المنتجات «نفدت»
- بعد الشراء → يختفي من القسم

## 5.3 ربط التوقف بالـ Push

| شرط | Push | توقيت |
|-----|------|-------|
| dwell_long ×2 على منتج + لا شراء | «لا زال [X] متوفر — 12,500 د.ع» | +24 ساعة |
| dwell + نفاد مخزون لاحقاً | «عاد [X] للمخزون» | فوري |
| dwell + خصم جديد | «خصم 15% على [X]» | فوري |
| dwell_long >5 بدون سلة | «هل تحتاج مساعدة؟» + واتساب | +48 ساعة (مرة/أسبوع max) |

**حدود:** max **2 push** مبنية على dwell / أسبوع — لا مضايقة.

## 5.4 Session Intelligence

```
session_summary (يُحسب عند app_background):
  - duration
  - categories_touched
  - max_dwell_product
  - cart_adds
  - intent_score (0–100)

intent_score > 70 && no_purchase
  → queue «سلة متروكة» أو «تذكير لاحق»
```

---

# 6. البحث الذكي والنوايا

## 6.1 V1 — بحث + affinities

```
ترتيب نتائج «حليب» =
  text_match_score
  × (1 + category_affinity(grocery))
  × neighborhood_availability
```

## 6.2 V2 — Embeddings عربية

```
query: «شي للبيت»
  → embedding
  → nearest products in vector space
  → filter by neighborhood + in_stock
```

**مصدر embeddings:** اسم + وصف + تصنيف — تحديث عند نشر منتج.

## 6.3 V3 — LLM Query Understanding

```
«هدية لأمي under 30 ألف»
  → LLM extracts: category=gift/beauty, max_price=3000000 fils
  → feed ranked list
```

---

# 7. الإعلانات المستهدفة (نفس محرك الاهتمامات)

> **V3 — ليس Pilot.** نفس `UserInterestProfile` + `segments`.

## 7.1 ما يستهدفه التاجر

```
حملة تاجر «سوبرماركت أ»:
  segment: grocery_heavy
  neighborhood: العشار
  min_dwell_grocery: 5 events/week
  exclude: purchased_from_competitor_last_7d
  budget: 10,000 د.ع/يوم
  bid: CPC 500 د.ع
```

## 7.2 أماكن الظهور

| مكان | trigger |
|------|---------|
| أعلى نتائج بحث «أرز» | query match + segment |
| بطاقة في feed «مميز» | category affinity |
| بانر رئيسية | CPM + segment |

## 7.3 Fairness

- 80% نتائج عضوية / 20% إعلان max
- شارة «إعلان» واضحة
- لا استهداف أطفال / فئات حساسة

---

# 8. المساعد الذكي (LLM) — مرحلة لاحقة

## 8.1 V3 — «مساعد نابو»

```
┌─────────────────────────────────────────┐
│  💬 اسأل نابو                           │
│  «أريد غداء سريع under 20 ألف»          │
└─────────────────────────────────────────┘
```

**RAG:** catalog محلي فقط — لا hallucinate منتجات.

## 8.2 استخدام Interest Profile

```
LLM system prompt includes:
  - top 3 categories
  - price band
  - favorite store
  → إجابات أقصر وأدق
```

---

# 9. الخصوصية والموافقة

## 9.1 موافقة صريحة (Opt-in)

```
شاشة بعد onboarding:

  «نخصّص تجربتك بناءً على ما تتصفّحه
   لنعرض منتجات تناسبك — يمكنك الإيقاف anytime»

  [ نعم، خصّص تجربتي ]    [ لا شكراً ]
```

| الاختيار | السلوك |
|----------|--------|
| **نعم** | كل الإشارات + تخصيص كامل |
| **لا** | trending عام فقط — **لا** dwell tracking للتخصيص |
| **إيقاف لاحقاً** | حسابي → «تخصيص الإعلانات والتوصيات» |

## 9.2 GDPR-like (حتى في العراق — best practice)

- تصدير «بياناتي»
- حذف ملف الاهتمامات
- لا بيع لطرف ثالث
- anonymize بعد 90 يوم للأحداث الخام

## 9.3 الشفافية للمستخدم

```
حسابي → «لماذا أرى هذا؟»
  → «لأنك توقفت عند منتجات بقالة هذا الأسبوع»
  → [ إخفاء هذا القسم ] [ إيقاف التخصيص ]
```

---

# 10. المعمارية التقنية

```
┌─────────────────────────────────────────────────────────────┐
│  Naboo Market (Flutter)                                      │
│  ┌─────────────────┐  ┌──────────────────────────────────┐ │
│  │ Analytics SDK   │  │ Feed UI                          │ │
│  │ (batch events)  │  │ GET /feed/home                   │ │
│  │ VisibilityDet.  │  │ sections from server             │ │
│  └────────┬────────┘  └──────────────────────────────────┘ │
└───────────┼─────────────────────────────────────────────────┘
            │ HTTPS batch (every 10s or app pause)
            ▼
┌─────────────────────────────────────────────────────────────┐
│  Supabase                                                    │
│  marketplace_events (raw)                                    │
│       ↓ nightly Edge Function                                │
│  user_interest_profiles (aggregated)                         │
│  user_segments                                               │
│       ↓ on-demand                                            │
│  Edge: get_home_feed(user_id)                                │
│  Edge: get_similar_products(product_id, user_id)            │
└─────────────────────────────────────────────────────────────┘
            │ V2+
            ▼
┌─────────────────────────────────────────────────────────────┐
│  pgvector — product_embeddings                               │
│  optional: external LLM API (V3 assistant only)              │
└─────────────────────────────────────────────────────────────┘
```

## 10.1 Client — قواعد الإرسال

| قاعدة | القيمة |
|-------|--------|
| Batch size | max 50 events |
| Flush | كل 10s · app background · before unload (web) |
| Offline queue | local SQLite/Hive — retry |
| Debounce dwell | 30s per product per session |
| Max events/session | 500 — ثم sample 50% |

---

# 11. نموذج البيانات

## 11.1 marketplace_events (raw)

```sql
CREATE TABLE marketplace_events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID,                    -- null للزائر
  device_id       TEXT NOT NULL,           -- دائماً
  session_id      TEXT NOT NULL,
  event_name      TEXT NOT NULL,           -- product_dwell, ...
  payload         JSONB NOT NULL DEFAULT '{}',
  -- payload examples:
  -- product_dwell: { product_global_id, duration_ms, screen: "pdp" }
  -- product_card_impression_dwell: { product_global_id, duration_ms, section_id }
  neighborhood_id TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_events_user_time ON marketplace_events(user_id, created_at DESC);
CREATE INDEX idx_events_device_time ON marketplace_events(device_id, created_at DESC);
CREATE INDEX idx_events_name ON marketplace_events(event_name, created_at DESC);
```

## 11.2 user_interest_profiles

```sql
CREATE TABLE user_interest_profiles (
  user_id           UUID PRIMARY KEY,
  category_scores   JSONB NOT NULL DEFAULT '{}',
  brand_scores      JSONB NOT NULL DEFAULT '{}',
  store_scores      JSONB NOT NULL DEFAULT '{}',
  dwell_products    JSONB NOT NULL DEFAULT '[]',
  price_p50_fils    INTEGER,
  price_p90_fils    INTEGER,
  segments          TEXT[] DEFAULT '{}',
  personalization_on BOOLEAN DEFAULT true,
  event_count       INTEGER DEFAULT 0,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

## 11.3 product_embeddings (V2)

```sql
CREATE TABLE product_embeddings (
  product_global_id TEXT PRIMARY KEY,
  embedding         vector(384),
  updated_at        TIMESTAMPTZ
);
```

## 11.4 ad_campaign_targets (V3)

```sql
CREATE TABLE ad_campaign_targets (
  campaign_id     UUID PRIMARY KEY,
  store_id        UUID NOT NULL,
  segments        TEXT[],
  neighborhoods   TEXT[],
  category_ids    TEXT[],
  min_dwell_score FLOAT,
  daily_budget_fils INTEGER,
  cpc_fils        INTEGER,
  is_active       BOOLEAN DEFAULT true
);
```

---

# 12. خط أنابيب المعالجة (Pipeline)

## 12.1 Real-time (خفيف)

```
event ingest → update session counter in Redis (optional)
             → if purchase → invalidate feed cache
```

## 12.2 Batch ليلي (02:00 Asia/Baghdad)

```
Job: aggregate_interests
  1. READ events last 30 days per user
  2. APPLY weights + decay
  3. COMPUTE category_scores, dwell_products, segments
  4. UPSERT user_interest_profiles
  5. LOG stats

Job: neighborhood_trending
  1. purchases last 7d by neighborhood
  2. WRITE cache trending_hood:{neighborhood_id}

Job: embedding_sync (V2 weekly)
  1. new/changed products → embed → product_embeddings
```

## 12.3 On-demand

```
get_home_feed(user_id):
  1. READ profile (or cold start)
  2. BUILD sections
  3. CACHE 5 minutes
  4. RETURN
```

---

# 13. مراحل الإطلاق — متى يُفعّل كل جزء

## 13.1 جدول المراحل

| ID | الاسم | الميزات | شرط التفعيل | Pilot؟ |
|----|-------|---------|-------------|--------|
| **AI-0** | Baseline | trending حي · onboarding | فوراً | ✅ |
| **AI-1** | Event Collection | product_view · add_to_cart · purchase | Market MVP live | ✅ جمع فقط |
| **AI-2** | Dwell Tracking | card dwell · section dwell · «توقفت عند» | ≥200 MAU · opt-in | ❌ V1 |
| **AI-3** | Feed Personalization | «لك خصيصاً» · because_you_viewed | ≥500 users · ≥10k events | ❌ V1 |
| **AI-4** | Dwell Push | push بعد توقف | AI-2 + opt-in | ❌ V1.5 |
| **AI-5** | Search Rank | affinities in search | AI-3 | ❌ V2 |
| **AI-6** | Embeddings | semantic search | ≥5k products | ❌ V2 |
| **AI-7** | Ad Targeting | segments for merchants | ≥50 merchants · AI-3 | ❌ V3 |
| **AI-8** | LLM Assistant | chat helper | budget + moderation | ❌ V3 |

## 13.2 Pilot — ماذا يُفعّل فعلاً؟

```
✅ AI-0: trending + onboarding interests
✅ AI-1: جمع أحداث basic (view, cart, purchase) — بدون عرض مخصّص
❌ AI-2+: لا dwell UI · لا «لك خصيصاً» · لا push dwell
```

**لماذا؟** 200 مستخدم في العشار = بيانات قليلة — التخصيص المبكر **يضر** (cold start noise).

## 13.3 خارطة زمنية مقترحة

```
Pilot (شهر 0–3):   AI-0 + AI-1 (جمع صامت)
V1 (شهر 4–6):      AI-2 + AI-3 + opt-in UI
V1.5 (شهر 6–8):    AI-4 (push dwell)
V2 (شهر 8–12):     AI-5 + AI-6
V3 (سنة 2):        AI-7 + AI-8
```

---

# 14. معايير الجودة والاختبار

## 14.1 A/B Tests

| Test | A | B | metric |
|------|---|---|--------|
| Feed-001 | trending only | personalized | conversion rate |
| Dwell-001 | no «توقفت عند» | with section | CTR section |
| Push-001 | no dwell push | dwell push 24h | purchase / unsubscribe |

## 14.2 Anti-patterns (فشل)

| Symptom | Cause | Fix |
|---------|-------|-----|
| نفس المنتج everywhere | over-weight one view | dedupe + diversity injection |
| «ملابس» لمن يشتري بقالة فقط | wrong segment | purchase > dwell weight |
| push كثير | aggressive dwell rules | caps |
| feed بطيء | heavy realtime ML | batch + cache |

## 14.3 Diversity Rule

```
في كل feed: max 60% من top category
             min 20% «explore» (categories جديدة)
```

---

# 15. مؤشرات النجاح (KPIs)

| KPI | AI-0 | AI-3 target |
|-----|------|-------------|
| CTR قسم «لك خصيصاً» | — | > 8% |
| CTR «توقفت عند هذه» | — | > 12% |
| conversion vs baseline | baseline | +15% |
| time on home | — | +20% |
| push opt-out rate | — | < 5% |
| dwell → purchase (7d) | — | > 3% |

---

# 16. ما لا نفعله

| ❌ | السبب |
|----|--------|
| تتبع GPS دقيق | خصوصية |
| تسجيل شاشة | illegal creep |
| تخصيص بدون opt-in | ثقة |
| AI في Pilot UI | لا بيانات |
| بيع بيانات لإعلانات خارجية | سمعة |
| LLM يختلق أسعار | خطر قانوني |
| أوزان dwell > purchase | قرارات خاطئة |

---

## الخاتمة

```
المراقبة:  view · dwell · scroll stop · cart · search · purchase
      ↓
الملف:     category_scores · dwell_products · segments
      ↓
المخرجات:  رئيسية · push · بحث · إعلانات (لاحقاً)
      ↓
الشرط:     opt-in · batch · مراحل · Pilot = جمع فقط
```

**Pilot:** اجمع الأحداث بصمت — **لا تُظهر** «توقفت عند هذه» حتى V1 و500+ مستخدم.

---

**نهاية الوثيقة**

*الإصدار: 1.0 | 2026-06-20 | تخطيط — لا كود*

*مرجع سريع للمطور القادم: [`naboo_market_master_plan_v1.md`](./naboo_market_master_plan_v1.md) §8*
