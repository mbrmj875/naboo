# خطة تنفيذ المرحلة 2 — إغلاق فجوات المزامنة والمحاسبة

> **النسخة:** v1
> **التاريخ:** 2026-06-02
> **المرجع المُحرّك:** `docs/specs/system_risk_analysis_full_2026-06-02.md`
> **المالك التقني:** فريق Naboo / Basra Store Manager
> **الحالة:** Approved for execution

---

## 1. السياق والنطاق

التقرير الشامل في `system_risk_analysis_full_2026-06-02.md` كشف 5 فجوات جوهرية و4 ثغرات جديدة. هذه الوثيقة **تنفيذية** — تحوّل المراجعة إلى 5 PRs قابلة للقياس مع معايير قبول و rollback.

**الهدف:** إغلاق ثغرات sync وسلامة بيانات فورية **قبل** بناء نظام Ledger الكامل.

**خارج النطاق:**
- بناء `debt_ledger` كامل (مرحلة منفصلة).
- تجميد الفاتورة بالمعنى الكامل (Immutability المعماري).
- ESC/POS للطابعات الحرارية.
- تحويل margin queries إلى fils (Medium impact، يؤجَّل).
- ترقيع كل الـ 94 حالة `catch (_) {}` (انتقائي فقط).

---

## 2. تحفظات حاسمة (Caveats)

### 2.1 `max(advancePayment)` حماية تكتيكية وليست نهائية

PR-1 يستبدل LWW الأعمى بـ `max(localFils, incomingFils)` لمنع مسح التسديدات. لكن:

| السيناريو | LWW اليوم | `max()` بعد PR-1 | Ledger النهائي |
|-----------|-----------|------------------|----------------|
| دفع offline ثم incoming قديم | قد يُمسح | محمي | محمي |
| جهازان يدفعان بنفس الوقت | يفوز الأخير | **يُختزل المجموع** | صحيح كلياً |
| مرتجع بعد دفع | محمي حالياً | محمي | محمي |

**النتيجة المحاسبية المهمة:** جدول `customer_debt_payments` يبقى **immutable** ويحتفظ بكل الدفعات كاملةً (دليل محاسبي محفوظ). الفقد المحتمل في السيناريو الثاني يقتصر على **عمود مشتق** (`invoices.advancePayment`)، لا على الدليل نفسه.

**الحل النهائي:** PR-Ledger يحوّل `advancePayment` إلى قراءة مشتقة `SUM(customer_debt_payments WHERE invoice_id = ?)`.

### 2.2 لا تغييرات سكيما في PR-1..3

PR-1, PR-2, PR-3 **لا تلمس migrations**. هذا متعمَّد لتقليل سطح المخاطرة. PR-4 وحده يلمس migrations، و PR-5 يضيف أعمدة `*Fils` للأقساط.

### 2.3 ترتيب التنفيذ ملزم

الترتيب 1 → 5 ليس اقتراحاً. PR-5 (items + installments) يستخدم نفس بنية الحماية من PR-1. تنفيذ PR-5 قبل PR-1 = duplication.

---

## 3. مسرد المفاهيم

| المصطلح | المعنى في هذا المشروع |
|---------|----------------------|
| **LWW** | Last-Write-Wins — السجل ذو `updatedAt` الأحدث يستبدل المحلي |
| **Merge protected field** | حقل تُهمَل قيمته الواردة ويبقى المحلي مهما كان timestamp |
| **Immutable event** | سجل لا يُحدَّث بعد إنشائه (مثل `cash_ledger`, `customer_debt_payments`) |
| **Derived column** | عمود يمكن إعادة حسابه من جدول آخر |
| **Outstanding** | `totalFils - advancePaymentFils > 0` لفاتورة غير مرتجعة |

---

## 4. كتالوج الـ PRs

### PR-1 — حماية merge الفواتير

**الأولوية:** P0 — يجب البدء بها.
**التقدير:** 1–2 يوم.

#### الهدف
استبدال `_doMergeWithGlobalId` العام في `_mergeInvoicesByGlobalId` بسياسة merge مخصصة تحمي الحقول المالية وتطبّق `max()` على `advancePayment*`.

#### الملفات
- `lib/services/cloud_sync_service.dart` — تعديل `_mergeInvoicesByGlobalId`.
- `test/security/invoice_merge_protection_test.dart` — جديد.

#### سياسة الحقول

