# Naboo Market — المرجع الشامل الوحيد
## التطبيق الثاني · كل ما ناقشناه في محادثة واحدة

> **الحالة:** مرجع رئيسي — **اقرأ هذا الملف أولاً** قبل أي وثيقة Market أخرى  
> **التاريخ:** 2026-06-20  
> **الإصدار:** 1.0  
> **المشروع:** `/Users/mohamed123/Development/naboo_market` (Flutter)  
> **ERP:** `/Users/mohamed123/Development/projict/basra_store_manager`  
> **Supabase:** مشروع واحد مشترك — `https://rkofqwcuvbzrnmelvxhz.supabase.co`  

---

## كيف تستخدم هذا الملف

| إذا كنت… | اذهب إلى |
|----------|----------|
| تريد فهم الفكرة بسرعة | [§1](#1-الملخص-التنفيذي) |
| تريد تشغيل التطبيق الآن | [§13](#13-إعداد-supabase) · [§14](#14-تشغيل-التطبيق) |
| مطور Flutter | [§9](#9-مشروع-flutter) · [§10](#10-الشاشات-والمسارات) · [§12](#12-حالة-التنفيذ) |
| مسؤول Concierge / مبيعات | [§4](#4-pilot-90-يوم) · [§5](#5-concierge-والتجار) |
| مصمم UI | [§11](#11-uiux--wildberries--ألوان-نابو) |
| تخطط للمستقبل (AI · محفظة · دفع) | [§15](#15-بعد-pilot--v2) |

**وثائق تفصيلية فرعية** (اختيارية — هذا الملف يلخّصها):

| ملف | متى تقرأه |
|-----|-----------|
| `naboo_market_mvp_spec_v1.md` | تفاصيل API/SQL تقنية |
| `naboo_market_ui_wildberries_inspired_v1.md` | Figma / مكوّنات UI |
| `naboo_market_ai_personalization_v1.md` | AI V1+ |
| `naboo_market_consumer_wallet_refunds_v1.md` | محفظة V2 |
| `naboo_market_payments_v1.md` | Zain/FIB/بطاقة V2 |
| `naboo_pilot_90_days_v1.md` | KPIs يومية |
| `naboo_concierge_ops_playbook_v1.md` | يوم بيوم للمندوب |
| `naboo_merchant_agreement_pilot_v1.md` | عقد التاجر |

> ⚠️ **ملغى — لا تستخدم:** `naboo_payment_master_plan_v1.md` (اشتراك ERP 15,000 د.ع/شهر — **ليس** Market)

---

## فهرس المحتويات

1. [الملخص التنفيذي](#1-الملخص-التنفيذي)
2. [التطبيقان — الفرق والربط](#2-التطبيقان--الفرق-والربط)
3. [نموذج العمل والعمولة](#3-نموذج-العمل-والعمولة)
4. [Pilot 90 يوم](#4-pilot-90-يوم)
5. [Concierge والتجار](#5-concierge-والتجار)
6. [المعمارية التقنية](#6-المعمارية-التقنية)
7. [Supabase — جداول · RLS · SQL](#7-supabase--جداول--rls--sql)
8. [ربط ERP بالمنتجات](#8-ربط-erp-بالمنتجات)
9. [مشروع Flutter](#9-مشروع-flutter)
10. [الشاشات والمسارات](#10-الشاشات-والمسارات)
11. [UI/UX — Wildberries + ألوان نابو](#11-uiux--wildberries--ألوان-نابو)
12. [حالة التنفيذ](#12-حالة-التنفيذ)
13. [إعداد Supabase](#13-إعداد-supabase)
14. [تشغيل التطبيق](#14-تشغيل-التطبيق)
15. [بعد Pilot — V2](#15-بعد-pilot--v2)
16. [خصوصية العنوان](#16-خصوصية-العنوان)
17. [KPIs ومعايير النجاح](#17-kpis-ومعايير-النجاح)
18. [خارطة الطريق](#18-خارطة-الطريق)
19. [قائمة تحقق نهائية](#19-قائمة-تحقق-نهائية)

---

# 1. الملخص التنفيذي

**Naboo Market** هو **التطبيق الثاني** — تطبيق **المستهلك** (ليس التاجر):

```
┌─────────────────────────────────────────────────────────────────┐
│  Naboo ERP          →  التاجر: مخزون · فواتير · صندوق · ديون    │
│  Naboo Market       →  الزبون: تصفّح · طلب · COD · PVZ          │
│  Supabase           →  مشروع واحد — جداول marketplace_*         │
│  الربح              →  عمولة 0.5%–3% على البيع (ليس اشتراك)     │
│  Pilot              →  حي العشار · COD فقط · Concierge          │
└─────────────────────────────────────────────────────────────────┘
```

**الهدف:** تجربة سوق محلي مثل **Ozon / Wildberries** — مكيّفة للعراق:

- **COD** عند الاستلام (95%+ في البداية)
- **PVZ** — استلام من نقطة قريبة (كل محل = PVZ محتمل)
- **عربي RTL** · Tajawal
- **Pilot:** حضانة — تجار offline-first، المنصة ترفع المنتجات

**نجاح شهر 1 = 3 طلبات مُسلّمة** — ليس 30 طلب/يوم.

---

# 2. التطبيقان — الفرق والربط

## 2.1 من يستخدم ماذا؟

| | Naboo ERP | Naboo Market |
|---|-----------|--------------|
| **المستخدم** | صاحب محل + موظف | زبون في الحي |
| **المشروع** | `basra_store_manager` | `naboo_market` |
| **قاعدة بيانات محلية** | SQLite (offline-first) | **لا** SQLite ERP |
| **Supabase** | مزامنة + ترخيص | catalog + طلبات مباشرة |
| **الدفع** | صندوق المحل | COD (Pilot) |
| **الربح لنابو** | — | عمولة على البيع |

## 2.2 كيف يتعرف Market على منتجات ERP؟

```
Naboo ERP (SQLite)
    │  CloudSync / Concierge / admin-web
    ▼
Supabase — جداول marketplace_*
    │  RLS: قراءة عامة للمنتجات المنشورة
    ▼
Naboo Market (Flutter) — Supabase client مباشر
```

**القاعدة الذهبية:**

- ERP = **مصدر الحقيقة** للمخزون والأسعار
- Market = **Catalog Projection** — نسخة عامة مقروءة فقط
- **لا** وصول Market لـ SQLite المحلي أو جداول ERP الحساسة
- الربط عبر `product_global_id` (معرّف عالمي من ERP) + `store_id`

## 2.3 ما لا يفعله Market في Pilot

- محفظة مستهلك
- دفع إلكتروني (Zain · FIB · بطاقة)
- AI / توصيات شخصية
- Web / SEO
- Hub & Spoke بين أحياء
- عرض عنوان البائع
- توصيل منزلي

---

# 3. نموذج العمل والعمولة

## 3.1 المجانية الكاملة

| ❌ ليس مصدر دخل | ✅ مصدر الدخل الوحيد |
|----------------|---------------------|
| بيع التطبيق | عمولة على البيع |
| اشتراك شهري ERP | |
| رسوم تحميل/تسجيل | |

## 3.2 العمولة (بعد Pilot)

| الفئة | العمولة |
|-------|---------|
| بقالة / مواد غذائية | **0.5%** |
| ملابس / منزل | **1.5%** |
| إلكترونيات | **2.5%** |
| فاخر / عالي القيمة | **3%** |

**Pilot:** **0% عمولة أول 30 يوم** لكل تاجر — ثم 0.5%–1% مع خصم من COD (لا محفظة إلزامية).

## 3.3 مقارنة Ozon / Wildberries

| ميزة | Ozon/WB | Naboo Market Pilot |
|------|---------|-------------------|
| سوق متعدد البائعين | ✅ | ✅ |
| PVZ | ✅ | ✅ **جوهر النموذج** |
| COD | أقل | ✅ **افتراضي** |
| توصيل منزلي | ✅ | ⏳ V2+ |
| بنفسجي WB | ✅ | ❌ **كحلي + ذهب** |
| تجار offline | ❌ | ✅ **Concierge** |
| محفظة + استرداد | ✅ | ⏳ V2 |

---

# 4. Pilot 90 يوم

## 4.1 الفهم الصحيح

```
❌ «منصة للتجار الذين يبيعون أونلاين»
✅ «حضانة — نُخرج تاجر المحل التقليدي للإنترنت لأول مرة»
```

**التجار المستهدفون:** يبيعون **في المحل فقط** — لا واتساب commerce · لا أونلاين.

## 4.2 شروط Go (بدونها No-Go)

- [ ] **0% عمولة 30 يوم**
- [ ] **مندوب منصة** 30 يوم — التاجر لا يوصّل
- [ ] **رفع منتجات نيابة** — Concierge
- [ ] **حي واحد:** العشار · **5 أيام** مهلة استلام
- [ ] **نجاح شهر 1 = 3 طلبات مُسلّمة**

## 4.3 لغة المبيعات للتاجر

| ❌ لا تقل | ✅ قل |
|----------|------|
| ERP مجاني | **نصوّر منتجاتك ونرفعها — لا تتعلّم شيئاً** |
| عمولة منخفضة | **صفر عمولة 30 يوم** |
| PVZ وشبكة | **جهّز المنتج — نحن الباقي** |

## 4.4 أهداف 90 يوم

| المرحلة | أيام | تجار | PVZ | طلب/يوم | معيار النجاح |
|---------|------|------|-----|---------|--------------|
| 1 | 1–30 | 10→20 | 4 | 3→10 | **≥3 مُسلّمة** |
| 2 | 31–60 | 20→30 | 6 | 10→25 | 15+ تاجر طلب/شهر |
| 3 | 61–90 | 30→40 | 8–10 | 25→50 | 40 تاجر |

**خط أحمر رفض COD:** >50% شهر 1 · >40% يوم 90.

## 4.5 أسبوع 1 — لا ERP كامل

| اليوم | نشاط |
|-------|------|
| 1–2 | زيارة محل · صور 15–30 منتج |
| 3–4 | فريق المنصة يرفع · تفعيل Market |
| 5–7 | «عند أول طلب — اتصل بنا» |

**تدريب ERP الكامل:** 5–7 أيام — **بعد أول طلب**.

---

# 5. Concierge والتجار

## 5.1 دور Concierge

```
زيارة → صور → رفع admin → أول طلب → مندوب يوصّل → COD للتاجر
```

## 5.2 سكربت 60 ثانية

> «السلام عليكم — أنا من **نابو**. نساعد محلات الحي تبيع أونلاين **بدون ما تتعلم تطبيق**.  
> نصوّر 20 منتج، نرفعهم، إذا جاء طلب **أنت بس تجهّزه** — **إحنا نوصّل**.  
> **صفر عمولة أول شهر.** **اسم محلك يظهر — عنوان بيتك لا.**»

## 5.3 checklist زيارة محل

1. تأكيد: **لا يبيع أونلاين حالياً**
2. موافقة/توقيع (اتفاقية Pilot)
3. اسم تجاري للعرض
4. **عنوان داخلي** للمندوب فقط
5. صور **15–30 منتج** + أسعار
6. جوال التاجر

## 5.4 عند أول طلب

```
مندوب: استلام من التاجر (internal_address)
     → توصيل PVZ أو مباشرة للزبون
     → تحصيل COD
     → تسليم نقد التاجر + شرح 0% عمولة
```

## 5.5 اتفاقية التاجر (ملخص)

- نابو: تصوير · رفع · مندوب 30 يوم · 0% عمولة 30 يوم
- التاجر: تجهيز دقيق · تحديث نفاد · +5% سعر كحد أقصى · **لا عنوان في Market**
- بعد 30 يوم: 0.5%–1% من COD
- Pilot: **COD فقط**

**الملف الكامل:** `naboo_merchant_agreement_pilot_v1.md`

---

# 6. المعمارية التقنية

```
┌──────────────────────────────────────────────────────────────┐
│                     Clients                                   │
├─────────────────────────┬────────────────────────────────────┤
│ Naboo ERP (Flutter)     │ Naboo Market (Flutter)             │
│ SQLite + Provider       │ Provider + go_router               │
│ CloudSyncService        │ supabase_flutter مباشر             │
└────────────┬────────────┴──────────────┬─────────────────────┘
             │                           │
             ▼                           ▼
┌──────────────────────────────────────────────────────────────┐
│              Supabase (مشروع naboo-lic واحد)                │
│  Auth · Storage · Realtime · FCM · Edge Functions (لاحقاً)   │
│  marketplace_neighborhoods · marketplace_stores              │
│  marketplace_products · marketplace_orders · …               │
└──────────────────────────────────────────────────────────────┘
             ▲
             │ admin-web (Concierge)
             │ رفع متاجر/منتجات · internal_address
```

## 6.1 قرارات تقنية ثابتة

| القرار | القيمة |
|--------|--------|
| Market framework | **Flutter** (مشروع مستقل) |
| State | **Provider** (مثل ERP — لا Riverpod) |
| Routing | **go_router** |
| Locale | **`ar_SA`** RTL |
| Font | **Tajawal** (google_fonts) |
| Money | **`int fils`** — لا double |
| Pagination | cursor `afterId` — لا OFFSET |
| Pilot platforms | Android + iOS |

## 6.2 Edge Functions (مخطط — لم تُنفّذ كلها)

| Endpoint | الغرض |
|----------|--------|
| `GET /catalog/home` | أقسام الرئيسية |
| `GET /catalog/products` | قائمة + pagination |
| `POST /orders` | إنشاء طلب — إعادة حساب أسعار server-side |
| `GET /pickup-points` | نقاط PVZ |
| `POST /admin/products` | Concierge رفع |

**Pilot الحالي:** Market يقرأ مباشرة من Supabase tables (بدون Edge Functions بعد).

---

# 7. Supabase — جداول · RLS · SQL

## 7.1 ملفات SQL (في ERP repo)

| الملف | الترتيب | الغرض |
|-------|---------|--------|
| `migrations/20260507_rls_tenant.sql` | **قبل** pilot | `app_current_tenant_id()` |
| `migrations/20260620_market_pilot.sql` | **1** | schema + RLS |
| `migrations/20260620_market_mock_seed.sql` | **2** | بيانات تجريبية العشار |

**نسخة في Market repo:** `naboo_market/supabase/migrations/`

## 7.2 الجداول الرئيسية

| جدول | الغرض |
|------|--------|
| `marketplace_neighborhoods` | أحياء — Pilot: `ashar` = العشار |
| `marketplace_stores` | متاجر + PVZ · `internal_address` سري |
| `marketplace_products` | منتجات · `price_fils` int |
| `marketplace_customers` | مشترون · OTP |
| `marketplace_orders` | طلبات · COD |
| `marketplace_order_items` | بنود الطلب |
| `marketplace_stores_public` | **VIEW** — بدون `internal_address` |

## 7.3 حالات الطلب

```
pending → accepted → ready_to_ship → in_transit
    → at_pickup_point → delivered
    → cancelled
```

## 7.4 RLS (Pilot)

| جدول | anon/authenticated | ملاحظة |
|------|-------------------|--------|
| `marketplace_products` | SELECT إذا `is_published` | ✅ |
| `marketplace_stores` | SELECT إذا `is_published` | ✅ |
| `marketplace_neighborhoods` | SELECT إذا `is_active` | ✅ |
| `marketplace_orders` | buyer يرى طلباته · merchant عبر `tenant_uuid` | يحتاج auth |
| `internal_address` | **لا قراءة عامة** | ops فقط |

## 7.5 Mock seed — UUIDs ثابتة

| الكيان | UUID | الاسم |
|--------|------|-------|
| Store 1 | `00000000-0000-0000-0000-000000000001` | سوبر ماركت النور |
| Store 2 (PVZ) | `00000000-0000-0000-0000-000000000002` | بقالة السلام |
| Products | `10000000-0000-0000-0000-00000000000N` | 10 منتجات MOCK-PROD-001…010 |

## 7.6 أخطاء SQL شائعة (حُلّت)

| الخطأ | السبب | الحل |
|-------|-------|------|
| `relation "marketplace_stores" does not exist` | seed قبل pilot | شغّل **pilot أولاً** |
| `column "tenant_id" does not exist` | سياسة RLS قديمة | استخدم `app_current_tenant_id()` — الملف محدّث |

---

# 8. ربط ERP بالمنتجات

## 8.1 تدفق Pilot (Concierge — بدون ERP كامل)

```
1. Concierge يزور محل
2. admin-web ينشئ marketplace_store + products
3. is_published = true
4. Market يعرض فوراً
5. بعد أول طلب → تدريب ERP «طلبات أونلاين»
```

## 8.2 تدفق مستقبلي (ERP → Market)

```
ERP product (SQLite)
  global_id = UUID/text ثابت
  ↓ sync
marketplace_products.product_global_id
  store_id ← marketplace_stores.tenant_uuid ← ERP tenant
```

## 8.3 ERP — شاشة جديدة (مخطط)

**المسار:** `lib/screens/online_orders/online_orders_screen.dart`

| التبويب | status |
|---------|--------|
| جديدة | pending |
| قيد التجهيز | accepted |
| جاهزة | ready_to_ship |

**إجراءات:** قبول · رفض · جاهز → FCM للمشتري

---

# 9. مشروع Flutter

## 9.1 الموقع والهيكل

```
naboo_market/
├── lib/
│   ├── main.dart                    # GoRouter + Providers
│   ├── core/
│   │   ├── constants/env.dart       # Supabase URL/key
│   │   ├── theme/
│   │   │   ├── design_tokens.dart   # Navy + Gold
│   │   │   └── app_theme.dart       # Dark theme
│   │   └── widgets/
│   │       ├── market_search_bar.dart
│   │       ├── market_product_card.dart
│   │       ├── market_category_tile.dart
│   │       └── market_bottom_nav.dart
│   └── features/
│       ├── auth/                    # onboarding · account · location
│       ├── home/                    # home · main_scaffold · feed
│       ├── catalog/                 # category · product details
│       ├── cart/
│       └── orders/
├── supabase/migrations/             # نسخ SQL
└── pubspec.yaml                     # provider · supabase · go_router · intl
```

## 9.2 Dependencies (لا تُضف بدون طلب)

`provider` · `supabase_flutter` · `go_router` · `google_fonts` · `intl`

**ممنوع بدون طلب صريح:** Riverpod · dio · go_router replacement · connectivity_plus

## 9.3 Providers

| Provider | الملف | الدور |
|----------|-------|-------|
| `LocationProvider` | auth/providers | حي + PVZ |
| `AuthProvider` | auth/providers | OTP (جزئي) |
| `HomeFeedProvider` | home/providers | منتجات + متاجر |
| `CatalogProvider` | catalog/providers | pagination |
| `CartProvider` | cart/providers | سلة |
| `OrdersProvider` | orders/providers | طلبات |

---

# 10. الشاشات والمسارات

## 10.1 الشاشات السبع (MVP)

| # | الشاشة | Route | الحالة |
|---|--------|-------|--------|
| 1 | اختيار حي + PVZ | `/onboarding` | ✅ |
| 2 | الرئيسية | `/` | ✅ WB-style |
| 3 | تصنيف / قائمة | `/categories` · `/categories/:id` | ✅ |
| 4 | صفحة منتج | `/p/:id` | ⚠️ أساسي |
| 5 | السلة + Checkout | `/cart` | ⚠️ أساسي |
| 6 | طلباتي | `/orders` | ⚠️ أساسي |
| 7 | حسابي | `/account` | ⚠️ أساسي |

**كل شاشة:** `loading` + `empty` + `error` + retry — إلزامي.

## 10.2 Bottom Navigation (5 تبويبات)

```
الرئيسية · التصنيفات · السلة · طلباتي · حسابي
```

- نشط: **ذهبي** `#B8960C`
- خلفية: **كحلي** `#071A36`
- badge السلة: أحمر

## 10.3 تدفق المستخدم

```
فتح → onboarding (حي + PVZ) → الرئيسية
  → بحث/تصنيف → منتج → سلة
  → checkout COD + PVZ → طلباتي → استلام + دفع
```

**زائر:** تصفّح + سلة — **تسجيل OTP عند Confirm Order** (مخطط).

---

# 11. UI/UX — Wildberries + ألوان نابo

## 11.1 المبدأ

> **هيكل Wildberries · ألوان Naboo — ليس البنفسجي WB**

| عنصر WB | Naboo |
|---------|-------|
| بنفسجي `#CB11AB` | **كحلي `#071A36`** |
| CTA بنفسجي | **ذهبي `#B8960C`** |
| خلفية داكنة WB | **`#0F172A`** surface |
| شارة خصم | **أحمر `#DC2626`** (نفس فكرة WB) |
| روابط/تركيز | **أزرق `#007AFF`** |

## 11.2 design_tokens (Market)

```dart
MarketColors.navy       = #071A36   // header · nav
MarketColors.navyDark   = #050A14   // status
MarketColors.gold       = #B8960C   // CTA · أسعار · active tab
MarketColors.surface    = #0F172A   // خلفية
MarketColors.card       = #1E293B   // بطاقات
MarketColors.discount   = #DC2626   // -15%
```

## 11.3 الرئيسية (مثل WB — مُنفّذ)

```
┌─────────────────────────────────────────┐
│ 📍 نقطة الاستلام ▼                      │
│ 🔍 ابحث في نابو          🎤 📷          │
├─────────────────────────────────────────┤
│ [بانر عروض — تدرج كحلي→ذهبي]           │
├─────────────────────────────────────────┤
│ شبكة تصنيفات 3×2 (بلاطات)              │
├─────────────────────────────────────────┤
│ الأكثر مبيعاً              عرض الكل ←  │
│ [بطاقة][بطاقة]                          │
├─────────────────────────────────────────┤
│ اكتشف المزيد                            │
│ [بطاقة][بطاقة]  infinite grid           │
├─────────────────────────────────────────┤
│ 🏠  📂  🛒  📦  👤                       │
└─────────────────────────────────────────┘
```

## 11.4 بطاقة منتج (WB-style)

- 70% صورة · قلب · شارة `-X%` · زر سلة دائري ذهبي
- سعر **ذهبي** bold · سعر قديم مشطوب
- **لا عنوان متجر** — اسم فقط في PDP

## 11.5 الزوايا

| المكوّن | Radius |
|---------|--------|
| بحث | 24px pill |
| بطاقة منتج | 12px |
| بلاطة تصنيف | 16px |

## 11.6 Theme Mode

**Dark theme افتراضي** — مثل لقطات WB التي أرسلتها — بألوان Naboo.

---

# 12. حالة التنفيذ

## 12.1 ✅ تم

| البند | التفاصيل |
|-------|----------|
| مشروع Flutter | `naboo_market` منفصل |
| Supabase config | `env.dart` — نفس مشروع ERP |
| SQL migrations | pilot + mock seed (مصحّح) |
| Theme WB + Naboo | dark · navy · gold |
| Home screen | PVZ · search · banner · categories · grids |
| Product card | WB-style shared widget |
| Bottom nav | custom · gold active · cart badge |
| Onboarding | العشار + 2 PVZ |
| Category screen | grid + shared cards |
| Mock data | 2 stores · 10 products |

## 12.2 ⚠️ جزئي / يحتاج عمل

| البند | ما ينقص |
|-------|---------|
| Product details | PDP غني · variants · sticky CTA |
| Cart / Checkout | 3 خطوات · POST order |
| Orders | timeline · إلغاء · QR |
| Auth OTP | Supabase phone auth |
| ERP online orders | شاشة قبول/تجهيز |
| admin-web Concierge | `/market/stores` · `/market/products` |
| Edge Functions | POST /orders server-side |
| FCM | إشعار تاجر + مشتري |
| Product images | Storage upload · عرض حقيقي |

## 12.3 ❌ لم يُبنَ (Pilot لا يحتاج)

- AI personalization
- Consumer wallet
- Zain Cash / FIB / بطاقة
- Flutter Web
- Multi-neighborhood
- Merchant wallet إلزامية
- Hub logistics

---

# 13. إعداد Supabase

## 13.1 الترتيب (SQL Editor — مشروع naboo-lic)

```
1. migrations/20260507_rls_tenant.sql     (إن لم يكن مُشغّلاً)
2. migrations/20260620_market_pilot.sql   ← Run
3. migrations/20260620_market_mock_seed.sql ← Run
```

## 13.2 التحقق (Table Editor)

- [ ] `marketplace_neighborhoods` → `ashar`
- [ ] `marketplace_stores` → 2 rows
- [ ] `marketplace_products` → 10 rows
- [ ] `marketplace_stores_public` view يعمل

## 13.3 إذا فشل SQL

| خطأ | الحل |
|-----|------|
| `marketplace_stores does not exist` | pilot قبل seed |
| `tenant_id does not exist` | حدّث pilot.sql — استخدم النسخة المصحّحة |
| `app_current_tenant_id does not exist` | شغّل 20260507_rls_tenant.sql |

---

# 14. تشغيل التطبيق

```bash
cd /Users/mohamed123/Development/naboo_market

# القيم الافتراضية في env.dart — أو:
flutter run \
  --dart-define=SUPABASE_URL=https://rkofqwcuvbzrnmelvxhz.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

**أول تشغيل:**

1. onboarding → اختر **العشار**
2. PVZ → **سوبر ماركت النور** أو **بقالة السلام**
3. الرئيسية → يجب أن تظهر 10 منتجات

---

# 15. بعد Pilot — V2

## 15.1 AI Personalization (V1→V3)

| المرحلة | ما يحدث |
|---------|---------|
| Pilot | trending محلي + حي |
| V1 | تتبّع سلوك · `product_dwell` · scroll stop |
| V2 | embeddings عربية · بحث ذكي |
| V3 | LLM مساعد · إعلانات مستهدفة |

**إشارات رئيسية:** `product_view` · `product_card_impression_dwell` · `home_section_dwell`

**الملف:** `naboo_market_ai_personalization_v1.md`

## 15.2 محفظة المستهلك (V2)

```
إلغاء قبل الشحن → رصيد فوري «محفظتي»
رفض عند PVZ → رصيد − رسوم توصيل
سحب للبطاقة → 3–7 أيام
```

**Pilot = COD فقط — لا محفظة.**

**الملف:** `naboo_market_consumer_wallet_refunds_v1.md`

## 15.3 الدفع الإلكتروني (V2)

| المرحلة | طرق |
|---------|-----|
| Pilot | COD ✅ |
| V2a | Zain Cash · FIB · رصيد نابو |
| V2b | Visa/Mastercard token |

**شرط البدء:** ≥3 طلبات COD مُسلّمة · ≥10 تجار · رفض ≤40%

**الملف:** `naboo_market_payments_v1.md`

## 15.4 محفظتا — لا تخلط

| | محفظة التاجر (ERP) | محفظة المستهلك (Market) |
|---|---------------------|---------------------------|
| الغرض | خصم **عمولة** | **استرداد** + شراء |
| Pilot | COD خصم | **غير موجودة** |

---

# 16. خصوصية العنوان

## 16.1 قاعدة صارمة

| يظهر للمستهلك | لا يظهر أبداً |
|---------------|---------------|
| **اسم المتجر** | `internal_address` |
| الحي (اختياري) | شارع/منزل البائع |
| `pickup_address` لـ PVZ فقط | خريطة موقع البائع |

## 16.2 تاجر من المنزل

- نفس الواجهة — **اسم تجاري فقط**
- `location_type = home`
- `internal_address` → للمندوب في admin/ops فقط
- API عام → `marketplace_stores_public` **بدون** internal

---

# 17. KPIs ومعايير النجاح

## 17.1 Pilot شهر 1

| KPI | هدف | خط أحمر |
|-----|------|---------|
| طلبات مُسلّمة | **≥3** | 0 |
| منتجات/تاجر | ≥15 | <5 |
| رفض COD | ≤40% | >50% |
| بقاء تاجر 30 يوم | ≥70% | <50% |

## 17.2 معايير قبول MVP تقني

- [ ] 15 منتج من 3 متاجر في Market
- [ ] طلب COD end-to-end
- [ ] عنوان بائع **غير** ظاهر في API عام
- [ ] إلغاء `pending` يعمل
- [ ] RTL · loading/empty/error · 7 شاشات
- [ ] كل المبالغ `int fils`

## 17.3 MiroFish — قرارات مُستخلصة

- **Go with conditions** — Pilot 90 يوم قبل «إطلاق البصرة»
- أكبر خطر: **«هل يشتري أحد أونلاين؟»** + رفض COD
- لا محفظة إلزامية عند صفر — **حد ائتماني** لاحقاً
- Concierge + مندوب = **ضروري** — ليس «تطبيق فقط»

---

# 18. خارطة الطريق

## 18.1 4 أسابيع MVP (تقني)

| أسبوع | مهام |
|-------|------|
| 1 | ✅ SQL · Storage · admin stores/products |
| 2 | ✅ Market onboarding · home · product · cart |
| 3 | POST order · ERP online orders · FCM |
| 4 | طلباتي · PVZ · اختبار 3 تجار |

## 18.2 بعد Pilot ناجح

```
شهر 4–6:   Zain + FIB + محفظة
شهر 6–8:   بطاقة · AI rules
شهر 9–12:  حي ثاني · تقليل Concierge · Web
```

---

# 19. قائمة تحقق نهائية

## قبل Demo للمستثمر / تاجر

- [ ] SQL pilot + seed ناجح في Supabase
- [ ] Market يعرض منتجات العشار
- [ ] UI كحلي + ذهبي (WB layout)
- [ ] onboarding PVZ يعمل
- [ ] سلة + (طلب test إن أمكن)

## قبل Pilot حقيقي (10 تجار)

- [ ] Concierge + مندوب + دعم
- [ ] اتفاقيات موقّعة
- [ ] admin-web رفع منتجات
- [ ] ERP طلبات أونلاين (قبول/تجهيز)
- [ ] FCM أو واتساب للطلبات
- [ ] Excel تتبّع KPIs

## قبل V2 (دفع إلكتروني)

- [ ] ≥3 طلبات COD مُسلّمة
- [ ] ≥10 تجار · رفض ≤40%
- [ ] محفظة مستهلك — تصميم جاهز
- [ ] Zain UAT + webhook

---

## ملحق أ — خريطة الملفات في المستودعين

### basra_store_manager

```
docs/specs/
  naboo_market_complete_reference_v1.md   ← هذا الملف (المرجع)
  naboo_market_master_plan_v1.md
  naboo_market_mvp_spec_v1.md
  naboo_market_ui_wildberries_inspired_v1.md
  naboo_market_ai_personalization_v1.md
  naboo_market_consumer_wallet_refunds_v1.md
  naboo_market_payments_v1.md
  naboo_pilot_90_days_v1.md
  naboo_concierge_ops_playbook_v1.md
  naboo_merchant_agreement_pilot_v1.md
  naboo_ecosystem_master_plan_v1.md       ← المنظومة الكاملة (ERP+Market)

migrations/
  20260620_market_pilot.sql
  20260620_market_mock_seed.sql
```

### naboo_market

```
lib/                          ← كود Flutter (انظر §9)
supabase/migrations/          ← نسخ SQL
docs/NABOO_MARKET_COMPLETE_REFERENCE.md  ← نسخة هذا الملف
```

---

## ملحق ب — قرارات مُقفلة (لا تعيد النقاش)

| # | القرار |
|---|--------|
| 1 | Market = مشروع Flutter **منفصل** |
| 2 | Supabase = **مشروع واحد** مع ERP |
| 3 | Pilot = **COD فقط** · العشار · Concierge |
| 4 | UI = **WB layout** · **Naboo colors** (ليس بنفسجي) |
| 5 | عنوان البائع = **ممنوع** في Market |
| 6 | الربح = **عمولة** — لا اشتراك ERP القديم |
| 7 | Money = **int fils** |
| 8 | Locale = **ar_SA** RTL |

---

*الإصدار: 1.0 | 2026-06-20 | المرجع الشامل الوحيد لتطبيق Naboo Market*
