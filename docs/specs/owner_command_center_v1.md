# مركز قيادة صاحب العمل — Spec v1.1.2

**الحالة:** معتمد للتنفيذ (توسيع المرحلة 4)  
**المرجع:** `owner_role_dashboard_master_plan.md` (مراحل 1–3 منجزة)  
**المبدأ:** لا تكرار العمل — إعادة استخدام الشاشات + بوابة الميزات + `PermissionService` الحالي  
**سجل الإصدارات:** v1.1 → فشل جزئي + TTL + offline · v1.1.1 → retry policy + audit cursor + mocks + S5 deps · **v1.1.2 → سياسة TTL مُفصّلة + سلوك Offline + استقلال Audit Panel** · **→ UI restructure:** [`owner_dashboard_ui_restructure_v1.md`](owner_dashboard_ui_restructure_v1.md) (S4.5–S5c + v4)

**خطة التنفيذ UI (معتمدة — لم تبدأ):** [`owner_dashboard_ui_restructure_v1.md`](owner_dashboard_ui_restructure_v1.md) — ابدأ من **S4.5** (TTL + Offline + Connectivity) ثم S5a → S5b → S5c.

> **Audit Panel (لوحة التعديلات الحساسة):** لا يستخدم نظام TTL المذكور أدناه، ولا يتأثر بتغيير الفترة الزمنية في Header (`OwnerDateRange` / `selectedPeriod`)، وهو مكوّن مستقل معمارياً بالكامل. لا تربطه بـ cache invalidation الخاص ببطاقات KPI.

---

## 1. الرؤية

تحويل `OwnerDashboardScreen` من **لوحة بيانات** إلى **مركز قيادة (Command Center)**:

- قراءة سريعة (KPI + تنبيهات + اتجاهات)
- فلتر زمني موحّد
- إجراءات ذكية من التنبيهات
- أداء ثابت مع بيانات كبيرة (cache per-section + isolates)
- **فشل جزئي:** بطاقة واحدة لا تُسقط اللوحة
- تدقيق التعديلات الحساسة
- (v2) تخصيص ترتيب البطاقات

---

## 2. القيود التقنية الملزمة (مكدس المشروع)

| مسموح | ممنوع |
|--------|--------|
| `provider` + `ChangeNotifier` | Riverpod / `FutureProvider` / `AsyncValue` (Riverpod) |
| `OwnerSectionResult<T>` (نموذج محلي) | Snapshot monolith يفشل كلياً |
| `int fils`، `tenant_id`، soft delete | `double` للمال، hard delete مالي |
| `compute()` / `Isolate.run()` للتجميع الثقيل | إعادة حساب KPI في كل `build` |
| `ListView.builder` + cursor (`afterId`) | `OFFSET` للبيانات الكبيرة |
| `BusinessFeaturesProvider` قبل الصلاحيات | ميزات مخفية «للعرض» فقط |
| `Semantics` على كل بطاقة KPI | بطاقات بلا وصولية |
| `AppLogger` | `print()` |

---

## 3. المعمارية — طبقات

```
OwnerCommandCenterScreen (UI)
        │
        ▼
OwnerCommandCenterProvider (ChangeNotifier)
  • OwnerDateRange (فلتر زمني)
  • OwnerSectionResult<T> لكل بطاقة (نجاح / خطأ / stale منفصل)
  • refreshSection(id) + refreshAll(force)
        │
        ├── OwnerCommandCenterRepository (cache per-section TTL)
        │         ├── HomeKpiRepository (موجود)
        │         ├── OwnerFinanceRepository
        │         ├── OwnerInventoryRepository
        │         └── OwnerTrendRepository
        │
        ├── OwnerCommandCenterSpec (بطاقات حسب Feature Gate)
        └── BusinessAuditLogService (SQLite + retention 90 يوم)
```

**لا Navigator داخلي جديد للمالك:** البطاقات تفتح الشاشات الموجودة.

---

## 4. نموذج الحالة — فشل جزئي (أهم تحسين v1.1)

### 4.0 `OwnerSectionResult<T>` (بديل AsyncValue — Provider فقط)