| الفئة | الحقول | السياسة |
|------|--------|---------|
| **مجمدة** | `total`, `totalFils`, `discount`, `discountFils`, `discountPercent`, `tax`, `taxFils`, `loyaltyDiscount`, `loyaltyDiscountFils`, `loyaltyPointsRedeemed`, `loyaltyPointsEarned`, `isReturned`, `originalInvoiceId`, `type` | المحلي يفوز دائماً |
| **`max()`** | `advancePayment`, `advancePaymentFils` | `max(local, incoming)` |
| **LWW** | `customerName`, `deliveryAddress`, `customerId`, `updatedAt` | إذا فاز incoming |
| **Enrichment** | `workShiftId`, `actorUserId`, `shiftOwnerUserId`, `createdByUserName` | تُملأ فقط لو المحلي null/0 |

#### حالات الاختبار (إلزامية — جميعها يجب أن تمر)

```
T1: local advancePaymentFils=500_000, incoming=0 (newer)
    → نتيجة: 500_000 (محمي)

T2: local=200_000, incoming=800_000 (newer)
    → نتيجة: 800_000 (max يأخذ الأعلى)

T3: local total=1_000_000, incoming total=900_000 (newer)
    → نتيجة: total=1_000_000 (مجمد)

T4: لا يوجد local row + incoming
    → insert كامل

T5: incoming = tombstone (deletedAt set)
    → tombstone محترم، الصف يُحذف

T6: enrichment — local workShiftId=null, incoming=42
    → نتيجة: 42 (إثراء)

T7: enrichment لا يُكتب فوق قيمة — local actorUserId=7, incoming=9
    → نتيجة: 7 (لا overwrite)
```

#### معايير القبول
- [ ] T1..T7 جميعها تمر.
- [ ] `test/suites/sync/data_integrity_sync_test.dart` لا يكسر.
- [ ] `test/security/lww_clock_skew_test.dart` لا يكسر.
- [ ] لا تغيير في `database_helper.dart` (لا migration).
- [ ] تعليق `// PR-1: tactical max() — see roadmap_phase2_execution_v1 §2.1` فوق دالة merge الجديدة.

#### Rollback
```
git revert <commit>
```
لا أثر على DB. إعادة النشر فورية. الـ snapshot التالي من جهاز آخر سيعيد كتابة الفواتير بالسلوك القديم (LWW الأعمى) — مقبول كحالة طارئة.

---

### PR-2 — منع حذف عميل بديون مفتوحة

**الأولوية:** P0.
**التقدير:** 4–8 ساعات.

#### الهدف
رفض `deleteCustomers` إذا كان لدى أي عميل من القائمة فاتورة آجل/تقسيط مفتوحة أو خطة تقسيط نشطة.

#### الملفات
- `lib/services/db_customers.dart` — `deleteCustomers()`.
- `test/security/customer_delete_guard_test.dart` — جديد.

#### المنطق

قبل `txn.delete('customers')` لكل `id`:

```sql
-- 1) فواتير credit/installment مفتوحة
SELECT COUNT(*) FROM invoices
WHERE tenantId = ? AND customerId = ?
  AND deleted_at IS NULL
  AND IFNULL(isReturned, 0) = 0
  AND type IN (?, ?)  -- credit, installment
  AND (IFNULL(totalFils, 0) - IFNULL(advancePaymentFils, 0)) > 0

-- 2) خطط تقسيط نشطة
SELECT COUNT(*) FROM installment_plans
WHERE tenantId = ? AND customerId = ?
  AND IFNULL(paidAmount, 0) < IFNULL(totalAmount, 0)
```

إذا أي count > 0 → ترمي `StateError` برسالة عربية تذكر اسم العميل وعدد الفواتير/الأقساط المفتوحة.

#### حالات الاختبار (4 إلزامية)

```
T1: عميل بفاتورة credit مفتوحة (advancePayment < total)
    → deleteCustomer يرمي StateError

T2: عميل بخطة تقسيط نشطة فقط (paidAmount < totalAmount) — لا فواتير
    → deleteCustomer يرمي StateError  ⟵ السيناريو الذي أضافه المراجع

T3: عميل بفاتورة credit مسدّدة كلياً (advancePayment == total)
    → deleteCustomer ينجح

T4: عميل بفاتورة مرتجعة (isReturned=1) أو محذوفة منطقياً
    → deleteCustomer ينجح
```

#### معايير القبول
- [ ] T1..T4 تمر.
- [ ] الرسالة بالعربية وتذكر `customerName` و عدد الالتزامات.
- [ ] `customers_screen.dart` و `customer_contacts_screen.dart` يعرضان الخطأ في SnackBar (لا تغيير كود مطلوب — `catch (e)` الموجود يعمل).
- [ ] الـ `deleteCustomers` يبقى atomic — إذا فشل عميل واحد، لا يُحذف أي عميل من القائمة.

