# جرد ميزات الشاشة الرئيسية (Home Screen Feature Inventory)

> **الملف المرحَّل:** `lib/screens/home_screen.dart`
> **حجم الملف:** 4474 سطرًا — تصنيف: Dashboard (Pilot Migration)
> **حالة الوثيقة:** عقد جرد مُجمّد قبل الترحيل (Frozen Inventory Contract).
> **القاعدة:** **لا يُحذف أي عنصر دون قرار صريح موثق هنا**.

---

## 0. ملخص تنفيذي

| البند | العدد |
|---|---|
| الـ Imports | 88 |
| الـ Providers المستخدمة | 9 |
| الـ Services المستخدمة | 8 |
| الـ Modules الرئيسية | 12 |
| الـ Sub-menu items | 30+ |
| الـ Listeners المُسجَّلة (في initState) | 6 |
| الـ Permission Keys المفحوصة | 11 |
| الـ Lifecycle hooks | 5 (initState, didChangeAppLifecycleState, didChangeDependencies, dispose, build) |
| الـ Deep Link handlers | 2 (Invoice + Barcode) |
| الـ Layout breakpoints الحالية | 2 (800dp) + استخدام `isHandsetForLayout` |
| الـ Routes ضمن Inner Navigator | ~25 |

---

## 1. الـ Providers والـ Services (إلزامية الإبقاء)

### 1.1 Providers (من `package:provider`)

| Provider | الاستخدام | حساسية |
|---|---|---|
| `AuthProvider` | حالة تسجيل الدخول، userId، isAdmin | 🔴 حرج |
| `ShiftProvider` | حالة الوردية المفتوحة، فحص `hasOpenShift`, refresh | 🔴 حرج (مع listener) |
| `ProductProvider` | تحميل المنتجات `loadProducts(seedIfEmpty: false)` | 🟡 مهم |
| `NotificationProvider` | الإشعارات: refresh + badge | 🟡 مهم |
| `ParkedSalesProvider` | الفواتير المعلّقة | 🟡 مهم |
| `SaleDraftProvider` | مسودة البيع، `enqueueProductLine` | 🔴 حرج (تكامل POS) |
| `ThemeProvider` | الوضع الداكن/الفاتح + الـ Consumer في build | 🟡 مهم |
| `GlobalBarcodeRouteBridge` | جسر استقبال الباركود من نطاق التطبيق | 🔴 حرج (attach/detach) |
| `LicenseService` (`context.watch`) | حالة الترخيص، الوضع المقيّد | 🔴 حرج |

### 1.2 Services (Singletons)

| Service | الاستخدام |
|---|---|
| `PermissionService.instance` | فحص صلاحيات المستخدم/الوردية |
| `AppSettingsRepository.instance` | قراءة إعدادات المستأجر (enableDebts, enableInstallments, etc.) |
| `BusinessFeaturesRevision.instance` | listener عند تغيير ميزات الأعمال |
| `CloudSyncService.instance.remoteImportGeneration` | listener لاستيراد لقطة سحابية |
| `MacStyleSettingsPrefs` | إعداد عرض الواجهات بنمط ماك |
| `RestrictedModePolicy` | فحص هل المسار مسموح في الوضع المقيد |
| `DatabaseHelper()` | استعلامات SQLite للبحث |
| `ProductRepository()` | بحث المنتجات للـ Global Search |

> **قاعدة الترحيل:** كل واحد من هذه يجب أن يبقى مستخدمًا بنفس التوقيع بعد الترحيل. **يُمنع** تغيير منطق أي Provider أو Service.

---

## 2. الـ State Variables (الحالة الداخلية)

### 2.1 Controllers & Notifiers

```
TextEditingController _searchController         ← البحث الموحّد
FocusNode _searchFocusNode                       ← تركيز شريط البحث
Timer? _searchDebounce                           ← debounce للبحث
AnimationController _nameAnimController          ← أنيميشن اسم الشركة
ValueNotifier<bool> _isDrawerOpen                ← حالة فتح Sidebar (الكبير)
ValueNotifier<bool> _mobileSearchCollapsed       ← طي شريط البحث في الموبايل
GlobalKey<NavigatorState> _innerNavKey           ← Inner Navigator للشاشات الكبيرة
GlobalKey<NavigatorState> _innerNavKeySmall      ← Inner Navigator للموبايل
```

### 2.2 Flags & Caches

