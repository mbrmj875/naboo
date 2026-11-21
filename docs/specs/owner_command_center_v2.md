# مركز قيادة صاحب العمل — Spec v2.0

**الحالة:** منفّذ (فوق v1.1.1)  
**المرجع:** `owner_command_center_v1.md` · `owner_role_dashboard_master_plan.md`  
**الشاشة:** `lib/screens/owner/owner_dashboard_screen.dart`

---

## 1. الهدف

إكمال ما كان مؤجّلاً في v1:

| ميزة v2 | الحالة |
|---------|--------|
| نطاق تاريخ **مخصص** (من–إلى) | ✅ |
| تخصيص اللوحة: ترتيب + إخفاء بطاقات KPI | ✅ |
| مفاتيح `SharedPreferences` **per tenant** | ✅ |
| Drag & Drop في ورقة تخصيص | ✅ |
| `warehouse_id` في audit | ⏳ v2.1 (migration اختياري) |

---

## 2. نطاق التاريخ المخصص

### 2.1 النموذج

```dart
enum OwnerDateRangeKind { today, thisWeek, thisMonth, custom }

class OwnerDateRange {
  factory OwnerDateRange.custom(DateTime start, DateTime end);
  // customStart / customEnd — أيام تقويم محلية
}
```

### 2.2 UI

- `OwnerDateRangeBar`: شرائح اليوم / الأسبوع / الشهر + شريحة **«مخصص»** تفتح `showDateRangePicker` (`locale: ar_SA`).
- عند اختيار فترة مخصصة تُعرض على الشريحة بصيغة `d/m — d/m`.

### 2.3 Provider

- `setDateRange` يقارن النطاق كاملاً (`==`) — تغيير تواريخ مخصصة يُطلق `refreshAll(force: true)`.
- الأقسام المتأثرة: `sales`, `salesSparkline` (نفس v1).
- `openShifts`, `cash`, `inventory*` **لا** تتأثر بفلتر التاريخ (قراءة لحظية / مخزون).

### 2.4 الاختبارات

- `test/owner/owner_date_range_test.dart`
- `owner_command_center_provider_test.dart` — `setDateRange custom`

---

## 3. تخصيص اللوحة

### 3.1 Provider

**ملف:** `lib/owner/providers/owner_dashboard_layout_provider.dart`

| مسؤولية | تفاصيل |
|---------|--------|
| ترتيب البطاقات | `_order` — قائمة معرفات |
| إظهار/إخفاء | `_visible` — Map |
| حفظ | `SharedPreferences` |
| Feature Gate | `syncWithFeatures` — يدمج البطاقات المسموحة فقط |
| حماية | لا يُخفى آخر بطاقة ظاهرة |

**معرفات البطاقات:**

- أقسام KPI من `OwnerSectionIds` (ما عدا `staffUsers`, `salesSparkline`)
- `quickActions` — اختصارات التقارير / المستخدمين
- **sparkline** يتبع بطاقة `sales` تلقائياً (غير قابل للترتيب منفرداً)

**ثابت خارج التخصيص (ثابت في أعلى العمود):**

- `OwnerDateRangeBar`
- `_StaffFilterCard`

### 3.2 مفاتيح per tenant

```
owner_dashboard_card_order_v2_t{tenantId}
owner_dashboard_card_visible_v2_t{tenantId}
```

- `tenantId` من `TenantContextService.activeTenantId`.
- `ChangeNotifierProxyProvider<TenantContextService, OwnerDashboardLayoutProvider>` في `main.dart`.
- `bindTenant(int)` — يفرغ الذاكرة ويعيد `_hydrateFromDisk()` عند تبديل المستأجر.

### 3.3 UI

**ملف:** `lib/owner/widgets/owner_dashboard_layout_sheet.dart`

- زر **تخصيص اللوحة** (`Icons.tune`) في رأس `OwnerDashboardScreen`.
- `ReorderableListView` + `SwitchListTile` لكل بطاقة.
- **إعادة الافتراضي** — ترتيب Feature Gate + كل البطاقات ظاهرة.

### 3.4 الاختبارات

- `test/owner/owner_dashboard_layout_provider_test.dart`
- (مستقبلي) widget test للورقة

