# إعادة هيكلة واجهة لوحة المالك — Spec v1.0 (مدمج)

**الحالة:** معتمد للتنفيذ — **لم يبدأ التنفيذ بعد**  
**الشاشة:** `OwnerDashboardScreen` / `OwnerCommandCenterScreen`  
**المراجع المدمجة:**

| الوثيقة | الدور |
|---------|--------|
| [`owner_command_center_v1.md`](owner_command_center_v1.md) **v1.1.2** | معمارية البيانات: `OwnerSectionResult`، TTL §5، Offline §6، استقلال Audit Panel |
| [`owner_dashboard_v4_mobile_sync_ux.md`](owner_dashboard_v4_mobile_sync_ux.md) **v1.1** | ثقة المزامنة، تجاوب الموبايل، Theme |
| [`owner_role_dashboard_master_plan.md`](owner_role_dashboard_master_plan.md) | المراحل 1–3 (منجزة) + Phase 4 مشروطة |

> **Audit Panel (لوحة التعديلات الحساسة):** لا يستخدم نظام TTL المذكور في v1.1.2 §5، ولا يتأثر بتغيير الفترة الزمنية في Header (`OwnerDateRange` / `selectedPeriod`)، وهو مكوّن مستقل معمارياً بالكامل. لا تربطه بـ cache invalidation الخاص ببطاقات KPI.

---

## 1. الهدف الرئيسي

بناء **معمارية قوية** تتعامل مع حالات الفراغ (Empty) والأخطاء (Error) والـ Offline بفعالية **قبل** أي تحسينات بصرية أو حركات — لضمان استقرار التطبيق على **Windows / macOS / Android**.

**ليست إعادة بناء من الصفر.** المعمارية الأساسية موجودة (~70%)؛ هذه الخطة توحّد الفجوات وتُرتّب Sprintات التنفيذ.

---

## 2. خط الأساس في الكود (Baseline — لا تُعاد)

| المكوّن | الملفات | الحالة |
|---------|---------|--------|
| `OwnerSectionResult<T>` + Provider | `owner_section_result.dart`, `owner_command_center_provider.dart` | ✅ موجود — يحتاج توسيع v1.1.2 |
| TTL per-section | `owner_section_ttl.dart` | ✅ موجود — قيم جزئياً قديمة |
| فشل جزئي + Retry | `OwnerPartialStatusBanner`, `OwnerSectionError` | ✅ موجود |
| Charts (Bar + Donut) | `owner_dashboard_analytics_panel.dart` | ✅ موجود |
| Live Activity | `owner_staff_activity_panel.dart`, `openShifts` | ✅ موجود |
| Audit + cursor pagination | `owner_sensitive_actions_panel.dart` | ✅ موجود — polish + offline banner |
| Skeleton (جزئي) | `owner_kpi_card_skeleton.dart` | ⚠️ غير موحّد على كل البطاقات |
| Sync Header | `lastSyncAt`, زر sync, `_SyncTrustBanner` | ⚠️ جزئي — ينقص مؤشر Online/Offline/Syncing |
| Theme toggle | Header | ✅ موجود |
| تخصيص البطاقات | `owner_dashboard_layout_sheet.dart` | ✅ جزئي — v2.0 drag-drop كامل |

---

## 3. معمارية عرض البيانات (Data State Architecture)

### 3.1 النمط الإلزامي

كل بطاقة KPI / مخطط / قسم live يستخدم `OwnerSectionResult<T>` مع **أربع حالات عرض** (ليس ثلاثاً فقط):