```dart
enum OwnerSectionStatus { idle, loading, success, error, stale }

class OwnerSectionResult<T> {
  const OwnerSectionResult({
    required this.status,
    this.data,
    this.errorMessage,
    this.fetchedAt,
  });

  final OwnerSectionStatus status;
  final T? data;
  final String? errorMessage; // عربي، بدون stack trace للمستخدم
  final DateTime? fetchedAt;
}
```

### 4.0.1 Snapshot مجزّأ — لا كتلة واحدة

```dart
class OwnerCommandCenterSnapshot {
  final OwnerSectionResult<SalesKpi> sales;
  final OwnerSectionResult<OpenShiftsKpi> openShifts;
  final OwnerSectionResult<DebtSummary>? debts;       // null = Feature Gate off
  final OwnerSectionResult<InstallmentAlert>? installments;
  final OwnerSectionResult<InventoryAlert>? inventory;
  final OwnerSectionResult<int>? inventoryValueFils;
  final OwnerSectionResult<CashSummary>? cash;
  final OwnerSectionResult<List<int>>? salesSparkline;
}
```

| قاعدة | سلوك |
|--------|------|
| تحميل | `Future.wait` مع `eagerError: false` — كل section في try/catch منفصل |
| خطأ section | البطاقة تعرض «تعذّر التحميل» + زر **إعادة المحاولة** → `refreshSection('debts')` |
| نجاح جزئي | باقي البطاقات تُعرض طبيعياً |
| `stale` | بيانات cache قديمة + شارة «آخر تحديث: …» (offline أو TTL منتهٍ) |

### 4.0.2 حالة الشاشة العامة

```dart
enum CommandCenterScreenStatus { idle, loading, partial, ready, offlineStale }
```

- `partial`: بعض الأقسام `error` والباقي `success`
- `offlineStale`: لا شبكة + عرض cache + `LicenseStatus.offline` أو فشل sync

---

## 5. [POLICY] Cache TTL — قيم مُحددة لكل مكوّن

يجب أن يعرف كل مكوّن TTL الخاص به بشكل صريح، ولا يُترك هذا القرار للتنفيذ العشوائي.

| المكوّن | TTL | معرّف Section (تقريبي) | السبب |
|---------|-----|------------------------|--------|
| مبيعات اليوم (KPI) | 2 دقيقة | `sales` (نطاق اليوم) | تتغير مع كل فاتورة جديدة |
| رصيد الصندوق (KPI) | 2 دقيقة | `cash` | حساس مالياً، يتطلب تحديثاً متكرراً |
| مبيعات الفترة (KPI) | 5 دقائق | `sales` (نطاق الفترة) | مجموع تاريخي، أقل تقلباً |
| مخطط المبيعات – 7 أيام | 10 دقائق | `salesSparkline` | بيانات تاريخية، لا تتغير بسرعة |
| توزيع الإيراد (Donut) | 10 دقائق | analytics panel | نفس السبب |
| قيمة المخزون (KPI) | 15 دقيقة | `inventoryValue` | يتغير فقط عند حركات المخزون |
| نواقص المخزون | 5 دقائق | `inventoryShortages` | تحذيري — يحتاج تحديثاً معقولاً |
| الموظفون النشطون (Live) | 30 ثانية | `openShifts` | يعكس الوردية الحالية — حيوي |
| اتجاه المبيعات (Sparkline) | 10 دقائق | `salesSparkline` | ملخص مرئي، ليس real-time |
| الديون / الأقساط | 5 دقائق | `debts` / `installments` | حركة مالية متوسطة التقلب |
| **Audit Panel** | **لا cache** | *(مستقل)* | يُجلب دائماً fresh عند الفتح — **خارج TTL** |

### قواعد التنفيذ

- عند انتهاء TTL، يُعاد الجلب في الخلفية (background refresh) **دون** إظهار Skeleton مجدداً — يبقى الرقم القديم ظاهراً حتى يصل الجديد.
- **استثناء:** إذا كانت البيانات أقدم من **3×** قيمة TTL (مثلاً مبيعات اليوم عمرها أكثر من 6 دقائق)، يُظهر Skeleton من جديد لأن البيانات قديمة جداً.
- زر **التحديث اليدوي** في Header يُبطل كل TTL فوراً **ما عدا Audit Panel**.
- `refresh(force: true)` و `invalidateAll()` (عند `CloudSyncService.remoteImportGeneration`) يتجاوزان TTL لجميع أقسام KPI.

