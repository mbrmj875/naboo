# بحث Ozon على GitHub — ما يفيد Naboo Market
## تقرير مرجعي v1.0 | كود مفتوح · APIs · معمارية

> **التاريخ:** 2026-06-20  
> **الغرض:** فهم ما هو متاح فعلياً على GitHub حول Ozon، وما يمكن الاستفادة منه لبناء **Naboo Market** (نموذج Ozon/WB للعراق)  
> **المراجع الداخلية:** [`naboo_market_complete_reference_v1.md`](./naboo_market_complete_reference_v1.md)  

---

## فهرس المحتويات

1. [الخلاصة التنفيذية — اقرأ هذا أولاً](#1-الخلاصة-التنفيذية--اقرأ-هذا-أولا)
2. [ما Ozon لا ينشره على GitHub](#2-ما-ozon-لا-ينشره-على-github)
3. [خريطة GitHub — 5 فئات](#3-خريطة-github--5-فئات)
4. [الفئة 1: Seller API (للتجار — ليس تطبيق المستهلك)](#4-الفئة-1-seller-api-للتجار--ليس-تطبيق-المستهلك)
5. [الفئة 2: Composer API (واجهة المستهلك — غير رسمي)](#5-الفئة-2-composer-api-واجهة-المستهلك--غير-رسمي)
6. [الفئة 3: معمارية Ozon الرسمية (مقالات + مبادئ)](#6-الفئة-3-معمارية-ozon-الرسمية-مقالات--مبادئ)
7. [الفئة 4: مشاريع تعليمية مستوحاة من Ozon](#7-الفئة-4-مشاريع-تعليمية-مستوحاة-من-ozon)
8. [الفئة 5: Ozon Tech الرسمي (بنية تحتية — ليس marketplace)](#8-الفئة-5-ozon-tech-الرسمي-بنية-تحتية--ليس-marketplace)
9. [مقارنة: ماذا يفيد Naboo Pilot vs V2+](#9-مقارنة-ماذا-يفيد-naboo-pilot-vs-v2)
10. [دروس معمارية قابلة للنقل إلى Naboo](#10-دروس-معمارية-قابلة-للنقل-إلى-naboo)
11. [دروس منتج/UX من Ozon](#11-دروس-منتجux-من-ozon)
12. [ما لا تنسخه — فخاخ شائعة](#12-ما-لا-تنسخه--فخاخ-شائعة)
13. [قائمة مراقبة GitHub موصى بها](#13-قائمة-مراقبة-github-موصى-بها)
14. [خطة عمل عملية لـ Naboo](#14-خطة-عمل-عملية-لـ-naboo)

---

# 1. الخلاصة التنفيذية — اقرأ هذا أولاً

## الحقيقة المهمة

> **Ozon لا ينشر كود تطبيق المستهلك (ozon.ru / تطبيق الجوال) كمشروع مفتوح على GitHub.**

ما تجده على GitHub يقع في أحد هذه السلال:

| السلّة | لمن؟ | هل يفيد Naboo Market؟ |
|--------|------|------------------------|
| **Seller API + SDKs** | التاجر يربط مخزونه | ⚠️ **جزئياً** — لاحقاً لربط ERP متقدم |
| **Composer API parsers** | reverse-engineering واجهة المستهلك | ❌ **لا تبنِ عليه** — غير رسمي + anti-bot |
| **مقالات Ozon Tech (Habr)** | معمارية Composer/BDUI | ✅ **أفكار** — ليس كوداً جاهزاً |
| **go-ozon-marketplace** | pet project تعليمي | ✅ **أنماط** Saga/Outbox/CQRS |
| **Ozon Tech OSS** | file.d, pg_doorman, cute | ⏳ **لاحقاً** عند scale |

## القرار لـ Naboo

```
Pilot (الآن):     Flutter + Supabase + marketplace_*  ← ما بُني فعلاً
                  لا تبحث عن «كود Ozon جاهز» — لن تجده

V1 (تعلّم):       مقالات Composer + OpenAPI Seller API كمرجع مجالات
V2 (ERP sync):    أنماط product/import/stocks من Seller API
V3 (scale):       Saga/Outbox إذا تجاوزت آلاف الطلبات/يوم
```

**لا تخلط:** `Apache Ozone` (تخزين Hadoop) ≠ `Ozon.ru` (ماركت بليس).

---

# 2. ما Ozon لا ينشره على GitHub

| المكوّن | الحالة | البديل للتعلّم |
|---------|--------|----------------|
| تطبيق Android/iOS للمستهلك | مغلق | لقطات شاشة WB/Ozon + [`naboo_market_ui_wildberries_inspired_v1.md`](./naboo_market_ui_wildberries_inspired_v1.md) |
| Composer Core (BDUI engine) | مغلق — مقال Habr فقط | [مقال Habr §6](#composer-bdui) |
| كود PVZ / لوجستيك داخلي | مغلق | Seller API: `/v1/delivery/point/list` كمرجع **مفاهيم** |
| قاعدة بيانات المنتجات | مغلق | `marketplace_products` في Supabase |
| محفظة مستهلك + استرداد | مغلق | [`naboo_market_consumer_wallet_refunds_v1.md`](./naboo_market_consumer_wallet_refunds_v1.md) |

Ozon Tech صرّحوا صراحة: منتج Composer **لن يصبح open-source** لأنه مرتبط ببنية Ozon الداخلية — لكن **المبادئ** قابلة للنقل.

---

# 3. خريطة GitHub — 5 فئات

```
GitHub + Ozon
│
├── [A] Seller API SDKs ──────────── للتاجر (ERP integration)
│     Python · PHP · Go · TypeScript
│
├── [B] Composer API scrapers ────── للمستهلك (غير رسمي ⚠️)
│     MCP server · gists · Apify
│
├── [C] OpenAPI specs mirror ─────── 460+ endpoint مرجع
│     MissiaL/ozon-api · phpsoftbox/ozon
│
├── [D] Architecture pet projects ── Saga · Outbox · CQRS
│     ekhodzitsky/go-ozon-marketplace
│
└── [E] Ozon Tech official OSS ───── infra (ليس marketplace)
      github.com/ozontech
```

---

# 4. الفئة 1: Seller API (للتجار — ليس تطبيق المستهلك)

## ما هو؟

**Ozon Seller API** = واجهة للتجار لإدارة:
- المنتجات والأسعار والمخزون
- الطلبات FBS/FBO/rFBS
- اللوجستيك والمستودعات
- **PVZ / نقاط التسليم** (`/v1/delivery/point/list`)
- المالية والعمولات
- التقييمات والأسئلة

**Base URL:** `https://api-seller.ozon.ru`  
**التوثيق الرسمي:** https://docs.ozon.ru/api/seller/  
**OpenAPI:** https://api-seller.ozon.ru/docs/openapi.json (422+ عملية، 68 tag)

> هذا API **للتاجر** الذي يبيع على Ozon — **ليس** API لتطبيق المستهلك الذي يتصفّح ويطلب.

## مستودعات GitHub المفيدة

### 4.1 مرجع OpenAPI كامل (الأهم للفهم)

| Repo | الرابط | الفائدة لـ Naboo |
|------|--------|------------------|
| **MissiaL/ozon-api** | https://github.com/MissiaL/ozon-api | 460 عملية Seller + 48 Performance — **فهرس كامل** لمجالات النظام |
| **phpsoftbox/ozon** | https://github.com/phpsoftbox/ozon | 421 endpoint مغطّى + `docs/swagger.json` + migration matrix |
| **salacoste/ozon-daytona-seller-api** | https://github.com/salacoste/ozon-daytona-seller-api | 278 method في 33 فئة — **خريطة وظيفية** |

**كيف تستفيد بدون تنفيذ Ozon API:**

استخدم هذه المستودعات كـ **قائمة تحقق** — «ما الذي يحتاجه أي ماركت بليس كامل؟»

| فئة Ozon Seller API | ما يعادله في Naboo (حالياً/مخطط) |
|---------------------|----------------------------------|
| Products — import/list/prices/stocks | `marketplace_products` + Concierge + ERP sync |
| FBS Orders — posting/list/accept | `marketplace_orders` + ERP online orders |
| Delivery — point/list, map, checkout | PVZ في onboarding + `pickup_store_id` |
| Finance — transactions, commission | عمولة 0.5–3% — لاحقاً `commission_fils` |
| Review / Question | V2 تقييمات |
| Notification — push to seller | FCM للتاجر في ERP |
| Analytics — top products | V1 trending في `HomeFeedProvider` |
| Warehouse / carriage / logistics | **Pilot:** مندوب يدوي — V3+ |

### 4.2 SDKs حسب اللغة

| Repo | لغة | Stars | ملاحظة |
|------|-----|-------|--------|
| [a-ulianov/OzonAPI](https://github.com/a-ulianov/OzonAPI) | Python async + Pydantic | ~22 | rate limit · OAuth · stocks/prices |
| [ashirchkov/ozon-sdk](https://github.com/ashirchkov/ozon-sdk) | PHP | — | v2.0.6 — product list مثال |
| [s1berc0de/ozon-api-client](https://github.com/s1berc0de/ozon-api-client) | Go | — | endpoints catalog مُوثّق |
| [ucoms-dev/ozon-api-client](https://github.com/ucoms-dev/ozon-api-client) | Go | — | webhooks للإشعارات |
| [mephistofox/python-ozon-api](https://github.com/mephistofox/python-ozon-api) | Python | — | الأصل الذي فُرع منه OzonAPI |

**لـ Naboo:** لا تحتاج SDK Ozon في Pilot. **لاحقاً** إذا ربطت تاجراً يبيع **على Ozon وعلى Naboo** معاً — Python/Go SDK مفيد كمرجع لـ **sync patterns** (import stocks, update prices).

### 4.3 مجموعات API حسب الوظيفة (من daytona docs)

| المجموعة | أمثلة endpoints | درس لـ Naboo |
|----------|-----------------|--------------|
| **Catalog** | product import, attributes, pictures | صور متعددة · `images[]` · `product_global_id` |
| **Pricing & Stocks** | import/prices, import/stocks | `price_fils` int · `in_stock` boolean — **نفس منطق ERP** |
| **Orders FBS** | posting list, ship, cancel | حالات طلب = enum — لديك `marketplace_order_status` |
| **Delivery / PVZ** | `point/list`, `map`, `checkout` | اختيار PVZ في onboarding — **مثل Ozon** |
| **Finance** | balance, transactions | محفظة تاجر V2+ |
| **Promos / Pricing strategy** | акции, стратегии | عروض Pilot — بانر يدوي |
| **Reviews** | review list, answer | V2 ثقة |

---

# 5. الفئة 2: Composer API (واجهة المستهلك — غير رسمي)

## ما هو Composer؟

**Composer** = محرك Ozon الداخلي الذي يغذّي **تطبيق المستهلك** وموقع ozon.ru.

الاستجابة تأتي كـ **شجرة widgets**:

```json
{
  "layout": [ /* شجرة مكوّنات */ ],
  "widgetStates": {
    "searchResultsV2-xxx": "{...json string...}",
    "webSale-xxx": "{...product price...}",
    "cartButton-xxx": "{...}"
  }
}
```

**Endpoint عام (غير موثّق رسمياً للمطورين الخارجيين):**

```
https://api.ozon.ru/composer-api.bx/page/json/v2?url=/product/...
```

## مستودعات reverse-engineering

| Repo / أداة | الرابط | ماذا يفعل |
|-------------|--------|-----------|
| **eduard256/ozon-mcp-server** | https://github.com/eduard256/ozon-mcp-server | headless Chromium يتجاوز anti-bot · يقرأ `widgetStates` |
| **Gist ionstudio** | https://gist.github.com/ionstudio/9fc5e90d8c8ac2e91bd60c82c442e018 | كيف تستخرج seller, description, cartButton من layout |
| **Gist DxDiagDx** | https://gist.github.com/DxDiagDx/710ac65e117bdd45d4dbb3c64d07849c | parser Python بسيط — `webSale` → price |
| **Apify ozon-scraper** | https://apify.com/ahaham_bytiz/ozon-scraper | `searchResultsV2` widget |

## widgets معروفة (مفيدة كمرجع UX/data model)

| Widget component | البيانات | درس لـ Naboo |
|------------------|----------|--------------|
| `searchResultsV2` | قائمة منتجات البحث | شبكة كثيفة — مثل home feed |
| `webSale` | title, price, finalPrice, id | سعر + سعر قديم + خصم |
| `cartButton` | CTA إضافة للسلة | زر ذهبي دائري على البطاقة |
| `seller` | اسم البائع | **اسم فقط** — مثل سياسة Naboo |
| `skuScroll` | متغيرات (لون/مقاس) | `variants_json` في V1 |
| `marketingActions` | شارات عروض | `-15%` badge |

## ⚠️ لماذا لا تبني Naboo على Composer API

| السبب | التفصيل |
|-------|---------|
| **غير رسمي** | Ozon قد يغيّر widget names في أي لحظة |
| **Anti-bot (Variti)** | يحتاج browser حقيقي — غير مناسب لتطبيق إنتاج |
| **قانوني/ToS** | scraping قد يخالف شروط Ozon |
| **لا علاقة ببياناتك** | Naboo يقرأ `marketplace_products` من Supabase |

**الاستفادة الصحيحة:** افهم **شكل البيانات** التي يتوقعها UI (سعر، خصم، بائع، صور) — وابنِ نفس الحقول في API Naboo.

---

# 6. الفئة 3: معمارية Ozon الرسمية (مقالات + مبادئ)

<a id="composer-bdui"></a>

## 6.1 Composer / Backend-Driven UI (مقال Habr الرئيسي)

**المقال:** [«Собираем данные из сотни микросервисов»](https://habr.com/ru/companies/ozontech/articles/839214/) — Ozon Tech، 2024

### الفكرة في 3 كلمات: **كُبَيْكَات (Widgets)**

Ozon قسّم الواجهة إلى:

| الكيان | الدور | مثال |
|--------|-------|------|
| **Widget** | قطعة UI + state | بطاقة منتج، زر سلة، بانر |
| **Parameter** | بيانات مشتركة | user_id, city, currency, cart_count |
| **Action** | تفاعل مستخدم | add_to_cart, change_pvz |

**Core service (Composer Core):**
1. يستقبل طلب صفحة
2. يختار **template** حسب قواعد (مدينة، A/B، مسجّل/زائر)
3. يبني **graf** resolve-providers
4. يجمع `widgetStates` مرة واحدة (بدون تكرار طلبات)
5. يرسل JSON للعميل (موبايل/ويب)

### لماذا Ozon فعل هذا؟

- **2000+ مطور** في **100+ فريق**
- تغيير الرئيسية **عدة مرات يومياً** بدون نشر تطبيق
- A/B tests على مستوى **القالب** لا الكود

### هل Naboo يحتاج Composer في Pilot؟

```
❌ Pilot:     Flutter widgets ثابتة + Supabase — كافٍ
⚠️ V1:        «أقسام ديناميكية» عبر JSON config من Supabase
✅ V2+:       BDUI خفيف إذا أصبح لديك 10+ فرق تطوّر الواجهة
```

**بديل Naboo خفيف (بدون مئات microservices):**

```sql
-- جدول home_sections في Supabase
CREATE TABLE marketplace_home_sections (
  id TEXT PRIMARY KEY,
  type TEXT,  -- 'banner' | 'product_grid' | 'category_row'
  title_ar TEXT,
  config JSONB,
  sort_order INT,
  neighborhood_id TEXT,
  is_active BOOLEAN
);
```

Flutter يقرأ الأقسام ويرسم widget مناسب — **80% فائدة Composer بدون 80% التعقيد**.

## 6.2 مقالات Ozon Tech إضافية

| المقال | الرابط | الدرس لـ Naboo |
|--------|--------|----------------|
| ميكروسيرفس + مئات الخدمات | [Habr 839214](https://habr.com/ru/companies/ozontech/articles/839214/) | فصل catalog / orders / payments |
| بаланسировка تكيّفية | [Habr 558926](https://habr.com/ru/companies/ozontech/articles/558926/) | ⏳ عند scale — ليس Pilot |
| multi-DC load testing | [Habr 667908](https://habr.com/ru/companies/ozontech/articles/667908/) | ⏳ بعيد جداً عن Pilot |
| Kafka 5M RPS | ozon.tech | Outbox pattern — V3 |

---

# 7. الفئة 4: مشاريع تعليمية مستوحاة من Ozon

## 7.1 go-ozon-marketplace ⭐ الأهم للمعمارية

**الرابط:** https://github.com/ekhodzitsky/go-ozon-marketplace  
**الوصف:** pet project — «production-grade» marketplace backend على Go  
**الوثائق:** [`docs/design.md`](https://github.com/ekhodzitsky/go-ozon-marketplace/blob/master/docs/design.md) · [`docs/DECISION_LOG.md`](https://github.com/ekhodzitsky/go-ozon-marketplace/blob/master/docs/DECISION_LOG.md)

### 8 خدمات

| Service | التخزين | الأنماط |
|---------|---------|---------|
| api-gateway | — | GraphQL · rate limit |
| user-service | PostgreSQL | JWT |
| catalog-service | PG + Elasticsearch | **CQRS** |
| order-service | PostgreSQL | **Saga** · **Outbox** |
| inventory-service | PG + Redis | optimistic lock |
| payment-service | PostgreSQL | Saga participant · DLQ |
| notification-service | — | Kafka consumer |
| analytics-service | ClickHouse | events |

### تدفق الطلب (Saga)

```
CreateOrder → ReserveInventory → ProcessPayment → ConfirmOrder
       ↓              ↓                ↓
   Cancel ←── ReleaseStock ←── Refund (compensation)
```

### ما تنسخه لـ Naboo **الآن**

| النمط | Pilot | متى |
|-------|-------|-----|
| Saga orchestrator | ❌ | transaction بسيط في Supabase Edge Function |
| Outbox + Kafka | ❌ | >1000 طلب/يوم |
| CQRS + Elasticsearch | ❌ | بحث متقدم V2 |
| **حالات طلب واضحة** | ✅ | لديك `marketplace_order_status` |
| **فصل catalog/orders** | ✅ | جداول منفصلة |
| **server-side price validation** | ✅ | `POST /orders` يعيد حساب الأسعار |

### قرارات ADR مفيدة (من DECISION_LOG)

| القرار | السبب | Naboo |
|--------|-------|-------|
| Saga **Orchestrator** لا Choreography | ترتيب صارم: لا دفع قبل حجز مخزون | نفس المنطق في Edge Function |
| Kafka + Outbox لا gRPC مباشر للأحداث | at-least-once بدون 2PC | Supabase Realtime + outbox table لاحقاً |
| GraphQL للعميل | تقليل round-trips | Pilot: REST/Supabase مباشر كافٍ |

---

# 8. الفئة 5: Ozon Tech الرسمي (بنية تحتية — ليس marketplace)

**المنظمة:** https://github.com/ozontech

| Repo | الوصف | متى يفيد Naboo |
|------|--------|----------------|
| [file.d](https://github.com/ozontech/file.d) | data pipelines | تحليلات سلوك V2+ |
| [pg_doorman](https://github.com/ozontech/pg_doorman) | PostgreSQL pooler | إذا انتقلت من Supabase لـ PG مخصص |
| [cute](https://github.com/ozontech/cute) | HTTP testing + Allure | اختبار E2E لـ Edge Functions |
| [kelp](https://github.com/ozontech/kelp) | Compose design systems | مرجع إذا انتقلت Market لـ Compose |
| [testo](https://github.com/ozontech/testo) | Go testing framework | — |
| [allure-go](https://github.com/ozontech/allure-go) | test reports | QA |

**لا يوجد** في ozontech: marketplace app · catalog service · PVZ service.

---

# 9. مقارنة: ماذا يفيد Naboo Pilot vs V2+

## جدول القرار السريع

| المصدر | Pilot (90 يوم) | V1 | V2+ |
|--------|----------------|-----|-----|
| Seller API OpenAPI (MissiaL) | 📖 مرجع مجالات | 📖 تصميم ERP sync | 🔧 إن ربطت بائع Ozon |
| Composer widget model | 📖 شكل بيانات UI | 📖 أقسام ديناميكية JSON | ⚠️ BDUI خفيف |
| ozon-mcp-server / scrapers | ❌ | ❌ | ❌ |
| go-ozon-marketplace Saga | ❌ | 📖 | 🔧 Edge Functions |
| Habr Composer article | 📖 | 📖 | 🔧 |
| Ozon Tech cute/testo | ⏳ | 🔧 E2E tests | 🔧 |
| daytona API categories | 📖 checklist | 📖 | 🔧 |

**رموز:** 📖 = اقرأ وتعلّم · 🔧 = نفّذ · ❌ = تجاهل · ⏳ = لاحقاً

## ما يعادل Ozon في Naboo اليوم

| Ozon | Naboo (مُنفّذ/مخطط) |
|------|---------------------|
| Composer home feed | `HomeScreen` + `HomeFeedProvider` |
| PVZ selection | `OnboardingScreen` + `LocationProvider` |
| Product card widget | `MarketProductCard` |
| Seller API products | `marketplace_products` |
| FBS order flow | `marketplace_orders` + ERP screen |
| COD checkout | `CartScreen` (جزئي) |
| `searchResultsV2` | `MarketSearchBar` (UI فقط — بحث V1) |

---

# 10. دروس معمارية قابلة للنقل إلى Naboo

## 10.1 من Ozon Composer

| الدرس | تطبيق Naboo |
|-------|-------------|
| الصفحة = قائمة widgets | الرئيسية = `CustomScrollView` + slivers |
| بيانات مشتركة تُحسب مرة | `LocationProvider` + cart count في Provider واحد |
| قواعد عرض حسب المدينة | `neighborhood_id` في كل query |
| فصل state عن rendering | Provider للبيانات · Widget للعرض |

## 10.2 من Seller API

| الدرس | تطبيق Naboo |
|-------|-------------|
| product import async | Concierge يرفع · `is_published` لاحقاً |
| stocks منفصلة عن product | `in_stock` boolean — V1: كمية |
| order posting lifecycle | enum statuses بالعربي |
| delivery point list | `marketplace_stores` where `is_pickup_point` |
| pickup code verify | `pickup_code` في الطلب |

## 10.3 من go-ozon-marketplace

| الدرس | تطبيق Naboo |
|-------|-------------|
| لا تثق بسعر العميل | `POST /orders` server-side validation |
| inventory reservation | تحقق `in_stock` قبل confirm |
| idempotent order create | `idempotency_key` على الطلب |
| notification on state change | FCM + Realtime |
| soft delete للمالية | `deleted_at` في ERP — نفس المبدأ |

---

# 11. دروس منتج/UX من Ozon

## 11.1 من Composer widgets

| نمط Ozon | Naboo |
|----------|-------|
| صورة 70% من البطاقة | `MarketProductCard` — flex 7:3 |
| سعر + سعر قديم + % | `discountPercent` + line-through |
| زر سلة على الصورة | `_CartFab` ذهبي |
| شريط بحث pill دائم | `MarketSearchBar` |
| PVZ في الأعلى دائماً | header onboarding |
| أقسام أفقية + شبكة | trending + infinite grid |

## 11.2 من Seller API (تجربة تاجر)

| نمط Ozon | Naboo Pilot |
|----------|-------------|
| تاجر يرى طلبات FBS في لوحة | ERP `online_orders_screen` |
| إشعار طلب جديد | FCM |
| قبول/رفض/جاهز للشحن | `accepted` → `ready_to_ship` |
| تقييم البائع | V2 |

## 11.3 PVZ (من delivery endpoints)

| Ozon | Naboo |
|------|-------|
| خريطة نقاط | V1: قائمة — V2: `pickup_latitude/longitude` |
| `point/list` | `marketplace_stores_public` |
| checkout يختار PVZ | `pickup_store_id` في الطلب |
| مهلة استلام | 5 أيام Pilot |

---

# 12. ما لا تنسخه — فخاخ شائعة

| الفخ | لماذا |
|------|-------|
| بناء Market على Composer API | غير مستقر · anti-bot · ليس لبياناتك |
| نسخ microservices Ozon في Pilot | 3 طلبات/يوم لا تحتاج Kafka |
| استخدام Seller API في تطبيق المستهلك | API للتاجر — مفاتيح سرية |
| تبنّي GraphQL + 8 services الآن | Supabase + Flutter أبسط وأسرع |
| نسخ UI بنفسجي Ozon القديم | Naboo = **كحلي + ذهب** |
| Apache Ozone | مشروع تخزين مختلف تماماً |
| `@Ozon-Seller-API` org على GitHub | منظمة غير رسمية (US) — احذر |

---

# 13. قائمة مراقبة GitHub موصى بها

## للمعمارية والتعلّم

| Repo | لماذا تراقبه |
|------|--------------|
| [ekhodzitsky/go-ozon-marketplace](https://github.com/ekhodzitsky/go-ozon-marketplace) | Saga · Outbox · ADR |
| [MissiaL/ozon-api](https://github.com/MissiaL/ozon-api) | OpenAPI محدّث |
| [ozontech](https://github.com/ozontech) | أدوات infra |

## للـ ERP sync (لاحقاً)

| Repo | لماذا |
|------|-------|
| [a-ulianov/OzonAPI](https://github.com/a-ulianov/OzonAPI) | stocks/prices patterns |
| [phpsoftbox/ozon](https://github.com/phpsoftbox/ozon) | migration matrix كاملة |

## للبحث والـ AI (V2 — ليس scraping إنتاج)

| Repo | لماذا |
|------|-------|
| [eduard256/ozon-mcp-server](https://github.com/eduard256/ozon-mcp-server) | فهم `widgetStates` structure |

## بدائل marketplace مفتوحة (للمقارنة — ليس Ozon)

| Repo | ملاحظة |
|------|--------|
| [mercurjs/mercur](https://github.com/mercurjs/mercur) | multi-vendor على Medusa — **أقرب** لمشروع marketplace كامل مفتوح |
| MedusaJS | Node — مختلف عن stack Naboo |

> **Mercur** مفيد إذا أردت «كود marketplace كامل» للدراسة — لكن Naboo مبني على Flutter+Supabase وليس Medusa.

---

# 14. خطة عمل عملية لـ Naboo

## المرحلة 0 — الآن (Pilot)

```
✅ لا تبحث أكثر عن «كود Ozon للمستهلك»
✅ أكمل: SQL · Market UI · POST order · ERP orders
📖 اقرأ: Habr Composer (مبادئ widgets فقط)
📖 راجع: MissiaL/ozon-api → قائمة مجالات النظام
```

## المرحلة 1 — بعد 3 طلبات مُسلّمة

```
□ home_sections JSON (BDUI خفيف)
□ بحث نصي على marketplace_products
□ تقييمات بسيطة
□ ربط ERP: product_global_id sync
```

## المرحلة 2 — 10+ تجار

```
□ Edge Function POST /orders (Saga مبسّط)
□ outbox table للأحداث
□ FCM state machine كامل
□ دراسة Mercur/Medusa لـ multi-vendor patterns فقط
```

## المرحلة 3 — scale

```
□ CQRS للبحث (إن لزم)
□ go-ozon-marketplace patterns كاملة
□ ozontech/pg_doorman إن خرجت من Supabase managed
```

---

## ملحق أ — روابط سريعة

### رسمية

| المورد | URL |
|--------|-----|
| Ozon Seller API docs | https://docs.ozon.ru/api/seller/ |
| Ozon Dev platform | https://dev.ozon.ru/ |
| OpenAPI | https://api-seller.ozon.ru/docs/openapi.json |
| API sandbox | https://api-seller.ozon.ru/docs/ |
| Ozon Tech blog | https://habr.com/ru/companies/ozontech/ |
| Telegram dev community | https://t.me/ozon_api_chat |

### GitHub — أفضل 10 للمرجعية

1. https://github.com/MissiaL/ozon-api — OpenAPI كامل  
2. https://github.com/ekhodzitsky/go-ozon-marketplace — معمارية  
3. https://github.com/salacoste/ozon-daytona-seller-api — 278 methods indexed  
4. https://github.com/phpsoftbox/ozon — swagger snapshot + matrix  
5. https://github.com/a-ulianov/OzonAPI — Python async SDK  
6. https://github.com/eduard256/ozon-mcp-server — Composer widgets  
7. https://github.com/ozontech — infra official  
8. https://github.com/mercurjs/mercur — marketplace OSS للمقارنة  
9. https://gist.github.com/ionstudio/9fc5e90d8c8ac2e91bd60c82c442e018 — Composer parsing  
10. https://github.com/ashirchkov/ozon-sdk — PHP SDK example  

---

## ملحق ب — جملة واحدة للإجابة على «أين كود Ozon؟»

> **كود تطبيق المستهلك Ozon غير مفتوح.** على GitHub تجد: (1) **Seller API** للتجار، (2) **reverse-engineering** لواجهة المستهلك عبر Composer، (3) **مشاريع تعليمية** للمعمارية، (4) **بنية تحتية** Ozon Tech. **Naboo الصحيح = Flutter + Supabase + أفكار Ozon — ليس fork من repo Ozon.**

---

*الإصدار: 1.0 | 2026-06-20 | بحث GitHub + Ozon Tech + تطبيق على Naboo Market*
