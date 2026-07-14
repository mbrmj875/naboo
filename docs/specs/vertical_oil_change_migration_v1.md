# فصل تخصصات العمل — Spec v1.0 (Pilot: `oil_change`)

> **الحالة:** المراحل 0–5 ✅ · المعايير 11–12 ✅ · المتبقي: المرحلة 6 (قبول ذهبي يدوي)  
> **التاريخ:** 2026-06-11 · **آخر تحديث:** 2026-06-12  
> **المراجع:** `feature_gate_v1.md` · `owner_command_center_v3_vertical_profiles.md` · `home_screen_dynamic_v1.md`  
> **النطاق:** تحويل `oil_change` إلى Vertical Module كامل — monorepo واحد، بدون packages منفصلة

---

## 1. الملخص التنفيذي

المشروع يملك **Feature Gate** يعمل (إخفاء تنقل، حارس مسارات، افتراضيات onboarding). لكن **الفصل ليس معمارياً**: كود الزيت (~50 ملف، ~12,000 سطر) موزّع، مع **God Screen** (`service_order_form_screen.dart` — 6,448 سطر) يجمع غيار الزيت وتذاكر الصيانة.

**الهدف:** كل تخصص = **Vertical Module** مسجّل في نواة مشتركة. إضافة/تعديل vertical لا يمسّ الآخرين. الشاشات المشتركة (مخزون، عملاء، صندوق) في `core` بدون `if (oil_change)`.

**Pilot:** `oil_change` — الأكثر نضجاً (Resolvers، Repos، Owner/Home Dashboard، اختبارات).

---

## 2. الوضع الحالي — تدقيق `oil_change`

### 2.1 مُفصَل ✅

| الطبقة | الملفات المرجعية |
|--------|------------------|
| تعريف النشاط | `BusinessVertical.oilChange` |
| Feature Gate | `BusinessFeaturesProvider` + `FeatureRouteGuard` |
| Home Dashboard | `OilChangeVerticalManifest.resolveHome` ← `HomeDashboardResolver` (تفويض) |
| Owner Dashboard | `OilChangeVerticalManifest.resolveOwner` ← `OwnerDashboardProfileResolver` (تفويض) |
| KPI Catalog | بطاقات `oil_*` في `owner_kpi_catalog.dart` |
| DB مخصص | `oil_change_oil_catalog`, `oil_change_filter_catalog`, `oil_change_hydraulic_catalog`, `oil_change_services` |

### 2.2 غير مُفصَل ❌

| # | المشكلة | الخطورة |
|---|---------|---------|
| P0 | ~~`service_order_form_screen.dart` (6,448 سطر) — `oilChangeMode`~~ → repair-only (~1,420 سطر)، الزيت في `OilChangeOrderFormScreen` | ✅ (مرحلة 1) |
| P1 | ~~`home_screen.dart` — imports ومنطق زيت مباشر~~ → nav من manifest، TODO واحد (`initialSearchQuery`) | ✅ (مرحلة 3) |
| P1 | ~~لا مجلد `lib/verticals/oil_change/`~~ | ✅ (مرحلة 2) |
| P2 | ~~`service_orders` مشترك (oil + repair)~~ → `OilChangeOrdersRepository` facade | ✅ (مرحلة 4) |
| P3 | ~~`reports_screen.dart` — `section == 8` hardcoded~~ → من manifest | ✅ (مرحلة 3) |
| P3 | ~~لا شاشة «الفواتير» عند `enablePos = false`~~ → `OilChangeInvoicesScreen` | ✅ (مرحلة 3.5) |

### 2.3 جرد الملفات (الحالة النهائية)

```
lib/verticals/oil_change/  →  50 ملف .dart (بدون export stubs)
God Screen (repair-only)   →  1,412 سطر (service_order_form_screen.dart)
OilChangeOrderFormScreen   →  ~6,128 سطر
```

---

## 3. الهدف المعماري — Core + Vertical Plugins