```dart
bool _isFresh(String sectionId, DateTime? fetchedAt) {
  final ttl = OwnerSectionTtl.forId(sectionId);
  if (fetchedAt == null) return false;
  return DateTime.now().difference(fetchedAt) < ttl;
}

bool _isVeryStale(String sectionId, DateTime? fetchedAt) {
  if (fetchedAt == null) return true;
  final ttl = OwnerSectionTtl.forId(sectionId);
  return DateTime.now().difference(fetchedAt) > ttl * 3;
}
```

**مرجع التنفيذ:** `lib/owner/models/owner_section_ttl.dart` — يُحدَّث ليطابق الجدول أعلاه عند Sprint التطبيق.

---

## 6. [POLICY] سلوك الشاشة عند انقطاع الاتصال (Offline Behavior)

### المبدأ الأساسي

الشاشة **لا تنهار** عند الـ Offline — بل تعرض آخر بيانات موثوقة مع توضيح صريح أنها بيانات مخزنة وليست حية.

### الحالات

**① عند انقطاع الاتصال وتوفر بيانات مخزنة (الحالة الشائعة):**

- تُعرض البيانات المخزنة كما هي.
- يظهر تحت كل بطاقة نص صغير: **«آخر تحديث: منذ X دقيقة»** بلون ثانوي مخفف.
- مؤشر Connectivity في Header يتحول لـ **Offline** (أيقونة + لون برتقالي).
- لا Skeleton، لا رسائل خطأ مزعجة.

**② عند انقطاع الاتصال ولا توجد بيانات مخزنة أصلاً (أول تشغيل بدون نت):**

- تُعرض حالة Empty مع أيقونة ونص: **«لا يمكن جلب البيانات حالياً — تحقق من الاتصال»**
- زر **«إعادة المحاولة»** ظاهر وواضح.
- مؤشر Connectivity في Header: Offline.

**③ عند عودة الاتصال:**

- يُعاد الجلب تلقائياً في الخلفية بدون تدخل المستخدم.
- مؤشر Connectivity يتحول لـ **Syncing** (أيقونة دوارة) ثم إلى **Online** عند اكتمال التحديث.
- البيانات الجديدة تحل محل القديمة بـ fade transition خفيف.

**④ Audit Panel عند الـ Offline:**

- يعرض السجلات **المخزنة محلياً** فقط (`business_audit_events` في SQLite).
- يظهر شريط تنبيه خفيف في أعلى اللوج: **«عرض السجلات المحلية فقط — غير متصل»**
- لا يحاول الجلب من الخادم ولا يُظهر خطأ.

### القاعدة الذهبية — `OwnerSectionResult<T>`

كل قسم KPI (وليس Audit Panel) يحمل:

| حقل | المعنى |
|-----|--------|
| `data: T?` | آخر بيانات ناجحة (`null` إذا لم تُجلب قط) |
| `isStale: bool` | `true` إذا تجاوزت البيانات **3× TTL** (أو `status == stale`) |
| `lastUpdated` / `fetchedAt` | وقت آخر جلب ناجح |
| `error: String?` | `null` في النجاح أو Offline مع cache |
| `isOffline: bool` | لتمييز خطأ الشبكة عن خطأ الخادم |

**منطق العرض في الـ widget:**

```
if (result.data != null && result.isOffline)  → عرض مع «آخر تحديث»
if (result.data != null && result.isStale)    → عرض مع تحذير بصري خفيف
if (result.data == null && result.isOffline)  → Empty + زر retry
if (result.data == null && result.error != null) → Error + زر retry
```

- مصدر offline: فقدان الشبكة (`Connectivity`) و/أو `LicenseStatus.offline`
- pull-to-refresh offline: Snackbar «تعذّر التحديث بدون اتصال» — **لا** مسح cache
- SQLite محلي يعمل دائماً — معظم KPIs قابلة للقراءة offline إن لم تكن stale جداً

**v1.1.2 — حقول مستهدفة (توسيع النموذج الحالي):** إضافة `isOffline` صريح؛ `isStale` يُشتق من `fetchedAt` + `3 × OwnerSectionTtl.forId(sectionId)`.

---

## 7. Optimistic UI للإجراءات السريعة

