# تقرير التقدّم — تخصص الصيدلية (Naboo Pharmacy)

> **الحالة:** ⏸️ **متوقف مؤقتاً** — يُستأنف لاحقاً  
> **آخر تحديث:** 2026-06-11  
> **المرجع الأصلي:** [`vertical_pharmacy_migration_v1.md`](vertical_pharmacy_migration_v1.md)  
> **ملحق QA:** [`../qa/golden_path_test_results_pharmacy_2026-06-13.md`](../qa/golden_path_test_results_pharmacy_2026-06-13.md)

---

## 1. ملخص تنفيذي

تم بناء **Vertical Module كامل** للصيدلية تحت `lib/verticals/pharmacy/` وفق نمط `oil_change`، مع ربط Core عبر `VerticalManifest` و`VerticalRegistry` **بدون** استيراد مباشر من Core إلى pharmacy.

| المؤشر | الوضع |
|--------|--------|
| هيكل Vertical + Manifest | ✅ |
| كatalog دواء (مرجع · شركات · أشكال) | ✅ |
| إضافة دواء (معالj 3 أوضاع) | ✅ |
| POS drug panel + FEFO + بدائل | ✅ |
| تنبيهات سريرية (resolver) | ✅ |
| ملف عميل صيدلاني (حساسية · مزمنة) | ✅ |
| تقارير + KPIs لوحة المالk | ✅ |
| اختبارات `test/pharmacy/` | ✅ ~83 (فشل واحد معروف غير مرتبط) |
| QA Golden Path (15 سيناريو) | ⚠️ 8 ✅ · 6 ⚠️ · 1 ❌ (قبل إصلاح P0) |
| Play Store v1.0 | ⚠️ تحضير جزئي — يحتاج QA يدوي + أصول المتجر |
| إعدادات UI لاختيار Mode A/B/C | ❌ مؤجل |

---

## 2. مراحل التنفيذ المكتملة

| المرحلة | المحتوى | الحالة |
|---------|---------|--------|
| **1** | `PharmacyVerticalManifest` · تسجيل في `VerticalRegistry` · جداول SQLite (`pharmacy_db_schema`) | ✅ |
| **2** | `DrugCatalogRepository` · نماذج مرجع · استيراد CSV للمواد الفعّالة | ✅ |
| **3** | `PharmacyProductEditor` — profile + batch + stock policy عند إضافة منتج | ✅ |
| **4** | `PharmacyPosDrugPanel` · FEFO · `SubstituteResolver` | ✅ |
| **5** | `PharmacyAlertResolver` (صلاحية · تفاعل · حساسية · جرعة · …) | ✅ |
| **6** | ملف عميل: `PharmacyCustomerRepository` · sheet · banner حساسيات | ✅ |
| **7** | فواتير صيدلية · `PharmacyInvoicesScreen` | ✅ |
| **8** | ربط Core: `add_product_screen` · `add_invoice_screen` · customers | ✅ |
| **9** | تقارير §9 · `PharmacyReportsRepository` · KPIs · لوحة مالk | ✅ |
| **10** | QA Golden Path + توثيق النتائج | ⚠️ (انظر §8) |
| **+** | **معالj إضافة دواء** (Modes A/B/C) | ✅ (آخر عمل قبل التوقف) |
| **+** | تحضير إصدار v1.0 (pubspec · builds · docs متجر) | ⚠️ جزئي |

---

## 3. البنية المعمارية

```
lib/verticals/pharmacy/
├── manifest.dart                 ← VerticalManifest + ربط Core
├── models/                       ← drug_reference, batch, profile, alerts, reports, …
├── services/                     ← catalog, alerts, reports, KPI, FEFO, substitutes, …
├── inventory/                    ← محرّr المنتج + المعالj (Wizard)
├── screens/                      ← POS panel, invoices, reports, owner dashboard
├── widgets/                      ← KPI grid, report panels, allergy badge, …
└── constants/

lib/verticals/_contract/
└── vertical_manifest.dart        ← عقود VerticalPharmacyProductEditor, alerts, POS, …

Core (بدون if pharmacy مباشر في المنطق الجديد):
├── add_product_screen.dart       ← session من manifest
├── add_invoice_screen.dart       ← evaluateSaleAlerts + override audit
├── reports_screen.dart           ← §9 pharmacy
└── owner_dashboard_v3_panel.dart ← PharmacyOwnerDashboardPanel
```

**قاعدة ذهبية:** حقول الصيدلية تظهر فقط عندما `businessVertical == pharmacy` عبر `VerticalRegistry.activeManifest`.

---

## 4. قاعدة البيانات والنماذج

جداول رئيسية (tenant-scoped · soft delete حيث ينطبق):