```
lib/
├── core/                    ← auth · tenant · customers · cash · inventory · navigation
├── verticals/
│   ├── _contract/           ← VerticalManifest + VerticalRegistry  ✅ المرحلة 0
│   ├── oil_change/          ← Pilot
│   ├── supermarket/
│   ├── clothing_store/
│   └── general_retail/      ← fallback
└── app/                     ← main · onboarding · shell
```

### 3.1 عقد `VerticalManifest`

كل vertical يُسجّل manifest واحد:

| القدرة | الوصف |
|--------|-------|
| `id` | `'oil_change'` |
| `navModules` | عناصر القائمة الجانبية |
| `routes` | مسارات + builders |
| `resolveHome` | لوحة الموظف |
| `resolveOwner` | لوحة المالk |
| `barcodePolicy` | Scan-to-Card |
| `reportSections` | تبويبات التقارير |
| `inventoryPolicy` | حقول المنتج |
| `kpiCatalogEntries` | بطاقات owner |
| `defaultFeatures` | افتراضيات onboarding |

**قاعدة:** أي ملف خارج `verticals/<id>/` **لا ي import** كود ذلك التخصص.

### 3.2 Core (لا يُفصل)

Auth · Tenant · RBAC · العملاء · الديون · الصندوق · الورديات · المخزون الأساسي · الطباعة · Feature Gate Shell.

---

## 4. مراحل التنفيذ

```
[0: العقد ✅] → [1: استخراج God Screen ✅] → [2: نقل الملفات ✅]
      → [3: Manifest + تنظيف Core ✅] → [3.5: Invoices Viewer ✅]
      → [4: DB encapsulation ✅] → [5: Owner/Home ✅]
      → [11: إزالة stubs ✅] → [12: loadOil* → manifest ✅]
      → [6: قبول ذهبي ⏳ QA يدوي]
```

### المرحلة 0 — العقد ✅

- `lib/verticals/_contract/vertical_manifest.dart`
- `lib/verticals/_contract/vertical_registry.dart`
- **لا نقل ملفات**

### المرحلة 1 — استخراج God Screen (P0) ✅

```
OilChangeFormScreen → OilChangeOrderFormScreen (مستقل)
RepairTicketForm    → RepairOrderFormScreen (يبقى في service_order_form_screen — repair-only)
service_order_form_screen.dart → ~1,420 سطر (تذاكر صيانة فقط، بدون oilChangeMode)
```

#### نتائج المرحلة 1 — مكتملة

| المقياس | قبل | بعد |
|---------|-----|-----|
| God Screen (`service_order_form_screen`) | 6,448 سطر | 1,420 سطر |
| `oilChangeMode` references | 98+ | 0 |
| `OilChangeOrderFormScreen` | لا يوجد | ~6,133 سطر |
| اختبارات الزيت | 13/13 | 13/13 |
| اختبارات كاملة | 804 | 805 |

**ما تم:**

- `OilChangeFormScreen` يوجّه إلى `OilChangeOrderFormScreen` مباشرة (لا `ServiceOrderFormScreen(oilChangeMode: …)`).
- نقل clusters: UI، submit، تحميل/مزامنة، visit sync من God Screen إلى شاشة الزيت.
- حذف dead oil UI + stubs من God Screen؛ إزالة `oilChangeMode` / `isOilNewCard` من constructor.
- `ServiceOrderFormScreen` = repair-only (`ServiceOrdersHub` + تعديل تذكرة صيانة).
- `dart analyze` → 0 errors على الملفات الملموسة؛ `test/oil_change_*` → 13/13.

**لم يُنفَّذ بعد (مراحل لاحقة):** نقل الملفات إلى `lib/verticals/oil_change/`، manifest كامل، Invoices Viewer، encapsulation DB، قبول ذهبي 15/15.


### المرحلة 2 — نقل إلى `lib/verticals/oil_change/`

