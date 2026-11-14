# فصل تخصص الصيدلية — Spec v1.0 (Naboo Pharmacy)

> **الحالة:** معتمد للتنفيذ — **لم يبدأ التنفيذ بعد**  
> **التاريخ:** 2026-06-12  
> **المراجع:** `vertical_oil_change_migration_v1.md` · `feature_gate_v1.md` · `inventory_policy_settings.dart`  
> **النطاق:** تحويل `pharmacy` إلى Vertical Module كامل — monorepo واحد، بدون packages منفصلة  
> **Framework:** Flutter + `provider` + `sqflite` + `VerticalManifest` (نفس مكدس Naboo — **لا إطار جديد**)

---

## 0. ملخص القرارات المعتمدة ✅ (Executive Summary)

| القرار | الاختيار | التوضيح والتحسينات المضافة ➕ |
|--------|----------|-------------------------------|
| **اللغة** | عربي + إنجليزي إلزامي + بحث بالاثنين | ➕ بحث ذكي باسم المرض/العرض والمادة الفعّالة |
| **Rx/OTC** | تمييز بدون إلزام وصفة | ➕ إلزام بيانات الطبيب فقط في «الأدوية المراقبة/الجدول» |
| **تقييم الشركات** | النوع + بلد المنشأ | ➕ فئة تصنيف جودة (A, B, C) لتسهيل البدائل |
| **الباركود** | واحد عام الآن + باركود الدفعة لاحقاً | ➕ يمهّد لتتبع Batch بدقة لسحب الأدوية (Recall) |
| **دواعي الاستعمال** | قائمة + نص حر + ATC | ➕ ربط بالفئة العمرية (أطفال/بالغين) لمنع الأخطاء |
| **التنبيهات** | كاملة (صلاحية · نقص · تفاعل · حمل · حساسية · أعراض · سحب · جرعة) | ➕ إيقاف تلقائي لبيع الدواء المنتهي أو المسحوب |
| **العملاء** | ملف كامل + أدوية مزمنة + تنبيهات | ➕ ولاء (نقاط) · حسابات آجلة · ملاحظات طبية عامة |
| **الموردين** | ملف كامل + مقارنة أسعار + مرتجعات | ➕ كشف حساب مالي · تقارير مرتجعات مالية |
| **التأمين** | اختياري | ➕ نسب التحمل · الرفض · المبالغ المغطاة |
| **التقارير** | شاملة | ➕ معدل دوران المخزون · الجرد الفعلي (Reconciliation) |

---

## 1. الملخص التنفيذي المعماري

### 1.1 الهدف

تحويل **صيدلية Naboo** من «محل تجزئة + صلاحية + دفعة» إلى **Vertical Module** مستقل تحت `lib/verticals/pharmacy/`، بنفس نمط `oil_change`:

- Core يوفّر: auth · tenant · customers · cash · invoices · products shell · navigation shell
- Pharmacy vertical يوفّر: drug catalog · clinical alerts · POS panel · substitutes · FEFO · reports · owner KPIs
- **صفر** `if (pharmacy)` في ملفات Core بعد اكتمال المرحلة 3

### 1.2 كيف تتعامل الأنظمة الكبيرة (مرجع Naboo)

الأنظمة الاحترافية تفصل **3 طبقات** — Naboo يتبعها:

```
┌─────────────────────────────────────────────────────────┐
│  Drug Reference Catalog (ثابت نسبياً — tenant + import) │
│  INN · ATC · indications · interactions · age band      │
└──────────────────────────┬──────────────────────────────┘
                           │ FK
┌──────────────────────────▼──────────────────────────────┐
│  Product SKU (مخزون — products + pharmacy_profile)      │
│  barcode · manufacturer · Rx/OTC · strength · form    │
└──────────────────────────┬──────────────────────────────┘
                           │ batch
┌──────────────────────────▼──────────────────────────────┐
│  Batch / Stock (دفعة · صلاحية · FEFO · location · cost) │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│  POS + Alerts + Substitutes + Customer clinical context   │
└─────────────────────────────────────────────────────────┘
```