```
bool _showVirtualSearchKeyboard
String _searchQuery
bool _globalSearchLoading
bool _navFilterApplied                           ← هل طُبقت صلاحيات الوردية
bool _barcodeBridgeAttached
double _mobileSearchHideDrag                     ← تتبع سحب البحث في الموبايل
double _mobileSearchShowDrag
ProductRepository _productRepo
DatabaseHelper _dbHelper
List<Map> _hitProducts, _hitCustomers, _hitUsers ← نتائج البحث
List<ModuleItem> _hitModules
ShiftProvider? _shiftProviderForGateListener     ← مرجع محفوظ للـ listener
GlobalBarcodeRouteBridge? _barcodeBridge
List<ModuleItem> _visibleNavModules              ← الوحدات بعد فلترة الصلاحيات
late List<ModuleItem> _orderedModules            ← الترتيب (قابل للحفظ في prefs)
List<QuickAction> _quickActions                  ← الاختصارات (قابلة للتخصيص)
List<BreadcrumbSegment> _breadcrumbTrail         ← مسار فتات الخبز
```

> **قرار الترحيل:** كل هذه الحالات تنتقل كما هي. لا تغيير في التوقيع أو الوظيفة.

---

## 3. الـ Lifecycle Hooks (إلزامية الإبقاء بالكامل)

### 3.1 `initState()` (السطر 729)

أعمال إلزامية تُنفّذ بنفس الترتيب:

```
1. WidgetsBinding.instance.addObserver(this)              ← AppLifecycleState
2. _orderedModules = List.from(_originalModules)          ← منع LateInitializationError
3. _nameAnimController = AnimationController(...)
4. unawaited(_loadHomeDiskPrefsOnce())                    ← قراءة prefs مرة واحدة
5. _searchController.addListener(_onSearchControllerChanged)
6. _searchFocusNode.addListener(_onSearchFocusTick)
7. CloudSyncService.instance.remoteImportGeneration.addListener(_onRemoteSnapshotImported)
8. WidgetsBinding.instance.addPostFrameCallback(...):
   - _shiftProviderForGateListener = context.read<ShiftProvider>()
   - _shiftProviderForGateListener!.addListener(_shiftGateListener)
   - BusinessFeaturesRevision.instance.addListener(_onBusinessFeaturesRevision)
   - unawaited(_ensureActiveShiftGate())
   - Future.delayed(450ms): _refreshHomeAuxProviders()
```

### 3.2 `didChangeAppLifecycleState(state)` (السطر 759)

```dart
if (state == AppLifecycleState.resumed) {
  unawaited(_ensureActiveShiftGate());   // فحص الوردية عند استئناف التطبيق
}
```

### 3.3 `didChangeDependencies()` (السطر 871)

أعمال إلزامية:
```
1. _barcodeBridge ??= context.read<GlobalBarcodeRouteBridge>()
2. لو لم يُسجّل: _barcodeBridge!.attach(_applyScannedCode)
3. takePendingScan() لمعالجة Pending barcodes من initial route
4. فحص hideInAppSearchKeyboard وإخفاء الـ virtual keyboard لو لزم
```

### 3.4 `dispose()` (السطر 903)

ترتيب التنظيف **إلزامي**:
```
1. _barcodeBridge?.detach() (لو متصل)
2. WidgetsBinding.instance.removeObserver(this)
3. _shiftProviderForGateListener?.removeListener(_shiftGateListener)
4. CloudSyncService.instance.remoteImportGeneration.removeListener(...)
5. BusinessFeaturesRevision.instance.removeListener(...)
6. _searchDebounce?.cancel()
7. _nameAnimController.dispose()
8. _searchController.removeListener + dispose
9. _searchFocusNode.removeListener + dispose
10. _isDrawerOpen.dispose()
11. _mobileSearchCollapsed.dispose()
```

> ⚠️ **خطر تسريب الذاكرة**: حذف أي listener من هذه القائمة = memory leak مؤكد. الترحيل يجب أن يحافظ على كل واحد منها.

---

## 4. الـ Modules (وحدات التنقل) — العقد الكامل

### 4.1 الترتيب الافتراضي للـ `_originalModules` (12 وحدة)

> هذا الترتيب قابل للتخصيص من قبل المستخدم ويُحفظ في `SharedPreferences.modules_order`.