| من | إلى |
|----|-----|
| `lib/models/oil_change_*` | `verticals/oil_change/models/` |
| `lib/services/oil_change_*` | `verticals/oil_change/services/` |
| `lib/screens/services/oil_change_*` | `verticals/oil_change/screens/` |
| `lib/widgets/oil_change/*` | `verticals/oil_change/widgets/` |
| `lib/utils/oil_change_*` | `verticals/oil_change/utils/` |
| `lib/home/widgets/oil_change_*` | `verticals/oil_change/home/` |
| `lib/owner/owner_oil_*` | `verticals/oil_change/owner/` |
| `lib/screens/reports/oil_change_*` | `verticals/oil_change/reports/` |

### المرحلة 3 — Manifest + تنظيف Core ✅

- `OilChangeVerticalManifest` مسجّل في `VerticalRegistry`
- `home_screen.dart`: **صفر** imports زيت — nav من manifest
- `content_navigation.dart`: route guard من manifest
- `reports_screen.dart`: sections من manifest

#### نتائج المرحلة 2 + 3 — مكتملة

| المقياس | النتيجة |
|---------|---------|
| ملفات منقولة إلى `lib/verticals/oil_change/` | 44 ملف |
| imports زيت في Core files | 0 |
| manifest guards موصولة | ✅ |
| TODO متبقية | 1 (`initialSearchQuery` في `home_screen`) |
| اختبارات | 805 ناجح |

**ما تم (المرحلة 2):**

- نقل 44 ملفاً إلى `lib/verticals/oil_change/` (models · services · screens · widgets · utils · home · owner · reports).
- ~~export stubs عند المسارات القديمة~~ → **حُذفت (المعيار 11 ✅)**
- `OilChangeVerticalManifest` مسجّل في `main.dart`.

**ما تم (المرحلة 3):**

- `home_screen.dart`: nav modules و routes من manifest — **صفر** imports زيت.
- `reports_screen.dart` · `add_product_screen.dart` · `add_invoice_screen.dart`: panels/editors من manifest (`reportSections` · `fluidInventoryEditor`).
- `content_navigation.dart`: manifest guards في `isContentRouteBlocked()` — `routeGuardExact` / `routeGuardPrefixes` + `reportSections` (طبقة إضافية فوق `featureRouteMapping`).
- `dart analyze` → 0 errors · `flutter test` → 805 passed (26 failed pre-existing، بدون regression).

**لم يُنفَّذ بعد:** قبول ذهبي 15/15 (المعيار 9 — QA يدوي على جهاز).

#### نتائج المراحل 3.5 + 4 + 5 — مكتملة

| المرحلة | النتيجة |
|---------|---------|
| **3.5 — Oil Invoices Viewer** | ✅ مكتملة — 5 ملفات جديدة، `viewOnly` mode، gate: `enableOilChange` |
| **4 — DB Encapsulation** | ✅ مكتملة — `OilChangeOrdersRepository` facade، 19 استدعاء منقول |
| **5 — Owner + Home Dashboard** | ✅ مكتملة — `resolveHome` + `resolveOwner` في manifest، صفر منطق زيت في Core resolvers |

### المرحلة 3.5 — Oil Invoices Viewer ✅ (مرجع التصميم)

**المشكلة:** `enablePos = false` يخفي «الفواتير»، لكن إقفال بطاقة الزيت يُنشئ فواتير في `invoices` + `service_orders.invoiceId`.

**الحل:** `OilChangeInvoicesScreen` — **عارض فقط**، بنفس UX `InvoicesScreen` بدون أي CTA بيع.

| عنصر | عرض |
|------|-----|
| إحصاءات · بحث · تبويبات (الكل/مدفوعة/غير مدفوعة/مرتجع) | ✅ |
| تبويب «تقسيط» | ❌ (مقفول لـ oil_change) |
| Master-Detail · تجميع ورديات | ✅ |
| زر «+ البيع» (FAB · empty · detail panel) | ❌ |
| sub-items (بيع جديد · معلقة · إعدادات POS) | ❌ |

**مسار:** `app_oil_invoices` · Gate: `enableOilChange` (ليس `enablePos`)