**قواعد Naboo الصيدلانية:**

- «لمن هذا العلاج» = **ATC + دواعي + فئة عمرية** — لا تشخيص ولا ادّعاء طبي في UI
- «جودة» = **نوع شركة (أصلي/جنيس/محلي) + بلد + tier A/B/C + سعر** — لا «أفضل/أسوأ» طبياً
- **Substitute** = نفس INN + تركيز + شكل صيدلاني — ترتيب حسب tier ثم ربحية أو صلاحية (قابل للإعداد)

### 1.3 الوضع الحالي في الكود

| موجود ✅ | غير موجود ❌ |
|----------|--------------|
| `BusinessVertical.pharmacy` في onboarding | `lib/verticals/pharmacy/` |
| افتراضيات: POS · ولاء · ديون | `PharmacyVerticalManifest` |
| `BusinessProfile.pharmacy`: expiry · batch · grade | drug reference catalog |
| حقول `grade` · expiry في `add_product_screen` | POS drug panel · substitutes |
| | clinical alerts · insurance · chronic meds |

### 1.4 قاعدة ذهبية — إضافة منتج والبيع حسب التخصص فقط ⭐

> **متطلب معتمد:** حقول وميزات الصيدلية **لا تظهر أبداً** لمحل سوبرماركت/ملابس/زيت — **فقط** عندما `businessVertical == pharmacy`.

#### المبدأ (نفس نمط `oil_change` — بدون `if (pharmacy)` منتشر)

Core يبقى شاشة واحدة مشتركة؛ التخصص يحقن **امتداداً** عبر `VerticalRegistry`:

```
add_product_screen.dart          add_invoice_screen.dart (POS)
        │                                    │
        ▼                                    ▼
VerticalRegistry.activeManifest    VerticalRegistry.activeManifest
        │                                    │
        ▼                                    ▼
pharmacyProductEditor              buildPosDrugPanel + alertResolver
(null إن لم يكن pharmacy)          (null → بيع عادي)
```

| الشاشة | محل تجزئة / سوبرماركت | صيدلية فقط |
|--------|------------------------|------------|
| **إضافة منتج** | اسم · باركود · سعر · مخزون · (variants ملابس) | ➕ wizard دواء: INN · ATC · دواعي · شركة · Rx/OTC · monitored · tier A/B/C · شكل/تركيز · دفعة/صلاحية إلزامية |
| **البيع (POS)** | scan → سطر فاتورة | ➕ لوحة دواء · FEFO · بدائل · تنبيهات (تفاعل · حساسية · حمل · recall · جرعة) · Rx capture للجدول |
| **سياسة مخزون** | `BusinessProfile.retail` | `inventoryPolicy` من manifest → expiry+batch+grade **مفعّلة تلقائياً** |

#### آلية التنفيذ في العقد

```dart
// vertical_manifest.dart — إضافات مقترحة (مرحلة 2)
abstract class VerticalManifest {
  VerticalPharmacyProductEditor? get pharmacyProductEditor => null;
  Widget? buildPosDrugPanel(BuildContext context, PosDrugPanelArgs args) => null;
  Future<List<PharmacyAlert>> evaluateSaleAlerts(SaleAlertContext ctx) async => [];
}
```

**Core يفحص:**

```dart
final editor = VerticalRegistry.instance.activeManifest.pharmacyProductEditor;
if (editor != null) ...editor.buildAddProductSection(...);
// pharmacy غير نشط → editor == null → واجهة المنتج العادية فقط
```

#### ما **لا** يحدث

- ❌ حقول INN/Rx/ATC في `add_product_screen` لكل التخصصات
- ❌ تنبيهات دوائية في POS لمحل غير صيدلية
- ❌ `if (features.businessVertical == pharmacy)` في 20 ملف — **فقط** في shell + manifest resolver

#### تحسين مقترح (تنظيف مع pharmacy)

اليوم الزيت يستدعي `manifestFor(BusinessVertical.oilChange)` صراحة في `add_product_screen` / `add_invoice_screen`.  
عند pharmacy: **توحيد** إلى `VerticalRegistry.instance.activeManifest` حتى يعمل تلقائياً حسب نشاط المتجر (زيت **أو** صيدلية **أو** لا شيء).