| # | العنوان | الأيقونة | اللون | routeId | sub-items |
|---|---|---|---|---|---|
| 1 | الفواتير | `Icons.receipt` | green | `AppContentRoutes.invoices` | 4 (قائمة، بيع جديد، معلّقة، إعدادات نقطة البيع) |
| 2 | العملاء | `Icons.person_outline` | teal | `AppContentRoutes.customers` | 4 (إدارة، إضافة جديد، اتصال، الولاء) |
| 3 | ولاء العملاء | `Icons.card_giftcard_rounded` | deepPurple | `AppContentRoutes.loyaltySettings` | 2 (إعدادات، سجل) |
| 4 | الأقساط | `Icons.calendar_today` | blue | `AppContentRoutes.installments` | 2 (خطط، إعدادات) |
| 5 | الديون | `Icons.balance_outlined` | amber | `AppContentRoutes.debts` | 2 (لوحة، إعدادات) |
| 6 | المخزون | `Icons.inventory_2` | orange | `AppContentRoutes.inventory` | **10** (قائمة، إضافة، تحديث، ملصقات، حركات، مستودعات، جرد، أوامر شراء، تحليلات، إعدادات) |
| 7 | الخدمات والصيانة | `Icons.handyman_rounded` | blueAccent | `AppContentRoutes.servicesHub` | 3 (لوحة، إضافة، تذاكر) |
| 8 | الصندوق | `Icons.account_balance_wallet` | purple | `AppContentRoutes.cash` | بدون sub |
| 9 | المصروفات | `Icons.payments_outlined` | teal | `AppContentRoutes.expenses` | بدون sub |
| 10 | التقارير | `Icons.bar_chart` | red | `AppContentRoutes.reports(0)` | بدون sub |
| 11 | المستخدمين | `Icons.people_alt` | indigo | `AppContentRoutes.users` | 3 (إدارة، ورديات، هويات) |
| 12 | الطباعة | `Icons.print` | blueGrey | `AppContentRoutes.printing` | بدون sub |

### 4.2 ترتيب الـ BottomNav بعد الترحيل (قرار جديد)

> بناءً على دستور الشاشة الرئيسية + إجابات المستخدم.

| موقع | phoneSM (5 slots) | phoneXS (4 slots) |
|---|---|---|
| 1 | الصندوق | الصندوق |
| 2 | الفواتير | الفواتير |
| 3 | المخزون | المخزون |
| 4 | العملاء | المزيد |
| 5 | المزيد | — |

> الباقي (8-9 وحدات) ينتقل تلقائيًا لـ BottomSheet عبر زر “المزيد”.

### 4.3 الـ QuickActions (4 افتراضية)

> الموقع الحالي: شريط أزرق تحت AppBar.
> **القرار المعتمد:** **يُحذف نهائيًا** (نوافق على إجابة المستخدم لسؤال 1).
> **لكن منطقها** (التنقل لـ AddInvoice / Invoices / Installments / Search) **يجب أن يظل متاحًا** من:
> - بطاقات “لمحة المربح” في الـ Dashboard.
> - الـ FAB في الموبايل/التابلت.
> - اختصارات الكيبورد في الديسكتوب (Ctrl+N للبيع).

---

## 5. الـ Permission Guards (فحوصات الصلاحيات)

كل وحدة في الـ Sidebar/BottomNav تخضع لفحص صلاحية. الترحيل **يجب أن يحفظها بنفس التوقيع**.

### 5.1 الـ PermissionKeys المستخدمة

| Module | PermissionKey |
|---|---|
| الفواتير / بيع | `salesPos` |
| العملاء | `customersView` |
| ولاء العملاء | `loyaltyAccess` |
| الأقساط | `installmentsPlans` |
| الديون | `debtsPanel` |
| المخزون | `inventoryView` |
| الصندوق | `cashView` |
| التقارير (`reports/*`) | `reportsAccess` |
| الطباعة | `printingAccess` |
| المستخدمين | `usersView` |
| ورديات الموظفين | `shiftsAccess` |

### 5.2 منطق الفحص (`_recomputeNavModules`)

```dart
PermissionService.instance.canForSession(
  sessionUserId: auth.userId,
  sessionRoleKey: auth.isAdmin ? 'admin' : 'staff',
  activeShift: shiftProv.activeShift,
  permissionKey: key,
)
```

### 5.3 الـ Business Feature Toggles

تُقرأ من `AppSettingsRepository` ويُخفى الوحدة بالكامل إذا = `0`:
- `BusinessSetupKeys.enableDebts`
- `BusinessSetupKeys.enableInstallments`
- `BusinessSetupKeys.enableCustomers`
- `BusinessSetupKeys.enableLoyalty`

### 5.4 الـ Restricted Mode

`RestrictedModePolicy.isRouteAllowed(routeId)` — يُفحص لكل مسار قبل السماح بالتنقل.

> **قرار الترحيل:** كل المنطق ينتقل كما هو إلى `_recomputeNavModules()` بدون تعديل. الـ AdaptiveScaffold لن يعرف عن الصلاحيات — هي تُطبَّق قبل تمرير `destinations`.

---

## 6. الـ Deep Links والـ Listeners الحرجة

### 6.1 GlobalBarcodeRouteBridge

```dart
// في didChangeDependencies:
_barcodeBridge ??= context.read<GlobalBarcodeRouteBridge>();
_barcodeBridge!.attach(_applyScannedCode);
final pending = GlobalBarcodeRouteBridge.takePendingScan();

// في dispose:
_barcodeBridge?.detach();
```

> **حساسية قصوى**: لو لم يُسجَّل الـ attach، أي باركود يُمسح من نطاق التطبيق سيضيع. لو لم يُستدعَ `takePendingScan()`، أي باركود مُمسوح قبل بناء الشاشة سيضيع.