| الحالة | متى | UI |
|--------|-----|-----|
| **Loading** | أول جلب فقط (`!hasData`) أو بيانات أقدم من **3× TTL** | Skeleton pulse — **لا** spinner في منتصف البطاقة |
| **Success** | `data != null` + fresh | القيمة + Trend ⬆️⬇️ إن وُجد |
| **Success + stale/offline** | `data != null` + (`isOffline` أو `isStale`) | القيمة + «آخر تحديث: منذ X دقيقة» — **لا Skeleton** |
| **Empty** | `data == null` + لا خطأ (لا بيانات في الفترة) | أيقونة خافتة + نص صريح (مثال: «لا مبيعات مسجلة في هذه الفترة») |
| **Error** | `data == null` + `error != null` (خطأ خادم/استعلام) | رسالة + زر «إعادة المحاولة» **للمكوّن فقط** |

**قاعدة:** خطأ قسم واحد **لا ينهار** الشاشة — انظر v1.1.2 §4 و §6.

### 3.2 TTL + Refresh (مرجع v1.1.2 §5)

- عند انتهاء TTL: background refresh **بدون** Skeleton — الرقم القديم يبقى ظاهراً.
- استثناء **3× TTL**: Skeleton من جديد.
- زر التحديث اليدوي + `invalidateAll()` يُبطلان TTL لكل KPI — **ما عدا Audit Panel**.

**ملفات التنفيذ:** `owner_section_ttl.dart`, `owner_command_center_provider.dart` (`loadSection`, `_setSectionLoading`).

### 3.3 Offline (مرجع v1.1.2 §6)

- Offline + cache → عرض + «آخر تحديث» — لا Skeleton، لا error مزعج.
- Offline + لا cache → Empty + retry.
- عودة الاتصال → refresh تلقائي + fade خفيف.
- Audit offline → سجلات SQLite محلية + شريط «عرض السجلات المحلية فقط — غير متصل».

**توسيع النموذج:** `isOffline: bool` على `OwnerSectionResult`؛ `isStale` يُشتق من `fetchedAt` + `3 × TTL`.

---

## 4. لغة التصميم والأداء (Design & Platform Performance)

### 4.1 Glassmorphism — قرار موحّد (v4 + هذه الخطة)

`BackdropFilter` مكلف على Desktop (Windows/macOS) وقد يهبط الإطارات. **القرار المعتمد:**

| المنطقة | Desktop / macOS / Windows | Android / iOS |
|---------|---------------------------|---------------|
| **خلفية الشاشة** | `GlassBackground` — gradient + glow **فقط** (بدون blur) | صورة + overlay (كما اليوم) |
| **Header العائم** | ألوان صلبة شبه شفافة — **لا** `BackdropFilter` | نفس الشيء |
| **بطاقات KPI / Charts / Audit** | `colorScheme.surface` **صلبة** — قراءة تحت الشمس | صلبة |
| **`BackdropFilter` / `GlassSurface`** | **ممنوع** على scroll areas وKPI في لوحة المالك | مسموح لعناصر صغيرة ثابتة فقط إن لزم |

**البدائل المقبولة:** `Opacity` + ألوان صلبة، `ColorFiltered` خفيف، `surface.withValues(alpha: …)`.

**الهدف:** 60fps على جميع المنصات.

### 4.2 مؤشر حالة الاتصال (Connectivity Indicator)

**إلزامي في Header** — يكمّل (لا يستبدل) `lastSyncAt` وزر المزامنة:

| الحالة | العرض |
|--------|--------|
| **Online** | أيقونة + لون طبيعي (أخضر/neutral) |
| **Offline** | أيقونة + **برتقالي** |
| **Syncing** | أيقونة دوارة أثناء `hydrateCloudAccountData` / pull |

**مصادر:** `LicenseStatus.offline`, `CloudSyncService` sync state, `_isSyncing` في الشاشة.

---

## 5. هيكلة المكونات (Component Breakdown)

### 5.1 [COMPONENT] Header & Controls

- إشعارات (إن مفعّلة).
- زر **تحديث يدوي** KPI (`refreshAll(force: true)`) — لا يمس Audit TTL.
- زر **مزامنة سحابية** (`hydrateCloudAccountData` / `syncNow`) — Sprint v4-A.
- **Date Range Picker** (`OwnerDateRangeBar`) — invalidates KPI فقط.
- **مؤشر Connectivity** (§4.2).
- Theme toggle + تخصيص اللوحة + قائمة الحساب.