---

## 2. تفاصيل الخطة المعمارية (Architecture Details)

### 2.1 قاعدة البيانات

> كل جدول: `tenant_id` إلزامي · soft delete للسجلات المالية · `INTEGER` fils للمال

| الجدول | المحتوى | التحسينات المضافة ➕ |
|--------|---------|----------------------|
| **`pharmacy_drug_reference`** | اسم عربي + إنجليزي · ATC · دواعي (قائمة + نص) · age band | ➕ تفاعلات دوائية مع مواد أخرى (interaction edges) |
| **`pharmacy_manufacturers`** | النوع (أصلي/جنيس/محلي) · بلد المنشأ | ➕ تصنيف جودة A/B/C |
| **`pharmacy_dosage_forms`** | أقراص · شراب · حقن · كريم… | ➕ وحدات القياس · قابلية التجزئة (شريط من علبة) |
| **`pharmacy_product_profile`** | `product_id` · reference_id · strength · Rx/OTC · monitored schedule · warnings · category (دواء/تجميل/مكمل) | ➕ ربط barcode عام (v1) |
| **`pharmacy_batches`** | batch_no · expiry · qty · cost fils · supplier_id | ➕ barcode دفعة (v2) · recall flag |
| **`pharmacy_stock_policy`** | min · max · reorder qty · shelf location | ➕ FEFO enforced · حد أقصى anti-overstock |
| **`pharmacy_customers_ext`** | chronic meds · allergies · pregnancy flag · medical notes · credit limit | ➕ ربط تأمين (optional FK) |
| **`pharmacy_suppliers_ext`** | payment terms · price history · account balance fils | ➕ vendor returns ledger |
| **`pharmacy_insurance_plans`** | carrier · copay % · covered amount rules · rejection codes | اختياري — feature gate |
| **`pharmacy_recalls`** | batch_no · product · ministry notice · frozen_at | ➕ تجميد فوري لكل الفروع (sync) |

**Extension على Core (لا تكرار):**

- `products` — الاسم التجاري · barcode · sell price · qty (Core)
- `customers` — name · phone · loyalty · debts (Core)
- `suppliers` — AP Core
- `invoices` / `invoice_items` — snapshots سريرية عند البيع (JSON columns)

### 2.2 التنبيهات

| التنبيه | متى يظهر | التحسينات المضافة ➕ |
|---------|----------|----------------------|
| انتهاء الصلاحية | قبل 30/60/90 يوم | ➕ **منع البيع** للصنف المنتهي |
| نقص المخزون | عند الحد الأدنى | ➕ اقتراح Reorder Qty في المشتريات |
| تفاعل دوائي | دواءان لا يجتمعان في الفاتورة | ➕ تجاوز بصلاحية **المدير الصيدلي** فقط |
| حمل/رضاعة | عند إضافة الدواء | ➕ عرض فئة FDA A/B/C/D/X |
| حساسية | عند البيع للعميل المسجّل | — |
| أعراض جانبية | عند عرض الدواء | — |
| دواء مزمن | اقتراب انتهاء دواء العميل | ➕ إشعار WhatsApp/SMS (مرحلة لاحقة) |
| **أدوية مسحوبة** | تعميم Recall | ➕ تجميد batch فوراً |
| **جرعة زائدة** | كمية كبيرة لنفس المريض | ➕ حماية — خصوصاً monitored/psychotropic |

**تنفيذ:** `PharmacyAlertResolver` في vertical — يُستدعى من POS قبل `validateInvoiceBalance`.

### 2.3 البيع والبدائل (POS)