### 6.2 InvoiceDeepLink

```dart
InvoiceDeepLink.parseInvoiceId(deepInvUri)
→ showInvoiceDetailSheet(context, _dbHelper, linkInvId)
```

> يُستدعى داخل `_runGlobalSearch` و `_applyScannedCode`.

### 6.3 _shiftGateListener

```dart
// يستمع لتغيرات ShiftProvider:
- إن أُغلقت الوردية → ينقل الـ Navigator لـ '/open-shift' (إجباري)
- مع كل تغيير → _recomputeNavModules() لإعادة فلترة الـ destinations
```

### 6.4 _onBusinessFeaturesRevision

```dart
// كل ما تتغيّر إعدادات الأعمال (مثلاً تفعيل ميزة الأقساط):
- _recomputeNavModules()
```

### 6.5 _onRemoteSnapshotImported

```dart
// عند استيراد لقطة من جهاز آخر:
- refresh ShiftProvider
- إن لم تكن هناك وردية → '/open-shift'
- وإلا: _refreshHomeAuxProviders + ProductProvider.loadProducts
- setState
```

> **قرار الترحيل:** كل هذه الـ listeners تنتقل كما هي. الـ AdaptiveScaffold لن يلمسها.

---

## 7. الـ Keyboard Shortcuts (الحالة الراهنة)

> **النتيجة:** لا توجد `Shortcuts` أو `Intent` widgets معرّفة في `home_screen.dart` حاليًا.

### 7.1 ما يجب إضافته في الترحيل (للديسكتوب فقط)

بناءً على دستور الشاشة الرئيسية:

| الاختصار | الإجراء |
|---|---|
| `Ctrl/Cmd + K` | تركيز شريط البحث |
| `Ctrl/Cmd + N` | فاتورة جديدة (Push to AddInvoiceScreen) |
| `Ctrl/Cmd + ,` | الإعدادات |
| `Esc` | إغلاق Sheet/Overlay/البحث |
| `Tab / Shift+Tab` | تنقل بين بطاقات الـ Dashboard |
| `Enter` | فتح البطاقة المركّز عليها |

> **شرط:** ينشط فقط في `desktopSM` و`desktopLG`.

---

## 8. الـ UI Features (الميزات المرئية)

### 8.1 الـ AppBar (الحالي)

**في الديسكتوب/التابلت الكبير (`_buildAppBar`):**
- لون الخلفية: `colorScheme.primary` (Navy)
- العنوان: `_buildZorahTitle()` — اسم الشركة (Zorah) + GestureDetector لتشغيل أنيميشن
- الأزرار (Compact، عرض < 960): shift, notif, user, overflow menu
- الأزرار (Full، عرض ≥ 960): shift, divider, user, notif, divider, calculator, settings, edit, dark mode toggle
- في الأسفل (`bottom`): شريط البحث

**في الموبايل (`_buildMobileTopAppBar`):**
- نفس الشكل لكن **بدون** شريط البحث في الـ bottom
- البحث يظهر منفصلاً تحت الـ AppBar وقابل للطي عند التمرير

### 8.2 شريط البحث (`_buildSearchBar`)

ميزات:
- Virtual keyboard عربي/إنجليزي
- Debounce على `_scheduleGlobalSearch`
- البحث في 4 مصادر: منتجات، عملاء، مستخدمين، وحدات
- Suffix dynamic: زر باركود، زر تشغيل/إيقاف الكيبورد، زر مسح
- يختفي على الموبايل عند التمرير، يعود عند السحب للأسفل

### 8.3 بانر صلاحيات الوردية (الشريط الأزرق)

> الموقع الحالي: تحت شريط البحث، يعرض نص مثل “صلاحيات التشغيل مرتبطة بنوبة الوردية – ali ahmad”.

**القرار المعتمد** بناءً على إجابات المستخدم:
- `phoneXS/SM` → أيقونة في الـ AppBar مع Tooltip.
- `tabletSM/LG` → Banner نحيف (32px).
- `desktopSM/LG` → Banner كامل تحت شريط البحث.

### 8.4 Breadcrumb Strip (`_buildBreadcrumbStrip`)

- يظهر **في الشاشات الكبيرة فقط** (≥ 800dp في النسخة الحالية).
- يعرض مسار التنقل داخل الـ Inner Navigator.
- يستخدم `_breadcrumbTrail` و `BreadcrumbSegment`.

**قرار الترحيل:** يظل مرئيًا في `tabletLG`, `desktopSM`, `desktopLG`. يُخفى في `phoneXS`, `phoneSM`, `tabletSM` (لتوفير المساحة).

### 8.5 السايدبار (`_buildPersistentSidebar`)