**بيانات:** فواتير مرتبطة بـ `service_orders.orderKind = 'oil_change'` عبر `OilChangeInvoicesRepository`.

**Hybrid (`enablePos`):** فلتر «من بطاقة زيت / من POS» في شاشة واحدة (الخيار A).

**DRY:** استخراج widgets من `invoices_screen.dart` → `core/widgets/invoices/` + `InvoiceListMode.viewOnly`.

**تنقل service-only:**
```
سجل غيارات الزيت → عمليات
الفواتير → قائمة الفواتير (viewer)
```

**تقدير:** 2–3 أيام ضمن الأسبوع 2–3.

### المرحلة 4 — DB Encapsulation ✅

- **الخيار A (v1):** الإبقاء على `service_orders` + `orderKind` — encapsulation في `OilChangeOrdersRepository`
- **الخيار B (v2):** جدول `oil_change_orders` منفصل (مؤجّل)

#### نتائج المرحلة 4 — مكتملة

| المقياس | النتيجة |
|---------|---------|
| DB Encapsulation | ✅ مكتملة — `OilChangeOrdersRepository` facade |
| استدعاءات منقولة | 19 في `OilChangeOrderFormScreen` |
| `ServiceOrdersRepository` | لم يُلمس (repair يبقى كما هو) |
| دوال زيت منقولة | `getLatestOilChangeBy*` · `getOilChangeLogPage` |
| facade wrappers | `createOilChangeOrder` · `updateOilChangeOrder` · `getOilChangeOrderById` · `replaceOilChangeItems` |
| اختبارات | 805 ناجح · `test/oil_change_*` → 13/13 |

### المرحلة 5 — Owner + Home Dashboard ✅

#### نتائج المرحلة 5 — مكتملة

| المقياس | النتيجة |
|---------|---------|
| Owner + Home Dashboard | ✅ مكتملة |
| `resolveHome` | منطق لوحة الموظف في `OilChangeVerticalManifest` — `HomeDashboardResolver` يفوّض |
| `resolveOwner` | `_oilChangeServiceSpec` · `_oilChangeHybridSpec` · `_oilServiceCardOrder` في manifest — `OwnerDashboardProfileResolver` يفوّض |
| منطق زيت في Core resolvers | **صفر** (تفويض فقط عبر `VerticalRegistry`) |
| اختبارات | 805 ناجح (بدون regression) |

#### نتائج المعيار 12 — نقل `loadOil*` إلى vertical ✅

| المقياس | النتيجة |
|---------|---------|
| `loadOwnerSection` + `loadOwnerSectionTrend` | في `VerticalManifest` + `OilChangeVerticalManifest` |
| التفويض | `OwnerOilDashboardRepository` (بيانات) · `OwnerTrendRepository` (WoW) |
| `OwnerCommandCenterProvider` | يستدعي عبر `VerticalRegistry` — **صفر** `_repository.loadOil*` |
| `loadHybridRevenueSplit` | لم يُمسّ (يبقى في `OwnerCommandCenterRepository`) |
| اختبارات | 805 ناجح · بدون regression |

#### نتائج المعيار 11 — إزالة export stubs ✅

| المقياس | النتيجة |
|---------|---------|
| stubs محذوفة | 43 ملف (`export 'package:naboo/verticals/oil_change/...'` فقط) |
| imports محدّثة | كل المستهلكين في `lib/` و `test/` → `verticals/oil_change/` |
| `dart analyze` | 0 errors |
| اختبارات | 805 ناجح · 26 فاشل pre-existing |

### المرحلة 6 — قبول ذهبي (QA يدوي على جهاز)

| # | سيناريو |
|---|---------|
| 1–10 | onboarding · gate · barcode · checkout · hybrid · owner · RTL |
| 11 | إقفال بطاقة → فاتورة في «الفواتير» |
| 12 | empty state بدون «+ بيع» |
| 13 | deep link `app_add_invoice` محظور |
| 14 | hybrid — فصل فواتير زيت/POS |
| 15 | RBAC — view بدون `sales.pos` |

---

## 5. Feature Gate — تعديل