| جدول / كيان | الغرض |
|-------------|--------|
| `pharmacy_drug_reference` | INN · ATC · دواعي · age band |
| `pharmacy_manufacturers` | شركة · نوع · بلد · tier A/B/C |
| `pharmacy_dosage_forms` | أقراص · شراب · حقن · … |
| `pharmacy_product_profile` | ربط `products` بالمرجع + Rx/OTC + strength |
| `pharmacy_batches` | دفعة · صلاحية · cost fils · FEFO |
| `pharmacy_stock_policy` | سياسة مخزون للـ SKU |
| `pharmacy_customer_ext` | حساسيات · أدوية مزمنة · ملاحظات |

**المال:** دائماً `int fils` — لا `double` للأسعار.

**استيراد CSV:**  
`assets/pharmacy/drug_reference_import_template.csv`  
`PharmacyDrugReferenceCsvImporter` + اختبارات.

---

## 5. الميزات حسب المجال

### 5.1 المخزون — إضافة دواء

**قبل:** شاشة واحدة طويلة (كل الحقول معاً).

**الآن:** معالj `PharmacyProductEditorWizard` بثلاثة أوضاع:

| Mode | الخطوات | الاستخدام |
|------|---------|-----------|
| **A** | 4 | مادة فعّالة → تجاري → دفعة/Rx → سعر/كمية/ملاحظات |
| **B** | 2 | معلومات مجمّعة → دفعة + سعر |
| **C** | 6 | شاشة منفصلة لكل قسم |

**ملفات المعالj:**

```
lib/verticals/pharmacy/inventory/
├── pharmacy_product_editor_wizard.dart      ← controller + widget + sheet launcher
├── pharmacy_product_editor_state_holder.dart
├── pharmacy_product_editor_mode.dart          ← PharmacyEditorMode + Store (prefs)
├── pharmacy_product_editor_form.dart          ← حالة النموذج + save
├── pharmacy_product_editor_sections.dart      ← UI + PharmacyProductEditorStepLayout
├── pharmacy_product_editor_validation.dart    ← تحقق كامل + per-step
├── pharmacy_product_editor_save_service.dart
├── pharmacy_product_editor_mode_a_step1..4.dart
├── pharmacy_product_editor_mode_b_step1..2.dart
├── pharmacy_product_editor_mode_c_steps.dart
├── pharmacy_product_editor_mode_a.dart        ← غلاف Mode A
└── pharmacy_product_editor.dart               ← session + VerticalPharmacyProductEditor
```

**الدمج في Core:**

- **مسار مستقل:** `openPharmacyProductEditorWizard()` / `openPharmacyProductEditorModeA()`
- **إضافة منتج:** زر «فتح معالj إضافة دواء» → `showPharmacyProductEditorWizardSheet()` (`draftOnly` — يملأ session دون حفظ DB منفصل)

**تفضيل الوضع:** `PharmacyEditorModeStore` — مفتاح SharedPreferences `pharmacy.editor_mode` (`mode_a` | `mode_b` | `mode_c`).  
**لم يُربَط بعد** بـ `BusinessSetupSettingsData` أو شاشة إعدادات.

### 5.2 نقطة البيع (POS)

- `PharmacyPosDrugPanel` — INN · ATC · FEFO · بدائل
- `PharmacyAlertResolver.evaluateSaleAlerts()` من `add_invoice_screen`
- override للتنبيهات مع `_logPharmacyAlertOverride` (audit)
- `buildCustomerAllergiesBanner` في manifest

### 5.3 العملاء

- `PharmacyCustomerDetailSheet` — حساسيات · أدوية مزمنة · ملاحظات
- `recordRefillsFromSale` — last purchase للمزمنة
- extension section في نموذج العميل عبر manifest

### 5.4 التنبيهات السريرية

| كود | السلوك |
|-----|--------|
| `expired_batch` | يمنع البيع |
| `expiring_batch_warning` | تحذير 1–30 يوم (**P0 — أُضيف بعد QA**) |
| `drug_interaction` | placeholder من CSV |
| `customer_allergy` | من ملف العميل |
| `overdose_monitored` | جرعة > 100 للمراقبة |

### 5.5 التقارير ولوحة المالk

- `PharmacyReportsRepository` — مخزون · صلاحية · مبيعات · موردين · مالية (cache 5 دقائق)
- `PharmacyKpiCalculator` — 12 KPI
- `PharmacyOwnerDashboardPanel` · `pharmacyReportSections` في manifest
- شاشات: inventory / sales / finance / supplier reports
- `reports_screen` — القسم §9

---

## 6. الاختبارات