| إجراء | Optimistic | تأكيد |
|--------|------------|--------|
| تذكير واتساب | علامة ✓ على العميل في القائمة فور فتح الرابط | لا rollback (خارج التطبيق) |
| تسجيل «تم التذكير» (اختياري v1.1) | تحديث عدّاد في البطاقة | `business_audit_events` `debt_reminder_sent` |
| تغيير سعر (من ProductEdit) | — | **لا** optimistic للمال؛ انتظار DB ثم `invalidateSection('inventory')` |
| PDF طلبية | spinner على الزر | عند اكتمال `compute()` |

**قاعدة:** Optimistic **فقط** للإجراءات غير المالية أو التي لا تغيّر أرصدة. تغيير سعر/كمية/دين = انتظار commit + audit log.

---

## 8. المراحل الوظيفية (محتوى)

### 8.1 — مركز القيادة + تنقل (v1)

| البطاقة | يظهر إذا | يفتح |
|---------|----------|------|
| مبيعات الفترة | دائماً | `ReportsScreen` |
| ورديات مفتوحة | دائماً | تفاصيل / `staff_shifts` |
| إجمالي الديون | `debts` | `DebtsScreen` |
| أقساط متأخرة | `installments` | `InstallmentsScreen` |
| نواقص المخزون | `inventory` | `InventoryProductsScreen` |
| قيمة المخزون | `inventory` (اختياري) | تقرير مخزون |
| صندوق / مصروفات | `cash` | `CashScreen` |

### 8.2 — مراقبة مالية

- ملخص مدين/دائن، Top N عملاء، أقساط اليوم/المتأخرة
- مصدر واحد في Repository — أرقام = `DebtsScreen`

### 8.3 — مراقبة مخزون

- نواقص، آخر سندات، حسب مخزن
- تعديل كمية **فقط** عبر سند مخزني

### 8.4 — حوكمة منتجات وأسعار

- `AddProductScreen` / `ProductEditScreen`
- كل تغيير → `BusinessAuditLogService.record(...)`

### 8.5 — تنبيهات + تدقيق + اتجاهات

- شارات على البطاقات
- لوحة «تعديلات حساسة»
- Sparklines (7 أيام مبيعات)

### 8.6 — تخصيص اللوحة → **v2.0 (خارج v1.1)**

- Drag & Drop، إخفاء بطاقات، `SharedPreferences`
- **لا يُنفَّذ في S1–S6** — بعد استقرار البيانات والاختبارات

---

## 9. التحسينات المؤسسية

### 9.1 فلتر زمني شامل

| الخيار | النطاق |
|--------|--------|
| اليوم | `startOfDay` → الآن |
| هذا الأسبوع | تقويم `ar_SA` |
| هذا الشهر | أول الشهر → الآن |

- يُ invalidates: `sales`, `salesSparkline`, نشاطات زمنية — **لا** `openShifts` — **لا Audit Panel**

### 9.2 إجراءات ذكية

| التنبيه | إجراء | تفاصيل |
|---------|--------|--------|
| N صنف ناقص | PDF طلبية | `compute()`, ≤100 صنف < 3s |
| ديون متأخرة | واتساب | قالب عربي، `customer_phone_launch` |
| قسط اليوم | قائمة تحصيل | `InstallmentsScreen` |

### 9.3 Sparklines

- `CustomPainter` بدون dependency جديدة إن أمكن
- يُحمَّل مع section `salesSparkline` — استعلام مجمّع 7 أيام
- **Performance budget:** رسم < 16ms/frame

### 9.4 سجل التدقيق `business_audit_events`

**جدول SQLite (migration v1):**

| عمود | نوع |
|------|-----|
| id | INTEGER PK |
| tenant_id | INTEGER NOT NULL |
| user_id | INTEGER |
| username | TEXT |
| event_type | TEXT |
| entity_type | TEXT |
| entity_id | TEXT |
| warehouse_id | INTEGER NULL *(migration v2 إن لزم)* |
| old_value_json | TEXT |
| new_value_json | TEXT |
| created_at | TEXT ISO NOT NULL |

**Retention (إلزامي):**

```dart
// عند startup أو مرة/يوم — business_audit_log_service.dart
await db.delete(
  'business_audit_events',
  where: 'tenant_id = ? AND created_at < ?',
  whereArgs: [tenantId, ninetyDaysAgo.toIso8601String()],
);
```