| الميزة | التفاصيل | التحسينات المضافة ➕ |
|--------|----------|----------------------|
| البيع المجهول | بدون اسم عميل | — |
| البيع باسم | اختياري أو ملف كامل | ➕ ربط **التأمين** إن وُجد |
| البحث | عربي + إنجليزي + barcode | ➕ بحث ذكي (مرض/عرض + INN) |
| البدائل | نفس مادة + تركيز + شكل تلقائياً | ➕ ترتيب: tier A/B/C · ربحية · صلاحية |
| FEFO | أقرب صلاحية أولاً + تحذير | ➕ تغيير الدفعة بموافقة (تلف علبة أقدم) |
| Rx/OTC | تمييز · بدون وصفة إلزامية | ➕ **إلزام** طبيب+مريض لأدوية الجدول |
| المرتجعات | صلاحية >3 أشهر + موافقة صيدلاني | ➕ إعادة لنفس batch |

**تكامل Core:** `InvoicesScreen` / `add_invoice_screen` — panel من `PharmacyVerticalManifest.buildPosDrugPanel()` (مثل `fluidInventoryEditor` للزيت).

### 2.4 العملاء

- ملف كامل: اسم · هاتف · تاريخ مشتريات
- **أدوية مزمنة** مسجّلة لكل عميل
- تنبيه تلقائي عند اقتراب انتهاء الدواء المزمن
- تاريخ كل عملية شراء
- ➕ ملاحظات طبية (أمراض غير مزمنة · حساسيات إضافية)
- ➕ **حسابات الآجل:** فواتير آجلة · تنبيهات سداد
- ➕ **ولاء:** نقاط (Core `enableLoyalty` — مفعّل افتراضياً للصيدلية)

**تنفيذ:** `pharmacy_customers_ext` + extension panel في `customer_form_screen` عبر manifest hook (مرحلة 4).

### 2.5 الموردين

- ملف كامل: اسم · هاتف · شروط الدفع
- تاريخ كل توريد · فواتير الشراء
- مقارنة أسعار الموردين لنفس الدواء
- ➕ **مرتجعات الموردين:** تالف/منتهي · مبالغ مستردة
- ➕ **كشف حساب:** مدين/دائن · دورة سداد

**تنفيذ:** `pharmacy_suppliers_ext` + reports — Core AP يبقى مصدر الحقيقة المالي.

### 2.6 التأمين (اختياري — Feature Gate)

- نسب التحمل (copay)
- الرفض وأسبابه
- المبالغ المغطاة
- ربط العميل بخطة تأمين
- ➕ split invoice: covered vs patient pay (fils)

**Gate:** `enablePharmacyInsurance` في `BusinessSetupSettingsData` — off افتراضياً.

### 2.7 التقارير

#### المخزون

- كمية + قيمة + آخر حركة
- تفاصيل كل دفعة وصلاحيتها
- بضاعة راكدة (30/60/90 يوم)
- مقارنة بالشهر الماضي
- ➕ **جرد فعلي (Reconciliation)**
- ➕ **كشف حركة صنف:** من المورد → العميل

#### المبيعات

- يومية / أسبوعية / شهرية
- أكثر الأدوية مبيعاً (كمية + قيمة)
- أكثر العملاء شراءً
- Rx مقابل OTC
- أصلي مقابل جنيس
- ساعات الذروة
- ➕ مبيعات الموظفين (عمولات)
- ➕ مبيعات حسب القسم (تجميل vs أدوية vs مكملات)

#### المالية

- ربح صافي لكل دواء
- هامش الربح
- الديون والمستحقات
- مقارنة أرباح بين الأشهر
- ➕ تقييم مخزون: cost vs expected retail

#### الموردين

- أفضل مورد بالسعر لكل دواء
- تاريخ آخر توريد · فواتires شراء
- ➕ **كشف حساب مورد**

**تنفيذ:** `PharmacyVerticalManifest.reportSections` + `loadReportSectionSnapshot` (نمط oil_change §8).

### 2.8 لوحة المالك (KPIs)

| KPI | مصدر |
|-----|------|
| أدوية تنتهي قريباً | batches + 30/60/90 |
| أدوية نفدت | stock policy |
| أكثر الأدوية مبيعاً | sales agg |
| نسبة أصلي/جنيس | manufacturer type |
| قيمة المخزون الكلية | inventory value |
| الربح اليومي/الشهري | finance repo |
| أفضل العملاء | customer rank |
| أفضل الموردين سعراً | supplier price compare |
| ➕ **معدل دوران المخزون (Turnover)** | stock / COGS |
| ➕ **متوسط قيمة الفاتورة (Ticket Size)** | invoice avg |
| ➕ **المديونية الشاملة** | AR (عملاء/تأمين) + AP (موردين) |