---

## 4. خريطة الشاشة (كما في الواجهة)

```
┌─────────────────────────────────────────────────────────────┐
│  [← دخول الموظفين]                    [تخصiص ⚙]  mohamed   │
├──────────────────────────┬──────────────────────────────────┤
│  KPI (يمين / عمود)       │  نشاط + تدقيق (يسار / desktop)   │
│  · فلتر تاريخ            │  · DashboardRecentActivity       │
│  · فلتر موظف             │  · OwnerSensitiveActionsPanel    │
│  · بطاقات KPI مرتّبة     │                                  │
│  · اختصارات سريعة        │                                  │
└──────────────────────────┴──────────────────────────────────┘
```

| منطقة | مصدر الكود | v1 / v2 |
|-------|------------|---------|
| فلتر التاريخ | `OwnerDateRangeBar` | v1 presets + **v2 مخصص** |
| فلتر الموظف | `_StaffFilterCard` | v1 |
| مبيعات / sparkline | `OwnerKpiCard` + `_SalesSparklineCard` | v1 |
| ورديات مفتوحة | `_OpenShiftsCard` | v1 |
| ديون / أقساط / مخزون / صندوق | `OwnerKpiCard` | v1 + Feature Gate |
| PDF نواقص / واتساب ديون | trailing على البطاقات | v1 |
| اختصارات | `_QuickActions` | v1 — **v2 قابل للترتيب/الإخفاء** |
| آخر النشاطات | `DashboardRecentActivity` | موجود مسبقاً — **إصلاح وقت v2.0.1** |
| تعديلات حساسة | `OwnerSensitiveActionsPanel` | v1 S5/S6 |
| بانر offline / partial | `_OfflineBanner`, `OwnerPartialStatusBanner` | v1 |

---

## 5. إصلاح وقت «آخر النشاطات» (v2.0.1)

### المشكلة

- SQLite يخزّن ISO UTC (`…T06:26:00.000Z`).
- `RecentActivityEntry.timeLabel` كان يعرض `at.hour` بدون `toLocal()` → فرق 3 ساعات (العراق UTC+3).

### الحل

**ملف:** `lib/utils/activity_timestamp.dart`

```dart
DateTime parseActivityTimestamp(String? raw) => DateTime.tryParse(raw)?.toLocal() ?? DateTime.now();
```

- كل factories في `RecentActivityEntry` تستخدم `parseActivityTimestamp`.
- `timeLabel` يبني «اليوم / أمس / تاريخ» من `at.toLocal()`.
- `_OpenShiftsCard._formatTime` في لوحة المالك يستخدم نفس المساعد.

**اختبار:** `test/recent_activity_timestamp_test.dart`

---

## 6. خارج نطاق v2.0

- Riverpod / go_router
- POS للمالك
- multi-org
- warehouse_id في audit (v2.1)
- قراءة `security_audit_logs` من Supabase في UI

---

## 7. علاقة بالإصدارات

| وثيقة | علاقة |
|--------|--------|
| `owner_command_center_v1.md` | الأساس — v2 يوسّع §8.6 و §9.1 |
| `feature_gate_v1.md` | بطاقات KPI المسموحة |
| `home_screen_dynamic_v1.md` | نفس widget النشاط على home |

---

## 8. قائمة تحقق QA

- [ ] شريحة «مخصص» → مبيعات تتغير للفترة المختارة
- [ ] تخصيص اللوحة → إخفاء بطاقة → pull-to-refresh → لا تعود
- [ ] تبديل tenant (إن وُجد) → ترتيب مختلف لكل tenant
- [ ] فتح وردية الآن → «آخر النشاطات» يعرض **وقت محلي** صحيح (مثلاً 09:26 وليس 06:26)
- [ ] آخر بطاقة لا تُخفى عند محاولة إيقاف كل المفاتيح

---

## 9. سجل التغيير

| إصدار | تاريخ | ملاحظة |
|-------|-------|--------|
| v2.0 | 2026-05 | تخصيص + تاريخ مخصص + tenant keys |
| v2.0.1 | 2026-05 | إصلاح timezone النشاطات |
| v3.0 | — | **انظر** `owner_command_center_v3_vertical_profiles.md` |