### 5.2 [COMPONENT] بطاقات KPI

- الحالات الإلزامية §3.1 لكل بطاقة.
- `OwnerKpiCardSkeleton` موحّد — **استبدال** `CircularProgressIndicator` في `OwnerKpiCard`.
- Trend: `OwnerKpiTrendLine` حيث يُعرّف في الكatalog.
- Semantics على كل بطاقة (v1.1 §9.5).

### 5.3 [COMPONENT] Charts Area

- **Bar Chart (7 أيام):** حواف دائرية؛ empty state صريح؛ تفاعل touch/tablet.
- **Donut (توزيع الإيراد):** legend تفاعلي؛ empty «لا توزيع كافٍ».
- TTL: 10 دقائق (v1.1.2 §5) — مرتبط بـ `salesSparkline` / analytics panel.
- **Morphing animations** → Sprint S5c فقط (ليس S5b).

### 5.4 [COMPONENT] Live Activity

- **موظفون نشطون:** avatars + pulse dot للورديات المفتوحة (`openShifts`, TTL 30ث).
- **نواقص المخزون:** warning glow عند كثرة النواقص → S5c.
- **Sparkline:** mini chart في بطاقة المبيعات — TTL 10 د.

### 5.5 [COMPONENT] Audit Panel

**وظيفياً جاهز** — التركيز على polish + سلوك v1.1.2:

- تصنيف بصري: حدث عادي / حساس.
- فلترة سريعة بالأيقونات (S5b polish).
- cursor pagination (`afterId`) — **موجود** — لا OFFSET.
- **fresh عند كل فتح** — لا TTL، لا invalidation مع date range.
- offline banner في أعلى اللوج.

---

## 6. خارطة Sprintات موحّدة (Execution Roadmap)

> **ترتيب إلزامي:** S4.5 قبل S5a — إصلاح سلوك البيانات قبل توحيد UI.

### S4.5 — بيانات وثقة (v1.1.2) — **الأولوية القصوى**

| مهمة | ملفات | مرجع |
|------|-------|------|
| تصحيح TTL (5/10/15 د…) | `owner_section_ttl.dart` | v1.1.2 §5 |
| `isVeryStale()` (3× TTL) | `owner_section_ttl.dart` | v1.1.2 §5 |
| Background refresh بدون skeleton | `owner_command_center_provider.dart` | v1.1.2 §5 |
| `isOffline` + `isStale` مشتق | `owner_section_result.dart` | v1.1.2 §6 |
| مؤشر Connectivity Header | `owner_dashboard_screen.dart` | §4.2 |
| Audit: offline banner + no TTL coupling | `owner_sensitive_actions_panel.dart` | v1.1.2 §6 ④ |

**اختبارات:** `owner_section_ttl_test.dart`, `owner_command_center_provider_test.dart`.

---

### S5a — توحيد الحالات (ليس بناءً جديداً)

| مهمة | ملاحظة |
|------|--------|
| Skeleton pulse موحّد لكل KPI | استبدال spinner في `OwnerKpiCard` |
| Empty states صريحة per-card / per-chart | نصوص عربية حسب الفترة |
| منطق عرض v1.1.2 §6 في widgets | «آخر تحديث»، Empty offline، Error+retry |
| `OwnerPartialStatusBanner` | مراجعة فقط — موجود |

**معيار القبول:** كل بطاقة تمر بـ loading → success / empty / error / stale-offline بدون crash جزئي.

---

### S5b — Charts + Live (polish + ربط)

| مهمة | ملاحظة |
|------|--------|
| Bar + Donut empty states | polish |
| Legend تفاعلي Donut | polish |
| Live avatars + pulse | `OwnerStaffActivityPanel` |
| Audit: تصنيف بصري + فلتر أيقونات | polish |

**الربط بالبيانات موجود** — لا Provider جديد.