**عرض في اللوحة:**

- أول صفحة: آخر 20 حدثاً
- «عرض المزيد»: `ListView.builder` + cursor `afterId` — **لا OFFSET**

### 9.5 Accessibility

كل `OwnerKpiCard`:

```dart
Semantics(
  label: 'مبيعات اليوم: ${IraqiCurrencyFormat.formatIqd(...)}',
  button: onTap != null,
  child: OwnerKpiCard(...),
)
```

- أزرار الإجراءات: `tooltip` + `Semantics(label: 'إعادة المحاولة')`
- Sparkline: `Semantics(label: 'اتجاه المبيعات آخر 7 أيام', excludeSemantics: true)` على الرسم فقط

---

## 10. خطة Migration لقاعدة البيانات

```dart
// database_helper.dart — migration N+1
await db.execute('''
  CREATE TABLE IF NOT EXISTS business_audit_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tenant_id INTEGER NOT NULL,
    user_id INTEGER,
    username TEXT,
    event_type TEXT NOT NULL,
    entity_type TEXT,
    entity_id TEXT,
    warehouse_id INTEGER,
    old_value_json TEXT,
    new_value_json TEXT,
    created_at TEXT NOT NULL
  )
''');
await db.execute('''
  CREATE INDEX IF NOT EXISTS idx_bae_tenant_created
  ON business_audit_events(tenant_id, created_at DESC, id DESC)
''');
```

**v2 (مستقبلي):** `ALTER TABLE ... ADD COLUMN warehouse_id` إذا أُضيف العمود بعد v1 بدون warehouse.

---

## 11. استراتيجية الاختبار

```
test/owner/
  owner_section_result_test.dart           ← unit: OwnerSectionResult merge
  owner_command_center_provider_test.dart  ← unit: partial failure, TTL, stale
  owner_section_ttl_test.dart              ← unit: per-section freshness
  owner_kpi_card_test.dart                 ← widget: error state, Semantics
  owner_command_center_screen_test.dart    ← integration: partial load mock
  business_audit_retention_test.dart       ← unit: 90-day prune
```

| نوع | ما يُختبر |
|-----|-----------|
| Unit | section يفشل منفرداً؛ الباقي success |
| Unit | TTL: section طازج لا يُعاد fetch |
| Unit | retention يحذف > 90 يوم فقط لـ tenant |
| Widget | بطاقة error + زر إعادة |
| Widget | Semantics label يحتوي القيمة |
| Integration | Feature Gate: لا استعلام debts عند off |

**Mock:** `test/mocks/owner_mock_repositories.dart` — انظر §21.

---

## 12. Performance Budget

| مقياس | هدف |
|--------|-----|
| Cold start — أول إطار (cache دافئ) | < 300ms |
| Cold start — بدون cache (skeleton) | < 800ms |
| Pull-to-refresh (parallel sections) | < 2s على شبكة 3G محاكاة |
| Sparkline paint | < 16ms/frame |
| PDF نواقص (100 صنف) | < 3s في `compute()` |
| `inventoryValue` aggregate | UI thread = 0ms (isolate فقط) |
| Audit list page (cursor) | < 100ms لـ 20 صف |

---

## 13. ترتيب التنفيذ (v1.1)

| Sprint | محتوى | يعتمد على |
|--------|--------|-----------|
| **S1** | `OwnerSectionResult` + Provider + per-section TTL + partial refresh | — |
| **S2** | بطاقات KPI + Feature Gate + أخطاء per-card + Semantics | S1 |
| **S3** | فلتر زمني + offline stale UI | S1 |
| **S4** | Actionable (PDF، واتساب) + optimistic حيث مسموح | S2 |
| **S5** | Sparklines + `OwnerTrendRepository` | S1 |
| **S5a†** | migration + `BusinessAuditLogService` + retention + tests | — |
| **S5b†** | audit hooks في `ProductRepository` (+ stock/debt) | S5a† |
| **S6** | لوحة تعديلات حساسة + cursor pagination | S5a† |
| **S7** | ~~Drag & Drop~~ → **v2.0** | — |

> **†** S5a/S5b هنا = **audit backend** (v1.1 الأصلي). لا تخلط مع **S5a/S5b UI** في [`owner_dashboard_ui_restructure_v1.md`](owner_dashboard_ui_restructure_v1.md).