**تنفيذ:** `PharmacyVerticalManifest.resolveOwner` + `loadOwnerSection` (نمط المعيار 12 للزيت).

---

## 3. هيكل `lib/verticals/pharmacy/`

```
verticals/pharmacy/
├── manifest.dart
├── models/
│   ├── drug_reference.dart
│   ├── manufacturer.dart
│   ├── dosage_form.dart
│   ├── product_profile.dart
│   ├── batch.dart
│   ├── customer_ext.dart
│   ├── supplier_ext.dart
│   ├── insurance_plan.dart
│   └── alert_models.dart
├── services/
│   ├── drug_catalog_repository.dart
│   ├── substitute_resolver.dart
│   ├── fefo_picker.dart
│   ├── pharmacy_alert_resolver.dart
│   ├── chronic_med_tracker.dart
│   ├── recall_service.dart
│   └── pharmacy_reports_repository.dart
├── inventory/
│   └── pharmacy_product_editor.dart      ← VerticalFluidInventoryEditor analogue
├── screens/
│   ├── pharmacy_pos_drug_panel.dart      ← embedded in add_invoice
│   ├── drug_catalog_hub_screen.dart
│   └── batch_management_screen.dart
├── widgets/
│   ├── drug_detail_card.dart
│   ├── substitute_list.dart
│   ├── expiry_badge.dart
│   ├── interaction_banner.dart
│   └── rx_capture_sheet.dart
├── reports/
│   ├── pharmacy_inventory_panel.dart
│   ├── pharmacy_sales_panel.dart
│   └── pharmacy_finance_panel.dart
├── owner/
│   ├── pharmacy_dashboard_repository.dart
│   └── pharmacy_morning_brief_builder.dart
└── home/
    └── pharmacy_home_dashboard.dart
```

### 3.1 عقد `PharmacyVerticalManifest`

| القدرة | pharmacy-specific |
|--------|-------------------|
| `id` | `'pharmacy'` |
| `navModules` | مخزون دوائي · POS · دفعات · recalls · تقارير |
| `inventoryPolicy` | expiry+batch إلزامي · drug wizard · Rx/OTC |
| `barcodePolicy` | scan → drug panel + FEFO hint |
| `buildPosDrugPanel` | **جديد في العقد** — panel سريري عند البيع |
| `buildCustomerExtension` | chronic meds · allergies |
| `reportSections` | inventory · sales · finance · suppliers |
| `resolveHome` / `resolveOwner` | KPIs §2.8 |
| `loadOwnerSection` | pharmacy owner loaders |
| `defaultFeatures` | pharmacy onboarding preset |

**قاعدة ذهبية (من oil_change):** Core لا ي import `verticals/pharmacy/*` — فقط `VerticalRegistry.instance.manifestFor(BusinessVertical.pharmacy)`.

---

## 4. مراحل التنفيذ

```
[0: Spec ✅] → [1: Drug Catalog DB]
    → [2: Manifest skeleton + onboarding]
    → [3: Product Editor wizard]
    → [4: POS panel + substitutes + FEFO]
    → [5: Alerts engine]
    → [6: Customers ext + chronic]
    → [7: Suppliers + returns + price compare]
    → [8: Insurance (optional gate)]
    → [9: Reports + Owner/Home]
    → [10: QA ذهبي 15/15]
```

### المرحلة 0 — Spec ✅ (هذه الوثيقة)

- قرارات Executive Summary معتمدة
- خريطة DB · POS · alerts · reports
- لا كود

### المرحلة 1 — Drug Catalog DB (أسبوع 1–2)

**مخرجات:**

- migrations: `pharmacy_drug_reference` · `pharmacy_manufacturers` · `pharmacy_dosage_forms`
- `DrugCatalogRepository` — CRUD + search ar/en + ATC
- seed CSV tool (empty template — **لا بيانات حقيقية** في repo)
- interaction edges table (structure only — rules empty v1)