- عرضين: مطوي (56px) / مفتوح (220px)
- `AnimatedContainer` 240ms `easeInOut`
- يعرض الوحدات + sub-items expandable
- يعرض بطاقة المستخدم في الأعلى
- زر تسجيل خروج في الأسفل

**قرار الترحيل:** يُستبدل بالكامل بـ `AdaptiveScaffold` (Sidebar في الديسكتوب، Rail في التابلت). السلوكيات تنتقل لـ `AdaptiveScaffold`.

### 8.6 BottomNavBar (`_buildBottomNavBar`)

- العرض الحالي: كل الوحدات (12) كأيقونات أفقية + قائمة overflow.
- يستخدم `_BottomNavIcon` و `_BottomNavTile` (subclasses).
- مسار طويل ومعقد بسبب dynamic resizing.

**قرار الترحيل:** يُستبدل بـ `NavigationBar` Material 3 داخل `AdaptiveScaffold`. أول 4-5 وحدات فقط حسب الـ variant.

### 8.7 الـ Floating Calculator Overlay

- يُفتح عبر `showFloatingCalculator(context)`.
- موقعه الحالي: زر في الـ AppBar (في النسخة الكاملة).

**قرار الترحيل:**
- `phoneXS` → ينتقل لقائمة “المزيد” فقط.
- `phoneSM/tabletSM/tabletLG` → FAB.
- `desktopSM/desktopLG` → لوحة جانبية يسرى قابلة للإخفاء.

### 8.8 App Notifications Sheet

- يُفتح عبر `showAppNotificationsSheet(...)` من زر الـ AppBar.

**قرار الترحيل:** يبقى كما هو لكن مكان زرّه يتغير حسب الـ variant:
- موبايل/تابلت → في الـ AppBar.
- ديسكتوب → في الـ AppBar (نفس الموقع، يفتح كـ Popover بدل Sheet).

### 8.9 Invoice Detail Sheet

- يُفتح عبر `showInvoiceDetailSheet(context, _dbHelper, id)`.
- يُستدعى من: Deep links، Recent activities، Pinned products، Barcode scan.

**قرار الترحيل:** يبقى كما هو. سلوك Bottom Sheet/Modal مناسب لكل الـ variants.

### 8.10 Dashboard Content (`_buildMainContent` + `DashboardView`)

عناصر:
1. **`HomeGlanceOrbit`**: 6 بطاقات (cash, newSale, inventoryProducts, parkedSales, reportsExecutive, completedOrders).
2. **Pinned Products**: شبكة منتجات قابلة للبيع السريع.
3. **Recent Activities**: 8 أنواع نشاط (invoice, cashMovement, parkedSale, loyalty, stockVoucher, customerCreated, productCreated, ...).

**قرار الترحيل:** نوسّع `dashboard_view.dart` ليصبح Adaptive (GridView متجاوب) بدل التخطيط الثابت الحالي. **لا نستبدله**.

### 8.11 Mac-Style Settings Panel

- ميزة اختيارية تُفعَّل عبر `MacStyleSettingsPrefs.isMacStylePanelEnabled()`.
- شاشات معينة (`_macFloatingRouteIds`) تُفتح كنوافذ عائمة بدل push.

**قرار الترحيل:** تبقى الميزة كما هي بدون تغيير في المنطق.

### 8.12 تأثيرات بصرية إضافية

| العنصر | الموقع | حالة الترحيل |
|---|---|---|
| `_animateCompanyName` (نقر على العنوان → animation) | `_buildZorahTitle` | يبقى |
| `_buildDarkModeToggle` (Toggle الـ Dark/Light) | AppBar actions | يبقى |
| `AppCornerStyle` (زوايا مستديرة/حادة من إعدادات المستخدم) | `_homeAppBarActionStyle` | يبقى |
| Black overlay عند نتائج البحث | Stack | يبقى |
| `_buildSearchOverlayDropdown` (قائمة نتائج البحث) | Positioned | يبقى |
| الـ 6 أيقونات الصغيرة في أعلى اليسار | Custom AppBar | يُدمج في الـ AppBar الجديد (المنظم) |

---

## 9. الـ Inner Navigator (نمط حرج)

### 9.1 لماذا هو ضروري؟

الـ Inner Navigator يحفظ حالة التنقل **داخل** الشاشة الرئيسية. عند التبديل بين وحدات في Sidebar/BottomNav، **لا يفقد المستخدم الـ history**. هذا حرج لـ:
- POS: لو المستخدم في وسط بيع وضغط على “العملاء”، يعود للبيع كما تركه.
- المخزون: navigation متعدد المستويات (Hub → قائمة → تفاصيل).

### 9.2 المفاتيح المستخدمة