| المسار | Gate |
|--------|------|
| `app_invoices` (POS) | `enablePos` |
| `app_oil_invoices` 🆕 | `enableOilChange` |
| `app_add_invoice` | `enablePos` |

---

## 6. مخاطر

| خطر | تخفيف |
|-----|--------|
| كسر checkout | `oil_change_customer_debt_test` + QA |
| Sync cloud | لا schema change v1 |
| Regression repair | فصل repair form قبل حذف God Screen |
| Scope creep | نقل معماري — لا UX redesign |

---

## 7. ما لا نفعله

- لا APK منفصل لكل vertical
- لا تغيير `biz.vertical` بعد onboarding
- لا جدول DB جديد v1
- لا pharmacy/restaurant (placeholder فقط)

---

## 8. معايير النجاح — «التحويل الكامل»

| # | المعيار | الحالة |
|---|---------|--------|
| 1 | God Screen مستبدَل بـ `OilChangeOrderFormScreen` (مسار الزيت) | ✅ |
| 2 | **صفر** `oilChangeMode` في `ServiceOrderFormScreen` | ✅ |
| 3 | `lib/verticals/oil_change/` — 100% كود الزيت (50 ملف `.dart` incl. manifest + phases 3.5–5) | ✅ |
| 4 | `OilChangeVerticalManifest` في `VerticalRegistry` | ✅ |
| 5 | **صفر** imports زيت في: `home_screen`, `content_navigation`, `reports_screen`, `add_invoice_screen`, `add_product_screen` | ✅ |
| 6 | `resolveHome` + `resolveOwner` للزيت في manifest (Core resolvers = تفويض فقط) | ✅ |
| 7 | `OilChangeOrdersRepository` facade فوق `service_orders` + `orderKind` | ✅ |
| 8 | `OilChangeInvoicesScreen` viewer بدون CTA بيع (`InvoiceListMode.viewOnly`) | ✅ |
| 9 | 15/15 سيناريو قبول ذهبي (المرحلة 6) | ⏳ **QA يدوي على جهاز** — لم يُنفَّذ بعد |
| 10 | CI: `flutter test` كامل أخضر | ⏳ **805 ناجح · 1 متخطى · 26 فاشل** — pre-existing موثّقة، **لا علاقة بالزيت** |
| 11 | إزالة export stubs والاستيراد من مسارات `lib/` القديمة | ✅ |
| 12 | نقل `loadOil*` من `OwnerCommandCenterProvider` إلى `OilChangeVerticalManifest.loadOwnerSection` | ✅ |

### المعيار 10 — الـ 26 فاشل pre-existing (ليست regression زيت)

| الفئة | أمثلة |
|-------|--------|
| Supabase / dart-define | `supabase_config_test.dart` (4) |
| DB tenant / cash | `db_cash_tenant_isolation_test.dart`, `soft_delete_test.dart` |
| Owner dashboard resolver | `owner_dashboard_profile_resolver_test.dart` (hero KPI قديم) |
| Security / license | `license_v2_only_test.dart`, `jwt_license_verify_test.dart` |
| Performance timing | `db_performance_test.dart` (flaky) |
| Phase regressions | `phase2_owner_governance_regression_test.dart`, `phase3_owner_dashboard_mvp_regression_test.dart` |

> تشغيل `flutter test` بعد المعايين 11–12: **805 ناجح** — نفس baseline قبل الهجرة.

---

## 9. التخصصات التالية

| # | Vertical | التعقيد |
|---|----------|---------|
| 2 | `supermarket` | weight + POS |
| 3 | `clothing_store` | variants |
| 4 | `general_retail` | fallback |
| 5 | `repair_services` | remnant God Screen |

---

## 10. المراجع البرمجية (المرحلة 0)

```dart
// lib/verticals/_contract/vertical_manifest.dart
abstract class VerticalManifest { ... }

// lib/verticals/_contract/vertical_registry.dart
VerticalRegistry.instance.register(manifest);
VerticalRegistry.instance.activeManifest;
```
