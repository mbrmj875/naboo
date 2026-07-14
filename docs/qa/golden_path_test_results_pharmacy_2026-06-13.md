# نتائج Golden Path — تخصص الصيدلية

**التاريخ:** 2026-06-13  
**البيئة:** CI محلي (macOS) — `flutter test` + `dart analyze` + مراجعة كود  
**الإصدار:** pharmacy vertical v1.0 (مراحل 1–9)

---

## ملخص تنفيذي

| المؤشر | النتيجة |
|--------|---------|
| سيناريوهات ذهبية (15) | **8 ✅ · 6 ⚠️ · 1 ❌** |
| Regression (8 مجالات) | **6 ✅ · 1 ⚠️ · 1 ❌** |
| `flutter test test/pharmacy/` | **71/71 passed** |
| `dart analyze` (errors) | **0 errors** (410 info/warning قديمة في المشروع) |
| جاهزية Play Store v1.0 | **❌ لا — يتطلب إصلاح #6 + QA يدوي على جهاز** |

---

## نتائج الاختبار — 15 سيناريو ذهبي

| # | السيناريو | النتيجة | دليل / ملاحظات |
|---|-----------|---------|----------------|
| 1 | Onboarding صيدلية | ✅ | `PharmacyVerticalManifest` + `ensurePharmacyCatalogTables`؛ `pharmacy_vertical_manifest_test` |
| 2 | Feature Gates | ⚠️ | `createForVertical(pharmacy)` → POS ON، oil OFF؛ **لا توجد مفاتيح `enablePharmacy*` منفصلة** (المو spec ≠ التنفيذ الحالي) |
| 3 | إضافة دواء أساسي | ✅ | `pharmacy_product_editor_mode_a_test` — profile + batch + stock policy |
| 4 | Interaction placeholder | ✅ | `pharmacy_drug_reference_csv_importer_test` + `pharmacy_alert_resolver_test` (interaction) |
| 5 | بيع بسيط + POS panel | ⚠️ | `pharmacy_pos_drug_panel_test` (INN · ATC · FEFO)؛ **لا E2E آلي لحفظ فاتورة كاملة** |
| 6 | تحذير صلاحية (30 يوم) | ❌ | **`PharmacyAlertResolver` يمنع المنتهي فقط** — لا banner تحذير لـ ≤30 يوم في POS/alerts |
| 7 | منع بيع منتهي | ✅ | `pharmacy_alert_resolver_test` — `expiredBatch` + `blocksSale: true` |
| 8 | تحذير تفاعل + override + audit | ⚠️ | resolver ✅؛ `_logPharmacyAlertOverride` في `add_invoice_screen` ✅؛ **لا test لسجل audit** |
| 9 | تحذير حساسية + override | ⚠️ | `customerAllergy` في resolver ✅؛ override UI موجود؛ **لا E2E آلي** |
| 10 | تحذير جرعة زائدة | ✅ | `pharmacy_alert_resolver_test` — monitored qty >100 |
| 11 | أدوية مزمنة + last_purchase | ✅ | `pharmacy_customer_repository_test` — `recordRefillsFromSale` |
| 12 | banner حساسيات في POS | ⚠️ | `buildCustomerAllergiesBanner` في manifest ✅؛ **لا widget test لـ banner في شاشة البيع** |
| 13 | تقرير مخزون | ✅ | `pharmacy_reports_repository_test` — expiry / out-of-stock / bundle |
| 14 | لوحة المالk 12 KPI | ✅ | `pharmacy_kpi_*` + manifest `loadOwnerDashboard` → 12 entries؛ لا NaN |
| 15 | RTL + overflow | ⚠️ | widget tests بـ `TextDirection.rtl` ✅؛ **لا golden على phone/tablet**؛ الأرقام Western (0–9) حسب قواعد المشروع وليس Arabic-Indic |

---

## Regression Tests

| Feature | Test | النتيجة | ملاحظات |
|---------|------|---------|---------|
| Oil Change | `oil_change_order_form_smoke_test` + `owner_oil_dashboard_repository_test` | ✅ | OK |
| Retail | `add_product_screen_test` + `phase6_owner_dashboard_regression_test` | ✅ | OK |
| Invoices (Core) | `pharmacy_invoices_screen_test` | ✅ | OK |
| Customers (Core) | `pharmacy_customer_repository_test` + detail sheet | ✅ | OK |
| Reports (Core) | sections 0–9 في `reports_screen` (code review) | ⚠️ | §9 pharmacy مضاف؛ **لا widget test لشاشة التقارير الكاملة** |
| Offline Sync | — | ⚠️ | **لم يُشغَّل** في هذه الجلسة |
| Multi-tenant | `product_variants_tenant_isolation_test` + pharmacy tenant tests | ✅ | OK |
| Performance | `db_performance_test` | ❌ | **1 فشل:** `soft delete 100 records < 500ms` (غير مرتبط بالصيدلية) |

---

## معايير النجاح (Acceptance Criteria)

| # | المعيار | Status |
|---|---------|--------|
| 1 | 15/15 سيناريو ذهبي pass | ❌ (8/15 صارم · 14/15 مع ⚠️ كـ «مقبول جزئياً») |
| 2 | 0 regression | ⚠️ (فشل perf واحد + gaps reports/sync) |
| 3 | `flutter test` ≥ 71 passed | ✅ (71 pharmacy) |
| 4 | `dart analyze` 0 errors | ✅ |
| 5 | RTL + no overflow | ⚠️ (RTL آلي؛ overflow يحتاج جهاز) |
| 6 | Performance <3s large datasets | ⚠️ (perf suite OK عدا soft-delete؛ **لا test 1000 invoice للصيدلية**) |
| 7 | Offline/Online toggle | ⚠️ (لم يُختبر يدوياً) |
| 8 | Mobile + Tablet | ⚠️ (لم يُختبر يدوياً) |

---

## فجوات يجب إصلاحها قبل Play Store

### P0 — blocker

1. **#6 تحذير صلاحية قريبة (≤30 يوم)**  
   أضف في `PharmacyAlertResolver._batchAlerts` تنبيهاً `warning` (لا يمنع البيع) عندما `expiryDay ≤ saleDay + 30`.

### P1 — قبل الإطلاق

2. **اختبار E2E لـ override + audit log** (`pharmacy_alert_override` في `BusinessAuditLogService`).  
3. **Widget test لـ banner حساسيات** في `add_invoice_screen`.  
4. **QA يدوي على جهاز:** phone + tablet، offline flush، overflow بصري.  
5. **إصلاح / ratchet** `db_performance_test` soft-delete إن كان regression حقيقي.

### P2 — توثيق

6. مواءمة spec «`enablePharmacy*`» مع `businessVertical == pharmacy` أو إضافة gates صريحة.

---

## أوامر التحقق المُعاد تشغيلها

```bash
flutter test test/pharmacy/ --concurrency=1          # 71 passed
flutter test test/owner/phase6_owner_dashboard_regression_test.dart
flutter test test/oil_change_order_form_smoke_test.dart
dart analyze                                         # 0 errors
```

---

## الخلاصة

التخصص الصيدلاني **قوي على مستوى المنطق والاختبارات الآلية (71 test)**، لكن **ليس جاهزاً لـ Play Store v1.0** حتى:

- إغلاق فجوة **تحذير الصلاحية القريبة (#6)**  
- إكمال **QA يدوي على جهاز** للسيناريوهات ⚠️  
- تأكيد **عدم regression** في perf suite

**التوصية:** إصلاح P0 → retest → QA يدوي 2–3 ساعات → ثم v1.0.