- `_innerNavKey: GlobalKey<NavigatorState>` — للشاشات الكبيرة (`isLarge ≥ 800`).
- `_innerNavKeySmall: GlobalKey<NavigatorState>` — للشاشات الضيقة.
- `restorationScopeId`: `'home_inner_nav_main'` / `'home_inner_nav_small'`.

### 9.3 المراقبون (Observers)

- `_innerNavObserver` (محلي).
- `homeInnerRouteObserver` (مشترك مع `app_route_observer.dart`).

### 9.4 الـ PopScope

`canPop: false` مع `onPopInvokedWithResult` يدوي لإدارة الـ back button في كل من المفتاحين.

> **قرار الترحيل الحرج:** الـ Inner Navigator **يجب أن ينتقل بالكامل** إلى `AdaptiveScaffold.body`. يجب أن نتأكد أن:
> 1. عند التبديل بين الـ variants (مثل إغلاق نافذة من ديسكتوب إلى موبايل)، الـ history لا تضيع.
> 2. كل من المفتاحين له `restorationScopeId` مختلف.
> 3. الـ Observers مسجلين في كلا المفتاحين.

### 9.5 المسارات داخل الـ Inner Navigator (`AppContentRoutes`)

> هذه مسارات داخلية (ليست `Navigator.pushNamed` الرسمي). يجب أن تظل كلها قابلة للاستدعاء.

| Route Constant | الشاشة |
|---|---|
| `AppContentRoutes.home` | _HomeContentPage (الحالية) |
| `AppContentRoutes.invoices` | InvoicesScreen |
| `AppContentRoutes.addInvoice` | AddInvoiceScreen |
| `AppContentRoutes.parkedSales` | ParkedSalesScreen |
| `AppContentRoutes.salePosSettings` | SalePosSettingsScreen |
| `AppContentRoutes.customers` | CustomersScreen |
| `AppContentRoutes.customersAdd` | CustomerFormScreen |
| `AppContentRoutes.customerContacts` | CustomerContactsScreen |
| `AppContentRoutes.loyaltySettings` | LoyaltySettingsScreen |
| `AppContentRoutes.loyaltyLedger` | LoyaltyLedgerScreen |
| `AppContentRoutes.installments` | InstallmentsScreen |
| `AppContentRoutes.installmentSettings` | InstallmentSettingsScreen |
| `AppContentRoutes.debts` | DebtsScreen |
| `AppContentRoutes.debtSettings` | DebtSettingsScreen |
| `AppContentRoutes.inventory` | InventoryHubScreen |
| `AppContentRoutes.inventoryProducts` | InventoryProductsScreen |
| `AppContentRoutes.addProduct` | AddProductScreen |
| `AppContentRoutes.quickUpdateProducts` | QuickProductUpdateScreen |
| `AppContentRoutes.inventoryBarcodeLabels` | BarcodeLabelsScreen |
| `AppContentRoutes.inventoryManagement` | InventoryManagementScreen |
| `AppContentRoutes.inventoryWarehouses` | WarehousesScreen |
| `AppContentRoutes.inventoryStocktaking` | StocktakingScreen |
| `AppContentRoutes.inventoryPurchaseOrders` | PurchaseOrdersScreen |
| `AppContentRoutes.inventoryAnalytics` | StockAnalyticsScreen |
| `AppContentRoutes.inventorySettings` | InventorySettingsScreen |
| `AppContentRoutes.servicesHub` | ServicesHubScreen |
| `AppContentRoutes.servicesAdd` | AddServiceScreen |
| `AppContentRoutes.serviceOrdersHub` | ServiceOrdersHubScreen |
| `AppContentRoutes.cash` | CashScreen |
| `AppContentRoutes.expenses` | ExpensesScreen |
| `AppContentRoutes.reports(N)` | ReportsScreen(initialSection: N) |
| `AppContentRoutes.users` | UsersScreen |
| `AppContentRoutes.staffShiftsWeek` | StaffShiftsWeekScreen |
| `AppContentRoutes.employeeIdentity` | EmployeeIdentityScreen |
| `AppContentRoutes.printing` | PrintingScreen |

> هذه ليست `Named Routes` للـ `Navigator` الرئيسي. هي مسارات داخلية للـ Inner Navigator. **لا تخلطها مع `routes_inventory.md`**.

---

## 10. ميزات قابلة للحذف (بقرار صريح)

### 10.1 شريط الـ QuickActions الأربعة (تحت AppBar)

- المحتوى: البيع، تسديد قسط، المرتجعات، بحث.
- **القرار:** **يُحذف نهائيًا**.
- **التبرير:** تكرار. كلها مغطّاة بـ Dashboard cards + FAB + AppBar.
- **الكود المُؤثر:** `_quickActions`, `_defaultQuickActions`, `_quickActionSize`, `_addQuickAction`, `_saveQuickActions`, الـ persistent prefs `quick_actions_labels`.