#### Rollback
```
git revert <commit>
```
لا أثر على DB. السلوك يعود إلى السماح بالحذف.

---

### PR-3 — تسجيل audit دائم لاستثناء المالك

**الأولوية:** P1.
**التقدير:** 2–4 ساعات (البنية جاهزة).

#### الهدف
عندما يستخدم المالك "كسر الطوارئ" للخروج/تبديل الحساب مع وردية مفتوحة، يُكتب سجل في `business_audit_events` بدلاً من `AppLogger.warn` فقط.

#### الملفات
- `lib/providers/auth_provider.dart` — `_assertNoOpenShiftBlockingAction()`.
- `test/phase1_owner_shift_bypass_regression_test.dart` — توسيع.

#### المنطق

داخل الفرع `if (_roleKey == 'owner' && allowOwnerEmergencyOverride)`:

```dart
AppLogger.warn(
  'AuthProvider',
  '$ownerEmergencyLogLabel: shiftId=$shiftId',
);
// PR-3: audit دائم لاستثناءات المالك
unawaited(BusinessAuditLogService.instance.record(
  eventType: 'owner_emergency_shift_bypass',
  entityType: 'work_shift',
  entityId: '$shiftId',
  userId: _userId,
  username: _username,
  newValueJson: jsonEncode({
    'action': actionLabel,
    'shiftStaffName': shiftStaffName,
  }),
));
return;
```

#### حالات الاختبار

```
T1: regression — وجود استدعاء record() ضمن الفرع
    (regex على ملف auth_provider.dart مثل phase1_owner_shift_bypass_regression_test)

T2: integration (اختياري — يمكن تأجيلها):
    استدعاء _assertNoOpenShiftBlockingAction كمالك مع وردية مفتوحة
    → يجب أن تظهر صف في business_audit_events
```

#### معايير القبول
- [ ] T1 يمر.
- [ ] `business_audit_events` يحوي event_type جديد `owner_emergency_shift_bypass`.
- [ ] الـ owner_sensitive_actions_panel يعرض الحدث تلقائياً (لا تغيير UI مطلوب).
- [ ] الاستدعاء **بدون TODO comment** — البنية الحالية تسمح بـ Provider→Service مباشرة (`db_debts`, `db_stock`, `product_repository` كلها تفعل ذلك).

#### Rollback
```
git revert <commit>
```
السجلات السابقة في `business_audit_events` تبقى. السلوك يعود لـ `AppLogger.warn` فقط.

---

### PR-4 — معالجة catch صامتة في migrations المالية

**الأولوية:** P1.
**التقدير:** 1–2 يوم.

#### الهدف
استبدال `catch (_) {}` بمنطق ذكي يميّز:
- **"العمود موجود بالفعل"** → تجاهل بصمت (طبيعي عند upgrade مكرر).
- **خطأ حقيقي** (صلاحيات، disk، sqlite corruption) → log + rethrow.

> ⚠️ هذا تعديل من المراجعة: feature flag على `rethrow` كان سيخلق "خطر صامت" — التطبيق يعمل على schema ناقص. النمط الجديد لا يحتاج flag.

#### الملفات
- `lib/services/database_helper.dart` — استبدال ~10–15 catch حرجة فقط.
- `lib/utils/db_migration_safety.dart` — جديد (helper).
- `test/security/migration_safety_test.dart` — جديد.

#### النمط المُقدَّم

```dart
// lib/utils/db_migration_safety.dart
class DbMigrationSafety {
  /// أخطاء SQLite الآمنة عند upgrade مكرر:
  /// - "duplicate column name" — العمود مضاف بالفعل.
  /// - "table ... already exists" — الجدول قائم.
  /// - "index ... already exists" — الفهرس قائم.
  static bool isBenignMigrationError(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('duplicate column') ||
           msg.contains('already exists');
  }

  /// نفّذ ALTER/CREATE migration مع التمييز بين الأخطاء الحميدة والحقيقية.
  static Future<void> runIdempotent(
    String migrationLabel,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e, st) {
      if (isBenignMigrationError(e)) {
        // طبيعي — العمود/الجدول قائم
        return;
      }
      AppLogger.error('Migration', '$migrationLabel failed', e, st);
      rethrow;
    }
  }
}
```

#### نطاق الاستبدال (انتقائي — ليس 94)

استبدال **فقط** في migrations التي تضيف:

| نوع | أمثلة | عدد تقريبي |
|------|--------|------------|
| أعمدة `*Fils` | `totalFils`, `advancePaymentFils`, `amountFils` | ~5 |
| أعمدة actor/shift | `actorUserId`, `shiftOwnerUserId`, `workShiftId` | ~3 |
| أعمدة sync | `global_id`, `updatedAt`, `deleted_at` | ~4 |
| أعمدة tenant | `tenantId` | ~3 |

**الباقي (~80 حالة)** — في `wipeBusinessDataKeepUsers`، seed، repair routines — تبقى كما هي.

#### حالات الاختبار

```
T1: simulate "duplicate column name" error → runIdempotent يبتلع ولا يرمي

T2: simulate "table already exists" error → runIdempotent يبتلع

T3: simulate generic SQL error (مثلاً "no such table") → runIdempotent يرمي rethrow

T4: regression — التحقق أن migration حرج معيّن يستخدم runIdempotent
    (regex على database_helper.dart)
```

#### معايير القبول
- [ ] T1..T4 تمر.
- [ ] `flutter test test/security/` كله أخضر (no regression).
- [ ] **اختبار upgrade يدوي:** تثبيت v(n-1) → ترقية → فتح. لا أخطاء.
- [ ] **اختبار install نظيف:** v(n) على جهاز جديد. لا أخطاء.

#### Rollback ⚠️ (الأخطر بين الـ PRs)

| السيناريو | الإجراء |
|----------|---------|
| فشل ترقية على نسبة قليلة من الأجهزة | `git revert` + إصدار hotfix |
| فشل ترقية واسع | إصدار patch يجبر `runIdempotent` على ابتلاع كل الأخطاء مؤقتاً + alert للمالكين بسحب snapshot من Supabase |
| تلف بيانات محلية | الجهاز يلتقط snapshot من Supabase (آلية CloudSyncService الحالية تدعم ذلك) |

**قبل النشر:**
- [ ] تشغيل suite kompletna من `test/`.
- [ ] اختبار upgrade من آخر 3 إصدارات production.
- [ ] إرسال beta لـ 10% من الأجهزة لمدة 48h قبل النشر الكامل.

---

### PR-5 — حماية merge لـ `invoice_items` و الأقساط

**الأولوية:** P1.
**التقدير:** 2–3 أيام.
**يعتمد على:** PR-1 (نفس النمط).

#### الهدف
تطبيق نفس نمط PR-1 على `invoice_items`, `installment_plans`, `installments` لإغلاق ثغرة LWW المتبقية في الأقساط والبنود.

#### الملفات
- `lib/services/cloud_sync_service.dart` — `_mergeInvoiceItemsByGlobalId` + merge functions جديدة للأقساط.
- `lib/services/database_helper.dart` — إضافة أعمدة `*Fils` للأقساط (migration).
- `test/security/invoice_items_merge_protection_test.dart` — جديد.
- `test/security/installments_merge_protection_test.dart` — جديد.

#### سياسة الحقول

**`invoice_items`:**
| الفئة | الحقول | السياسة |
|------|--------|---------|
| مجمدة | `price`, `total`, `unitCost`, `quantity` | المحلي يفوز |
| LWW | `productName` (display) | incoming يفوز إذا أحدث |
| Enrichment | `invoiceId`, `productId` | إثراء فقط |

**`installment_plans`:**
| الفئة | الحقول | السياسة |
|------|--------|---------|
| مجمدة | `totalAmount`, `totalAmountFils`, `numberOfInstallments`, `invoiceId` | المحلي يفوز |
| `max()` | `paidAmount`, `paidAmountFils` | `max(local, incoming)` |
| LWW | `customerName`, `customerId` | incoming يفوز |

**`installments`:**
| الفئة | الحقول | السياسة |
|------|--------|---------|
| مجمدة | `amount`, `amountFils`, `dueDate`, `planId` | المحلي يفوز |
| Boolean monotonic | `paid` | `local || incoming` (مرة paid، تبقى paid) |
| Enrichment | `paidDate` | يُملأ لو null |

#### Migration المطلوبة (هنا فقط، ليس في PR-1..3)

```sql
ALTER TABLE installment_plans ADD COLUMN totalAmountFils INTEGER NOT NULL DEFAULT 0;
ALTER TABLE installment_plans ADD COLUMN paidAmountFils  INTEGER NOT NULL DEFAULT 0;
ALTER TABLE installments      ADD COLUMN amountFils      INTEGER NOT NULL DEFAULT 0;
```