### 13.1 المرحلة التالية — UI + بيانات (v1.1.2 + restructure)

| Sprint UI | محتوى | مرجع |
|-----------|--------|------|
| **S4.5** | TTL v1.1.2 + `isVeryStale` + background refresh + `isOffline` + Connectivity Header | v1.1.2 §5–§6 |
| **S5a UI** | Skeleton موحّد + Empty/Error per-component | restructure §3 |
| **S5b UI** | Charts/Live/Audit polish | restructure §5 |
| **S5c UI** | Animations + 60fps glass policy | restructure §4 |

**الوثيقة الكاملة:** [`owner_dashboard_ui_restructure_v1.md`](owner_dashboard_ui_restructure_v1.md)

---

## 14. هيكل ملفات

```
lib/owner/
  specs/owner_command_center_spec.dart
  models/owner_date_range.dart
  models/owner_section_result.dart
  models/owner_section_ttl.dart
  models/owner_command_center_snapshot.dart
  owner_command_center_repository.dart
  owner_finance_repository.dart
  owner_inventory_repository.dart
  owner_trend_repository.dart
  providers/owner_command_center_provider.dart
  services/business_audit_log_service.dart
  widgets/owner_date_range_bar.dart
  widgets/owner_kpi_card.dart
  widgets/owner_section_error.dart
  widgets/owner_stale_badge.dart
  widgets/owner_sparkline.dart
  widgets/owner_alert_tile.dart
  widgets/owner_sensitive_actions_panel.dart
  screens/owner_command_center_screen.dart

test/owner/   ← انظر §11
```

---

## 15. معايير قبول (v1.1)

### فشل جزئي

- [ ] فشل استعلام الديون لا يخفي بطاقة المبيعات
- [ ] كل بطاقة error لها «إعادة المحاولة» تعمل
- [ ] `partial` status عند mix success/error

### Cache / Offline

- [ ] `openShifts` TTL 30s؛ `inventoryValue` TTL 10m
- [ ] offline + cache: عرض stale + «آخر تحديث»
- [ ] offline بدون cache: رسالة واضحة لا شاشة حمراء

### أداء

- [ ] Performance budget §12 — regression test أو manual checklist

### تدقيق

- [ ] retention 90 يوم يعمل على startup
- [ ] pagination audit: cursor فقط، لا OFFSET
- [ ] تعديل سعر → حدث في اللوحة ≤ 5s

### Feature Gate

- [ ] بطاقة معطّلة = لا استعلام + لا section في snapshot

### Accessibility

- [ ] `Semantics` على كل بطاقة KPI — اختبار widget

### اختبارات

- [ ] `test/owner/owner_command_center_provider_test.dart` — partial failure PASS

---

## 16. أولوية `oil_change`

1. نواقص + PDF  
2. ديون (بدون أقساط افتراضياً)  
3. مبيعات + sparkline  
4. ورديات / نشاط  
5. حوكمة منتجات  

---

## 17. خارج النطاق v1.1

- Drag & Drop تخصيص (**v2**)  
- Riverpod / dio / go_router  
- POS للمالك  
- multi-org  
- Optimistic لتغييرات مالية  
- قراءة `security_audit_logs` من Supabase في UI  

---

## 18. العلاقة بالوثائق

| وثيقة | علاقة |
|--------|--------|
| `owner_role_dashboard_master_plan.md` | مراحل 1–3 منجزة |
| `feature_gate_v1.md` | بطاقات |
| `home_screen_dynamic_v1.md` | موظف vs مالك |

**v3.0:** `owner_command_center_v3_vertical_profiles.md` — Vertical Profiles + Hero + catalog + عقود KPI — **معتمد للتنفيذ** (يبدأ `oil_change`).

---

## 19. سياسة إعادة المحاولة (Retry Policy) — v1.1.1