> **ملاحظة هامة:** الـ `_saveQuickActions` يكتب في `SharedPreferences`. عند الحذف، نتأكد من **عدم قراءة prefs قديمة** يمكن أن تعيد المنطق. الحذف يجب أن يكون كاملاً (read + write).

### 10.2 الأرقام الثابتة في الشاشة الحالية

- `const kWideBreakpoint = 800.0` (السطر 1538) → يُستبدل بـ `DeviceVariant`.
- `_quickActionSize(width)` ثوابت (70/80/90) → تُحذف مع QuickActions.
- `collapsedW = 56.0` / `expandedW = 220.0` (السايدبار) → يُستبدل بمنطق `AdaptiveScaffold` الذي يعتمد على `desktopSM (240)` / `desktopLG (280)`.
- `compact = sl.isHandsetForLayout || w < 960` → يُستبدل بـ `layoutVariant`.

---

## 11. ميزات تحتاج توضيحًا أو قرارًا

> هذه ميزات اكتُشفت أثناء الفحص وتحتاج قرار المستخدم قبل الترحيل.

### 11.1 ❓ الـ 6 أيقونات الصغيرة في أعلى اليسار (الموجودة في الصور)

تظهر في الصور كأيقونات صغيرة بدون تسميات. **لم أعثر عليها بوضوح في الكود** ضمن `_buildAppBarActions` الذي يحتوي:
- shift, notif, user, calculator, settings, edit, dark mode toggle.

**سؤال:** هذه هي الـ 7 أزرار الموجودة في وضع “Full”. هل هي بالفعل المقصودة؟

**اقتراح الترحيل:** كلها تبقى في الـ AppBar الجديد، لكن:
- موبايل: تظهر 3 فقط (notif, user, overflow menu).
- تابلت/ديسكتوب: تظهر كلها مع فواصل.

### 11.2 ❓ زر تعديل الترتيب (`_appBarEditButton`)

- يسمح بسحب الـ Modules لإعادة الترتيب.
- يحفظ في `SharedPreferences.modules_order`.

**سؤال:** نبقي هذه الميزة بعد الترحيل؟ (نوصي: نعم — تخصيص مهم للمستخدم).

### 11.3 ❓ التخصيص في `_persistModulesOrder`

ميزة مرتبطة بالتعديل (السابقة). تكتب الترتيب الجديد للقرص.

**قرار:** يبقى كما هو.

### 11.4 ❓ بطاقة “لمحة المربح” (الموجودة في الصور)

تظهر في الصور بستة عناصر:
- بيع جديد (فاتورة سريعة)
- التقارير (لوحة تفاعلية)
- معلّقات (0 فاتورة)
- الطلبات المنتظرة (0 طلب)
- الصندوق (559,500 د.ع)
- المخزون (3554 صنفًا نشطًا)

**هذه هي `HomeGlanceOrbit`** في الـ `DashboardView`. القرار: **توسعة** `dashboard_view.dart` لتصبح Adaptive Grid (متغير عدد الأعمدة حسب الـ variant).

### 11.5 ❓ شريط “منتجات مثبتة”

في الصور: شبكة 5 منتجات + Filter Chips (الكل, hmrv, fbn, ...).

**قرار:** ميزة جيدة، تبقى. لكن **يجب توفر `EmptyState`** عند عدم وجود منتجات مثبتة (حاليًا تظهر بيانات تجريبية فارغة).

---

## 12. خريطة “ماذا يصبح ماذا” (Migration Map)

| الموجود حاليًا | يُصبح في النسخة الجديدة |
|---|---|
| `Scaffold` + Drawer + BottomNav + Custom AppBar | `AdaptiveScaffold` (slot واحد لكل شيء) |
| `LayoutBuilder` + `kWideBreakpoint = 800` | `context.screenLayout.layoutVariant` (6 فئات) |
| `_buildPersistentSidebar(isExpanded)` | جزء داخلي من `AdaptiveScaffold._buildDesktopLayout` |
| `_buildBottomNavBar(modules)` | جزء داخلي من `AdaptiveScaffold._buildMobileLayout` |
| `_buildAppBar` / `_buildMobileTopAppBar` | `appBar:` slot في `AdaptiveScaffold` |
| `_buildSearchBar()` | يُمرر كـ `searchBar:` slot (يبقى استخدامه القديم من `_searchController`) |
| `_quickActionSize` + شريط الأزرار الأربعة | **يُحذف** |
| `_buildBreadcrumbStrip` | يُمرر داخل الـ body (يظهر في tabletLG + desktop) |
| `_isDrawerOpen` value notifier | **يُحذف** (لم يعد للـ Sidebar وضع طي قابل للتفاعل اليدوي — يتحكم بها `AdaptiveScaffold` تلقائيًا) |
| `_innerNavKey` + `_innerNavKeySmall` | يبقيان كما هما داخل `AdaptiveScaffold.body` |
| `_buildMainContent` | يبقى لكن يستدعي `DashboardView` الموسّع |
| `DashboardView` ثابت | `DashboardView` Adaptive (GridView متجاوب) |
| الشريط الأزرق للصلاحيات | Widget جديد `ShiftPermissionBanner` يتصرف حسب الـ variant |
| Mac-Style Settings Panel | يبقى كما هو |