+ backfill لـ rows القائمة عبر `_installmentToFils()`.

استخدم `DbMigrationSafety.runIdempotent` (من PR-4).

#### حالات الاختبار (مختصرة — توسَّع أثناء التنفيذ)

```
items:
  T1: local price=1000, incoming price=900 (newer) → 1000
  T2: incoming items لفاتورة isReturned=1 محلياً → respect freeze
  T3: enrichment productId من product_global_id

plans:
  T1: local paidAmountFils=500_000, incoming=0 (newer) → 500_000
  T2: local totalAmountFils=2_000_000, incoming=3_000_000 → 2_000_000 (مجمد)

installments:
  T1: local paid=1, incoming paid=0 (newer) → paid=1 (monotonic)
  T2: local amountFils=250_000, incoming=300_000 → 250_000 (مجمد)
```

#### معايير القبول
- [ ] جميع الاختبارات تمر.
- [ ] لا regression في `test/oil_change_customer_debt_test.dart` ولا في `test/security/invoices_installments_tenant_scope_regression_test.dart`.
- [ ] backfill migration ناجح على جهاز يحوي بيانات قديمة (اختبار يدوي).
- [ ] قسم Caveat (§2.1) ينطبق على `paidAmount` كذلك — يُذكر في كود التعليق.

#### Rollback
- التغييرات في merge: `git revert` كافٍ.
- المigrations الجديدة (`*Fils`): الأعمدة تبقى في DB (غير ضارة). الكود القديم يقرأ الأعمدة القديمة فقط.

---

## 5. ترتيب التنفيذ والاعتمادات

```
Day 1-2:   PR-1  (invoice merge)         ─┐
Day 3:     PR-2  (delete guard)          │  مستقلة عن بعضها
Day 4:     PR-3  (owner audit)           ─┘
Day 5-6:   PR-4  (migration safety)      ← يقدّم runIdempotent
Day 7-10:  PR-5  (items + installments)  ← يستخدم نمط PR-1 + helper PR-4
```

**الاعتمادات الصلبة:**
- PR-5 يعتمد على PR-1 (نمط الحماية).
- PR-5 يستخدم `DbMigrationSafety.runIdempotent` من PR-4 للـ `*Fils` migrations.

**يمكن التوازي:**
- PR-2 و PR-3 يمكن تنفيذهما بالتوازي مع PR-1.

---

## 6. ما تبقى بعد المرحلة 2

هذه الـ PRs **لا تغلق** الفجوات التالية — تحتاج خطة منفصلة:

| الفجوة | المرحلة المقترحة |
|--------|------------------|
| تجميد الفاتورة كاملاً (Immutability) | spec `invoice_immutability_v1.md` |
| `debt_ledger` كنظام دفتر مستقل | spec `debt_ledger_v1.md` |
| إعادة جدولة الأقساط بعد المرتجع | spec `installment_rebalance_v1.md` |
| ESC/POS thermal | spec `escpos_thermal_v1.md` |
| margin queries → fils | tactical PR منفصل (Medium) |
| باقي catch صامتة (~80) | يُنظر بعد PR-4 |

---

## 7. مخرجات النجاح

بعد دمج PRs 1..5:

| المؤشر | قبل | بعد |
|--------|------|------|
| فقدان تسديد بسبب LWW | ممكن | غير ممكن (max protection) |
| فقدان دفعة على فاتورة عبر sync | ممكن | محصور في derived column فقط |
| حذف عميل يخلّف ديوناً يتيمة | ممكن | غير ممكن |
| استثناء مالك بلا أثر دائم | حقيقي | يُسجَّل دائماً |
| فشل migration مالي بصمت | ممكن | يُكتشف فوراً (rethrow) |
| تقارير الأقساط بدقة fils | لا | نعم |

---

## 8. مراجع

- `docs/specs/system_risk_analysis_full_2026-06-02.md` — التقرير الذي حرّك هذه الخطة.
- `lib/services/cloud_sync_service.dart`:
  - `_mergeCashLedgerByGlobalId` — النمط المرجعي لـ immutable merge.
  - `_mergePartyMasterByGlobalId` — نمط `_partyBalanceProtectedCols`.
  - `_mergeProductsByGlobalId` — نمط `_productStockProtectedCols`.
- `lib/owner/services/business_audit_log_service.dart` — خدمة audit المستخدمة في PR-3.
- `.cursor/skills/erp-logic-performance/SKILL.md` — قواعد المال والأداء.
- `.cursor/skills/offline-sync-supabase/SKILL.md` — قواعد المزامنة.