| الإجراء | السلوك | ملاحظة |
|---------|--------|--------|
| **Pull-to-refresh** | `refreshAll(force: true)` — **يُعيد جلب كل الأقسام المفعّلة** (Feature Gate) بالتوازي | موثّق وثابت — لا surprises |
| **زر «إعادة المحاولة» على بطاقة** | `refreshSection(sectionId)` — **قسم واحد فقط** | لا يمس الأقسام الناجحة |
| **تغيير فلتر زمني** | `refreshAll(force: true)` للأقسام الزمنية + `openShifts` منفصل إن لزم | |
| **بعد `CloudSyncService` import** | `invalidateAll()` ثم `refreshAll(force: true)` في post-frame | |
| **فشل section أثناء `refreshAll`** | الأقسام الأخرى تبقى `success`؛ الفاشل → `error` | لا rollback للنجاح |

```dart
// owner_command_center_provider.dart — عقد واضح
Future<void> refreshAll({required bool force}) async {
  await Future.wait(
    _enabledSectionIds.map((id) => _loadSection(id, force: force)),
    eagerError: false,
  );
  notifyListeners();
}

Future<void> refreshSection(String sectionId, {bool force = true}) async {
  await _loadSection(sectionId, force: force);
  notifyListeners();
}
```

---

## 20. Pagination التدقيق — cursor `id` (ليس `created_at`)

**القرار:** cursor = **`id` (INTEGER PK)** — أستقر من `created_at` عند إدخالات متزامنة.

**ترتيب العرض:** `ORDER BY created_at DESC, id DESC`

**الصفحة الأولى (لوحة):**

```sql
SELECT ... FROM business_audit_events
WHERE tenant_id = ? AND deleted_at IS NULL  -- إن وُجد soft delete لاحقاً
ORDER BY created_at DESC, id DESC
LIMIT 20
```

**الصفحة التالية:**

```sql
WHERE tenant_id = ? AND id < ?   -- afterId من آخر صف
ORDER BY created_at DESC, id DESC
LIMIT 20
```

- **ممنوع:** `OFFSET`
- **واجهة:** `loadAuditPage({int? afterId, int limit = 20})`

---

## 21. Mocks للاختبار — ملكية مشتركة

```
test/mocks/
  owner_mock_repositories.dart    ← FakeOwnerFinanceRepository, FakeInventory, …
  owner_command_center_fixtures.dart  ← snapshot جاهز success/partial/error

test/owner/
  owner_command_center_provider_test.dart  ← يستورد من test/mocks/
  ...
```

| قاعدة | تفاصيل |
|--------|--------|
| ملكية | **ملف مشترك واحد** — لا تكرار fake لكل test |
| DB | unit tests للـ Provider: mocks فقط؛ integration: `InMemoryFinancialDb` (`test/helpers/in_memory_db.dart`) |
| regression | `phase3_owner_dashboard_mvp_regression_test.dart` يبقى؛ اختبارات owner جديدة في `test/owner/` |

---

## 22. تبعيات خارجية — Sprint S5 / S6

| التبعية | الحالة الحالية | تأثير على S5 |
|---------|----------------|--------------|
| `ProductEditScreen` | **موجودة** — `_save()` → `ProductRepository.updateProductBasic` | جاهزة **للربط** — لا audit hook بعد |
| `AddProductScreen` | **موجودة** — `insertProductComplete` | جاهزة **للربط** — لا audit hook بعد |
| `BusinessAuditLogService` | **غير موجود** (مخطط v1.1) | **S5a** — يجب قبل hooks |
| migration `business_audit_events` | **غير موجود** | **S5a** — مع الخدمة |
| `financial_audit_log` (Postgres) | موجود على السيرفر (`migrations/20260509_…`) | **منفصل** — لا يُخلط مع SQLite المحلي للمالك |

**ترتيب S5 المُحدَّث:**

```
S5a: migration + BusinessAuditLogService + retention + unit tests
S5b: hooks في ProductRepository (أفضل من الشاشة) — price_change, product_create, soft_delete
S5c: hooks اختيارية في stock voucher / debt adjust
S6:  OwnerSensitiveActionsPanel (يعتمد S5a فقط — لا ينتظر S5b إن وُجدت بيانات seed)
```

> **قرار معماري:** ربط التدقيق عند **`ProductRepository`** / `db_stock` وليس داخل widgets — شاشة واحدة أو API مستقبلي يمر بنفس المسار.

**مخاطر تأخير:** إذا تأخر S5b، S6 يعرض أحداث seed/اختبار + أحداث stock/debt فقط حتى اكتمال ربط المنتجات.