---

## 13. الخريطة الزمنية للترحيل (لـ PR Pilot)

| الخطوة | المخرج | تقدير الوقت |
|---|---|---|
| 1. كتابة `home_screen_wireframe.md` | wireframe ASCII للستة variants | 15 دقيقة |
| 2. مراجعة المستخدم | موافقة | 10 دقيقة |
| 3. توسعة `dashboard_view.dart` لتكون Adaptive | grid متجاوب | 1 ساعة |
| 4. بناء `ShiftPermissionBanner` widget | متجاوب | 30 دقيقة |
| 5. إعادة كتابة `home_screen.dart` باستخدام `AdaptiveScaffold` | الـ shell كله | 2-3 ساعات |
| 6. ترحيل كل الـ initState/dispose/listeners بدون فقدان | حفظ كل تكامل | 1 ساعة |
| 7. إضافة keyboard shortcuts للديسكتوب | جديد | 30 دقيقة |
| 8. اختبار يدوي على الـ 6 variants | تحقق | 30 دقيقة |
| 9. كتابة Golden tests | جديد | 1 ساعة |
| 10. كتابة Smoke test | جديد | 30 دقيقة |
| **المجموع** | | **8-10 ساعات** |

---

## 14. قائمة DoD للتحقق النهائي

```
☐ كل provider في القسم 1.1 لا يزال مستخدمًا بنفس التوقيع.
☐ كل service في القسم 1.2 لا يزال يُستدعى.
☐ كل listener في القسم 3.1 يُسجَّل في initState.
☐ كل listener في القسم 3.4 يُلغى في dispose.
☐ GlobalBarcodeRouteBridge.attach و takePendingScan يعملان.
☐ _shiftGateListener ينقل لـ '/open-shift' عند إغلاق الوردية.
☐ _onRemoteSnapshotImported يحدّث الـ Providers.
☐ كل وحدة من الـ 12 في القسم 4.1 موجودة في القائمة.
☐ كل sub-item في القسم 4.1 (30+) قابل للوصول.
☐ كل permission key في القسم 5.1 يُفحص.
☐ كل business feature toggle في القسم 5.3 يحجب الوحدة عند 0.
☐ Inner Navigator (في الـ variants المناسبة) يحفظ history التنقل.
☐ Breadcrumb يظهر في tabletLG+desktop ويعمل.
☐ Floating calculator متاح حسب الـ variant.
☐ App notifications sheet يفتح من زر الـ AppBar.
☐ Invoice detail sheet يفتح من Deep Link + Recent Activity + Pinned Product + Barcode.
☐ Search bar يعمل بالـ debounce + virtual keyboard + 4 مصادر.
☐ Dark mode toggle يعمل.
☐ Mac-style floating routes تعمل لو مفعّلة.
☐ شريط QuickActions الأربعة محذوف **كاملاً** (read + write of prefs).
☐ flutter analyze نظيف.
☐ لا تعديل على services/providers/models/navigation.
☐ routes_inventory.md لم يُكسر.
☐ Golden tests للستة variants تمر.
☐ Smoke test للتنقل يمر.
```

---

## 15. الأسئلة المفتوحة للمستخدم

> أسئلة اكتُشفت أثناء الجرد ولم تُحسم في النقاش السابق:

1. **الأيقونات الـ 7 في الـ AppBar (Full mode)**: نبقيها كاملة في الديسكتوب، أم نقلل بعضها؟ (مثل: نحذف زر الـ Edit ونضعه في قائمة المستخدم؟)
2. **زر الـ Edit (إعادة ترتيب الوحدات)**: نبقيه فقط في الديسكتوب؟
3. **`_animateCompanyName` (نقر على اسم الشركة → animation)**: نبقيها كميزة “easter egg” أم نحذفها؟
4. **ميزة `MacStyleSettingsPanel` العائمة**: نوسعها لتعمل على كل الـ variants أم نقتصرها على الديسكتوب؟
5. **`_buildBreadcrumbStrip`**: في الصور يظهر شريط أزرار أربعة (بيع، تسديد قسط، المرتجعات، بحث) — هل هذا هو الـ QuickActions الذي قررنا حذفه، أم هذا شيء آخر؟ يرجى التأكيد.

---

> **حالة الجرد:** ✅ مكتمل.
> **الخطوة التالية:** كتابة `home_screen_wireframe.md` ثم البدء بكتابة الكود.