**تحقق:** unit tests search · tenant isolation · `dart analyze` 0 errors

### المرحلة 2 — Manifest + Feature Gate (أسبوع 2)

**مخرجات:**

- `PharmacyVerticalManifest` مسجّل في `main.dart`
- `routeGuardExact` / `Prefixes` للمسارات الصيدلانية
- `BusinessSetupSettingsData.createForVertical(pharmacy)` — gates جديدة:
  - `enablePharmacyClinicalAlerts`
  - `enablePharmacyInsurance` (off)
  - `enablePharmacyMonitoredRxCapture`
- `HomeDashboardResolver` / `OwnerDashboardProfileResolver` — تفويض فقط

**تحقق:** onboarding pharmacy → manifest active · zero pharmacy imports in core screens

### المرحلة 3 — Product Editor (أسبوع 3–4)

**مخرجات:**

- `PharmacyProductEditor` — wizard خطوتين:
  1. اختيار drug reference (search ar/en/INN/ATC)
  2. SKU: company · strength · form · Rx/OTC · barcode · pricing
- ربط `pharmacy_product_profile` ↔ `products`
- manufacturer picker + tier A/B/C
- age band display (read-only from reference)

**تحقق:** add product pharmacy tenant → profile saved · expiry/batch/grade from existing policy

### المرحلة 4 — POS Panel + Substitutes + FEFO (أسبوع 4–5)

**مخرجات:**

- `PharmacyPosDrugPanel` — INN · company · batch/expiry · indications · tier
- `SubstituteResolver` — same INN+strength+form · sort configurable
- FEFO batch picker · override with pharmacist approval log
- Rx/OTC badge · monitored schedule → `RxCaptureSheet`
- invoice line snapshots (clinical JSON)

**تحقق:** smoke widget test POS panel · substitute swap · FEFO warning

### المرحلة 5 — Alerts Engine (أسبوع 5–6)

**مخرجات:**

- `PharmacyAlertResolver` — كل تنبيهات §2.2
- block sale: expired · recalled
- interaction · pregnancy · allergy · overdose quantity rules
- pharmacist override → audit log (`business_audit_log`)

**تحقق:** integration tests per alert type · override requires role

### المرحلة 6 — Customers Extension (أسبوع 6)

**مخرجات:**

- chronic meds registry · allergy list
- chronic expiry reminder (in-app؛ WhatsApp deferred)
- medical notes · credit limit hook (Core debts)
- loyalty — Core path unchanged

### المرحلة 7 — Suppliers Extension (أسبوع 7)

**مخرجات:**

- price history per drug per supplier
- vendor returns workflow
- supplier statement report
- batch ↔ supplier link on inbound PO

### المرحلة 8 — Insurance (optional — أسبوع 8)

**Gate off by default.**

- plans · copay · covered rules
- invoice split fils
- rejection tracking

### المرحلة 9 — Reports + Owner/Home (أسبوع 8–9)

**مخرجات:**

- all report panels §2.7 via manifest
- owner KPIs §2.8 via `loadOwnerSection`
- `pharmacy_home_dashboard.dart`

### المرحلة 10 — QA ذهبي (أسبوع 10)

15 سيناريو (انظر §8).

---

## 5. MVP vs مراحل لاحقة

| MVP (v1.0 — مراحل 1–5 + 9 جزئي) | v1.1+ |
|----------------------------------|-------|
| Drug catalog ar/en + ATC | import MOH ministry lists |
| Product wizard + batch/expiry | batch barcode |
| POS panel + substitutes + FEFO | insurance split |
| Alerts: expiry · shortage · interaction · recall block | pregnancy FDA full |
| Basic reports: expiry · sales · Rx/OTC | reconciliation UI |
| Owner: expiry · shortage · top sellers | turnover · ticket size |
| Customer chronic meds (manual) | WhatsApp chronic reminder |
| Supplier price compare (read-only) | vendor returns workflow |

---

## 6. Framework والتقنية