```
test/pharmacy/
├── pharmacy_vertical_manifest_test.dart
├── drug_catalog_repository_test.dart
├── pharmacy_drug_reference_csv_importer_test.dart
├── pharmacy_product_editor_mode_a_test.dart
├── pharmacy_product_editor_wizard_test.dart      ← 10 tests (A/B/C + validation)
├── pharmacy_alert_resolver_test.dart
├── pharmacy_pos_drug_panel_test.dart
├── pharmacy_customer_repository_test.dart
├── pharmacy_customer_detail_sheet_test.dart
├── pharmacy_invoices_screen_test.dart
├── pharmacy_reports_repository_test.dart
├── pharmacy_kpi_calculator_test.dart
└── pharmacy_kpi_cards_grid_test.dart
```

**أوامر التحقق:**

```bash
flutter test test/pharmacy/
flutter test test/pharmacy/pharmacy_product_editor_wizard_test.dart
flutter test test/screens/add_product_screen_test.dart
dart analyze lib/verticals/pharmacy/
```

**ملاحظات:**

- `pharmacy_customer_repository_test` — فشل متقطع/معروف في بعض تشغيلات CI (83 passed · 1 failed في آخر تشغيل كامل)
- `db_performance_test` soft-delete — فشل عام في المشروع، غير مرتبط بالصيدلية

---

## 7. تحضير إصدار v1.0

| العنصر | الحالة |
|--------|--------|
| `pubspec.yaml` → `1.0.0+1` | ✅ |
| Android `compileSdk 36` · APK/AAB builds | ✅ (مع `--no-tree-shake-icons`) |
| iOS `Info.plist` version | ✅ |
| `docs/store/play_store_metadata.md` | ✅ |
| `PRIVACY.md` · `TERMS.md` · `CHANGELOG.md` · `USER_GUIDE.md` | ✅ |
| `docs/store/v1.0_release_checklist.md` | ✅ |
| keystore إنتاج · privacy URL · أصول المتجر · QA يدوي | ❌ قبل النشر |

---

## 8. QA Golden Path — ملخص

التفاصيل الكاملة: [`../qa/golden_path_test_results_pharmacy_2026-06-13.md`](../qa/golden_path_test_results_pharmacy_2026-06-13.md)

**بعد كتابة تقرير QA:**

- ✅ **P0 #6** — `PharmacyAlertCodes.expiringBatchWarning` + `PharmacyBatch.daysUntilExpiryOn()` + resolver warning 1–30 يوم
- ⚠️ **P1** — E2E override audit · widget test banner · QA جهاز · perf soft-delete
- ⚠️ **P2** — مواءمة spec `enablePharmacy*` مع التنفيذ الفعلي

**يُنصح** بتحديث ملف QA ليعكس إصلاح P0 (#6 → ✅) عند الاستئناف.

---

## 9. ما لم يُنجز / مؤجل عند التوقف

| البند | الأولوية |
|-------|----------|
| UI إعدادات لاختيار Mode A/B/C في `BusinessSetupSettingsData` | P2 |
| `enablePharmacyInsurance` والتأمين | غير منفّذ (spec) |
| E2E آلي لحفظ فاتورة POS كاملة | P1 |
| Widget test لـ banner حساسيات في `add_invoice_screen` | P1 |
| Golden tests RTL / tablet | P1 |
| QA يدوي phone + tablet + offline | P1 |
| Play Store: keystore · URLs · screenshots | قبل الإطلاق |
| تحديث `vertical_pharmacy_migration_v1.md` §1.3 «الوضع الحالي» (لا يزال «لم يبدأ») | توثيق |

---

## 10. كيفية الاستئناف

1. **اقرأ هذا الملف** + QA golden path.
2. **شغّل** `flutter test test/pharmacy/` للتأكد من baseline.
3. **اختر مساراً:**
   - إكمال QA / Play Store (P0–P1)
   - إعدادات Mode A/B/C في inventory settings
   - ميزات spec متبقية (تأمين · barcode batch · …)
4. **لتغيير وضع المعالj برمجياً:**

```dart
await PharmacyEditorModeStore.save(PharmacyEditorMode.modeB);
```

5. **Spec الأصلي** يبقى مرجع المتطلبات طويلة المدى — هذا التقرير يسجّل **ما بُني فعلياً**.

---

## 11. مراجع سريعة

| الموضوع | الملف |
|---------|-------|
| Spec كامل | `docs/specs/vertical_pharmacy_migration_v1.md` |
| QA | `docs/qa/golden_path_test_results_pharmacy_2026-06-13.md` |
| Manifest | `lib/verticals/pharmacy/manifest.dart` |
| معالj الدواء | `lib/verticals/pharmacy/inventory/pharmacy_product_editor_wizard.dart` |
| قالب CSV | `assets/pharmacy/drug_reference_import_template.csv` |
| checklist متجر | `docs/store/v1.0_release_checklist.md` |

---

*نهاية التقرير — آخر عمل: معالj إضافة الدواء (Modes A/B/C) + اختبارات wizard.*