**يتداخل مع v4 Sprint B:** Grid ديناميكي، إزالة `width > 850`، ارتفاعات مرنة.

---

### S5c — الجماليات والأداء

| مهمة | ملاحظة |
|------|--------|
| `AnimatedSwitcher` / `TweenAnimationBuilder` للأرقام | micro-animation |
| Morphing charts عند تغيير الفترة | بعد استقرار S4.5 |
| Warning glow نواقص المخزون | اختياري |
| اختبار 60fps Desktop — **لا BackdropFilter** على scroll | §4.1 |

**يتداخل مع v4 Sprint C:** Theme `colorScheme` في KPI cards، fade عند refresh.

---

### v4 Sprint A — ثقة المزامنة (بالتوازي أو بعد S4.5)

| مهمة | حالة |
|------|------|
| زر sync + `lastSyncAt` | ✅ جزئي |
| Banner «جارٍ المزامنة…» | ✅ `_SyncTrustBanner` |
| Pull-to-refresh → hydrate + refreshAll | تحقق |
| Integration test `remoteImportGeneration` | `test/owner/` |

---

### v2.0 — مستقبلي (خارج S5)

- Drag-drop إعادة ترتيب البطاقات (توسيع `OwnerDashboardLayoutProvider`).
- تصدير PDF تقارير من اللوحة.
- مرجع: v1.1 §8.6 — **لا يُنفَّذ قبل استقرار S4.5–S5c**.

---

## 7. جدول مطابقة Sprintات

| Sprint هذه الوثيقة | v1.1.2 | v4 UX | v1.1 §13 |
|-------------------|--------|-------|----------|
| **S4.5** | §5 + §6 | Sprint A (جزئي) | — |
| **S5a** | §4 + §6 UI | — | S2 polish |
| **S5b** | Charts TTL | Sprint B | S5 polish |
| **S5c** | — | Sprint C | — |
| **v2.0** | §8.6 | — | S7 |

---

## 8. خطة التحقق (Verification)

1. **TTL:** section طازج لا يُعاد fetch؛ بعد TTL → background بدون skeleton؛ بعد 3× TTL → skeleton.
2. **Offline:** cache + «آخر تحديث»؛ no cache + empty + retry؛ Audit محلي فقط.
3. **Partial failure:** قسم واحد error — الباقي success.
4. **Audit:** تغيير date range **لا** يعيد تحميل Audit؛ فتح اللوحة → fresh fetch.
5. **Desktop perf:** scroll سلس بدون `BackdropFilter` على KPI grid.
6. **E2E جهازين:** v4 Verification §1.
7. **RTL + 3 مقاسات:** phone / tablet / desktop.

---

## 9. هيكل ملفات (تعديلات متوقعة — عند التنفيذ)

```
lib/owner/
  models/owner_section_result.dart      ← isOffline, isStale مشتق
  models/owner_section_ttl.dart         ← قيم v1.1.2 + isVeryStale()
  providers/owner_command_center_provider.dart  ← background refresh
  widgets/owner_kpi_card.dart           ← skeleton + empty
  widgets/owner_kpi_card_skeleton.dart  ← pulse animation (S5a)
  widgets/charts/owner_dashboard_analytics_panel.dart
  widgets/owner_sensitive_actions_panel.dart
lib/screens/owner/owner_dashboard_screen.dart   ← connectivity indicator

test/owner/
  owner_section_ttl_test.dart
  owner_command_center_provider_test.dart
  owner_kpi_card_test.dart
```

---

## 10. سجل الإصدارات

| إصدار | تاريخ | ملاحظات |
|-------|-------|---------|
| **v1.0** | 2026-06-02 | دمج: خطة إعادة الهيكلة + v1.1.2 + v4 + baseline الكود — **معتمد، لم يُنفَّذ** |

---

*عند بدء التنفيذ: ابدأ دائماً من **S4.5** — لا S5a قبل إصلاح `loadSection` + TTL.*