| السؤال | الجواب |
|--------|--------|
| Framework جديد؟ | **لا** — Flutter + `provider` + `sqflite` + `VerticalManifest` |
| Package جديد؟ | **لا** — `lib/verticals/pharmacy/` داخل monorepo |
| Riverpod / go_router؟ | **ممنوع** بدون طلب صريح (قواعد المشروع) |
| Cloud drug DB v1؟ | **لا** — SQLite local + CSV import؛ sync لاحقاً |
| Money | **`int fils`** دائماً |
| Tenant | **`tenant_id`** في كل query |

**Option A (المعتمد):** بناء vertical module على نمط `oil_change` المكتمل — أسرع وأقل مخاطرة من greenfield framework.

---

## 7. مخاطر

| خطر | تخفيف |
|-----|--------|
| ادّعاءات طبية / liability | disclaimers · «معلومات مرجعية — استشر الصيدلي» |
| catalog فارغ | CSV import tool · wizard يسمح نص حر مؤقتاً |
| scope creep (insurance day 1) | gate off · مرحلة 8 |
| interaction rules incomplete | block only high-severity · pharmacist override |
| God Screen POS | **لا God Screen** — panel extension في `add_invoice_screen` |
| regression other verticals | feature gates · `flutter test` baseline 805 |

---

## 8. معايير النجاح — «التحويل الكامل»

| # | المعيار |
|---|---------|
| 1 | `PharmacyVerticalManifest` في `VerticalRegistry` |
| 2 | **صفر** imports pharmacy في core screens (post phase 3) |
| 3 | drug reference ar/en + ATC searchable |
| 4 | product wizard → profile + batch |
| 5 | POS: INN · company · expiry · indications · tier |
| 6 | substitutes same INN+strength+form |
| 7 | FEFO + block expired/recalled |
| 8 | alerts: interaction · allergy · overdose (minimum) |
| 9 | customer chronic meds |
| 10 | supplier price compare |
| 11 | reports: expiry · sales · Rx/OTC · originator/generic |
| 12 | owner KPIs §2.8 (minimum 6 cards) |
| 13 | RTL · 3 breakpoints |
| 14 | `flutter test` ≥ 805 passed (no regression) |
| 15 | QA manual 15 scenarios on device |

### سيناريوهات QA (15)

1. onboarding pharmacy · gates correct  
2. add drug via wizard · batch · expiry  
3. POS anonymous sale  
4. POS named customer · allergy warning  
5. substitute swap · tier sort  
6. FEFO · override logged  
7. expired batch · **blocked**  
8. recall batch · **blocked all branches**  
9. interaction two drugs · block · pharmacist override  
10. monitored Rx · doctor fields required  
11. chronic med · expiry reminder  
12. supplier price compare report  
13. Rx vs OTC sales report  
14. owner dashboard expiry KPI  
15. RTL tablet + phone  

---

## 9. ما لا نفعله (v1)

- لا encyclopedia طبية كاملة offline
- لا تشخيص AI · لا «هذا الدواء أفضل طبياً»
- لا package منفصل · لا APK صيدلية منفصل
- لا تغيير `biz.vertical` بعد onboarding
- لا hard delete للسجلات المالية

---

## 10. المراجع

- `docs/specs/vertical_oil_change_migration_v1.md` — قالب المراحل والمعايير
- `lib/verticals/_contract/vertical_manifest.dart` — العقد (يُوسَّع لـ `buildPosDrugPanel`)
- `lib/services/inventory_policy_settings.dart` — `BusinessProfile.pharmacy`
- `lib/services/business_setup_settings.dart` — `BusinessVertical.pharmacy`

---

## 11. الخطوة التالية

**بعد اعتماد هذه الوثيقة:**

1. المرحلة 1 — migrations + `DrugCatalogRepository` + CSV template  
2. **لا بيانات دوائية حقيقية** في repository — tenant يستورد أو يُدخل يدوياً  

> **سؤال Framework:** لا حاجة لإطار جديد — **Option A معتمد:** Flutter Naboo + Vertical Module pattern (مثل `oil_change`).
