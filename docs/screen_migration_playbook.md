# دستور إعادة هيكلة واجهات Basra Store Manager
## (Adaptive UI Migration Constitution & Screen Playbook)

> **حالة الوثيقة:** دستور مُجمّد (Frozen Constitution).
> **الغرض:** المرجع الوحيد والشامل لإعادة هيكلة واجهات التطبيق إلى نموذج متجاوب (Adaptive) موحّد الهوية.
> **النطاق:** يُلزم كل مطور (ومحرر ذكاء اصطناعي) يعمل على ملفات `lib/screens/**`, `lib/widgets/**`, `lib/theme/**`.
> **الإصدار:** 1.0 — 2026-05-13.

---

## جدول المحتويات

1. [الفلسفة العامة (Vision & Principles)](#1-الفلسفة-العامة)
2. [ضمانات سلامة الهيكلة (Architecture Safeguards)](#2-ضمانات-سلامة-الهيكلة)
3. [معيار القبول النهائي (Definition of Done)](#3-معيار-القبول-النهائي)
4. [دستور التصميم المتجاوب (Adaptive UI Rules)](#4-دستور-التصميم-المتجاوب)
5. [المكونات المركزية الإلزامية (Mandatory Central Components)](#5-المكونات-المركزية-الإلزامية)
6. [قواعد الاتجاهات والوصول (RTL & Accessibility)](#6-قواعد-الاتجاهات-والوصول)
7. [دستور الشاشة الرئيسية (Home Screen Constitution)](#7-دستور-الشاشة-الرئيسية)
8. [دليل ترحيل الشاشة الواحدة (Screen Migration Playbook)](#8-دليل-ترحيل-الشاشة-الواحدة)
9. [أنماط الترحيل حسب فئة الشاشة (Migration Patterns by Type)](#9-أنماط-الترحيل-حسب-فئة-الشاشة)
10. [خريطة الطريق ومتتبع الحالة (Roadmap & Status Tracker)](#10-خريطة-الطريق-ومتتبع-الحالة)
11. [الممنوعات المطلقة (Absolute Prohibitions)](#11-الممنوعات-المطلقة)
12. [الأسئلة الشائعة (FAQ)](#12-الأسئلة-الشائعة)
13. [المراجع وروابط الكود (References)](#13-المراجع-وروابط-الكود)

---

## 1. الفلسفة العامة

### الرؤية
تطبيق متجاوب حقيقي (Adaptive، ليس فقط Responsive) يعمل بكفاءة على ست فئات أجهزة من هاتف صغير جداً إلى ديسكتوب كبير، مع **هوية بصرية موحدة** و**سلوك متوقع** على كل حجم.

### المبادئ الستة الحاكمة

| # | المبدأ | المعنى العملي |
|---|---|---|
| 1 | **Single Source of Truth** | مرجع واحد للمقاسات (`ScreenLayout`)، الألوان (`AppColors`)، المسافات (`AppSpacing`)، الخطوط (`AppTypography`). |
| 2 | **Extend, Don't Replace** | نوسّع الموجود ولا نستبدله. لا ملفات تكرّر وظيفة موجودة. |
| 3 | **Layer Freeze** | الترحيل في طبقة الواجهات فقط. يُمنع تعديل `services`, `providers`, `models`, `navigation`. |
| 4 | **Routing Stability** | المسارات والـ Deep Links عقد مُجمّد. اكسره = PR مرفوض. |
| 5 | **One Screen Per PR** | شاشة واحدة لكل PR، إزالة كاملة للكود القديم في نفس الـ PR. |
| 6 | **No Mass Changes** | يُمنع Find & Replace جماعي. كل تعديل يدوي ومراجَع. |

### المساحة تُستخدم للمحتوى، لا للتمطيط

القاعدة الذهبية: **المساحة الإضافية في الديسكتوب تعرض معلومات أكثر، لا تكبّر العناصر الحالية**. بطاقة منتج لا تصبح أعرض في 4K — نضع بطاقات أكثر بدلاً من ذلك.

---

## 2. ضمانات سلامة الهيكلة

### 2.1 المرجع الوحيد للمقاسات
- المرجع الرسمي: `lib/utils/screen_layout.dart`.
- الـ enum: `DeviceVariant` (six values).
- لا يُنشأ ملف `AppBreakpoints` أو enum بديل.

### 2.2 التوسعة لا الاستبدال
- `design_tokens.dart` يبقى. نضيف بجواره `app_spacing.dart` و`app_typography.dart`.
- `screen_layout.dart` يبقى بدواله القديمة (`isHandsetForLayout` etc.). نضيف فقط `layoutVariant` والـ getters الستة الجديدة.

### 2.3 تجميد الطبقات

| الطبقة | الحالة في هذا الترحيل |
|---|---|
| `lib/screens/**` | ✅ ضمن النطاق |
| `lib/widgets/**` | ✅ ضمن النطاق |
| `lib/theme/**` | ✅ ضمن النطاق (إضافة فقط) |
| `lib/utils/screen_layout.dart` | ✅ توسعة فقط |
| `lib/services/**` | ❌ مجمد |
| `lib/providers/**` | ❌ مجمد |
| `lib/models/**` | ❌ مجمد |
| `lib/navigation/**` | ❌ مجمد |
| `lib/storage/**` | ❌ مجمد |
| `lib/dev/**` | ❌ خارج النطاق |
| `lib/main.dart` | ❌ ما عدا تسجيل الثيم |
| `lib/firebase_options.dart` | ❌ خارج النطاق |

> **استثناء:** إذا اكتشفت أثناء الترحيل خطأً معطلاً للبناء في طبقة مجمدة، أصلحه في **PR منفصل** قبل العودة لترحيل الشاشة.

### 2.4 استقرار المسارات
- العقد المُجمّد: [`docs/routes_inventory.md`](./routes_inventory.md).
- يُمنع تغيير: أسماء الـ Named Routes، أو الـ URL Schemes للـ Deep Links، أو الـ Required Constructor Arguments للشاشات الديناميكية.
- تكييف شاشة من Push إلى Master-Detail داخلي = يجب أن يبقى توقيع الـ constructor كما هو.

### 2.5 سياسة الـ PR

| القاعدة | التطبيق |
|---|---|
| شاشة واحدة لكل PR | ولا حتى دمج شاشتين متشابهتين |
| حذف الكود القديم في نفس الـ PR | ممنوع ترك أنماط مزدوجة |
| `flutter analyze` نظيف | بدون تحذيرات جديدة |
| Tests included | Golden + Smoke في نفس الـ PR |
| تحديث متتبع الحالة | في [القسم 10](#10-خريطة-الطريق-ومتتبع-الحالة) |

---

## 3. معيار القبول النهائي

لا تُعتبر أي شاشة “مكتملة” إلا بعد اجتيازها **سبع نقاط بالضبط**:

```
☐ Adaptive pass — تتجاوب على الفئات الست بدون أي شرط width يدوي
☐ Theme pass — كل الألوان من design_tokens.dart، كل القياسات من AppSpacing
☐ Accessibility pass — textScaleFactor + Keyboard focus + Color contrast
☐ Golden pass — لقطات Golden لكل من الـ 6 variants
☐ Smoke pass — التنقل من/إلى الشاشة بدون أخطاء وقت التشغيل
☐ No regression — الشاشات الأخرى والـ providers لم تتأثر
☐ Rollback plan — git revert يعيد كل شيء بدون أثر جانبي
```

كل بند **إلزامي** قبل الدمج.

---

## 4. دستور التصميم المتجاوب

### 4.1 فئات الأجهزة الست (Mutually Exclusive)

| الفئة | الكود | المدى (`size.width`) | شرط إضافي |
|---|---|---|---|
| هاتف صغير جداً | `phoneXS` | `< 360` | أو `size.height < 600` |
| هاتف عادي | `phoneSM` | `360 – 599` | `height >= 600` |
| تابلت صغير | `tabletSM` | `600 – 839` | — |
| تابلت كبير | `tabletLG` | `840 – 1023` | — |
| ديسكتوب صغير | `desktopSM` | `1024 – 1439` | — |
| ديسكتوب كبير | `desktopLG` | `≥ 1440` | — |

**ملاحظة منطقية:** الفئات متبادلة الاستبعاد بنيوياً عبر `early-return` في `layoutVariant`. لا يمكن أن تتفعّل فئتان معاً.

### 4.2 قواعد التنقل (Navigation Spec)

| الفئة | نوع التنقل | موقعه |
|---|---|---|
| `phoneXS` | `NavigationBar` بـ 4 أيقونات + “المزيد” | أسفل |
| `phoneSM` | `NavigationBar` بـ 5 أيقونات + “المزيد” | أسفل |
| `tabletSM` | `NavigationRail` مضغوط | يمين (RTL) |
| `tabletLG` | `NavigationRail` موسّع (extended) | يمين (RTL) |
| `desktopSM` | Sidebar دائم 240px | يمين |
| `desktopLG` | Sidebar دائم 280px | يمين |

**قاعدة “المزيد” (الموبايل فقط):** يفتح كـ `showModalBottomSheet` يحتوي باقي الـ destinations.

### 4.3 قواعد التفاعل (Interaction Spec)

| الفئة | حجم اللمس الأدنى | Hover | اختصارات الكيبورد |
|---|---|---|---|
| `phoneXS`/`phoneSM` | 48×48px | ❌ ممنوع | بحث فقط |
| `tabletSM`/`tabletLG` | 44×44px | تأثيرات خفيفة (إن كان ماوس متصل) | Tab navigation |
| `desktopSM`/`desktopLG` | 32×32px | ✅ كامل (تظهر أزرار الإجراءات السريعة) | كامل + Focus rings |

### 4.4 قواعد التخطيط (Layout Spec)

| الفئة | عدد الأعمدة (Dashboard) | عرض Master في Master-Detail | عرض النماذج (Forms) |
|---|---|---|---|
| `phoneXS` | 1 | كامل (push للـ detail) | كامل |
| `phoneSM` | 2 | كامل (push للـ detail) | كامل |
| `tabletSM` | 2-3 | 280px | كامل |
| `tabletLG` | 3-4 | 320px | max 600px |
| `desktopSM` | 4 | 320px | max 600px + معلومات جانبية |
| `desktopLG` | 5-6 | 360px | max 700px + معلومات جانبية |

### 4.5 قاعدة عرض البطاقات

- **حد أقصى لعرض البطاقة الواحدة**: 320px (لا تكبير).
- **حد أدنى لعرض البطاقة**: 140px (تحته تصبح “مضغوطة” compact).
- المساحة الإضافية = بطاقات أكثر، لا بطاقات أكبر.

### 4.6 قاعدة الـ Hover

```dart
// مثال على Hover state صحيح
MouseRegion(
  onEnter: (_) => setState(() => _hover = true),
  onExit: (_) => setState(() => _hover = false),
  child: AnimatedOpacity(
    opacity: _hover ? 1.0 : 0.0,
    duration: const Duration(milliseconds: 150),
    child: const _QuickActions(),  // أزرار التعديل/الحذف
  ),
)
```

**شروط**: نشط فقط في `desktopSM` و`desktopLG`. ممنوع في الموبايل والتابلت.

---

## 5. المكونات المركزية الإلزامية

### 5.1 الـ Layer Stack

```
┌─────────────────────────────────────┐
│  Screen (your screen.dart)          │
├─────────────────────────────────────┤
│  AdaptiveScaffold (shell)           │  ← lib/widgets/adaptive/
│  + MasterDetailLayout (pattern)     │
│  + AdaptiveSearchBar (search)       │
├─────────────────────────────────────┤
│  AppSpacing | AppTypography         │  ← lib/theme/
│  AppColors | AppShape | AppGlass    │  ← design_tokens.dart
├─────────────────────────────────────┤
│  ScreenLayout + DeviceVariant       │  ← lib/utils/screen_layout.dart
└─────────────────────────────────────┘
```

### 5.2 `AdaptiveScaffold`

**المسار:** `lib/widgets/adaptive/adaptive_scaffold.dart`

**التوقيع:**
```dart
const AdaptiveScaffold({
  required List<AdaptiveDestination> destinations,
  required int selectedIndex,
  required ValueChanged<int> onDestinationChanged,
  PreferredSizeWidget? appBar,
  Widget? body,
  Widget? searchBar,
  Widget? floatingActionButton,
})
```

**سلوكه:**
- يلفّ `Scaffold` أصلي (للحفاظ على Snackbars/Drawers/Dialogs).
- يقرأ `context.screenLayout.layoutVariant` ويختار التنقل تلقائياً.
- موبايل/تابلت: `appBar` يُمرر للـ Scaffold.
- ديسكتوب: عنوان الشاشة يُدمج مع الـ Sidebar.

### 5.3 `AdaptiveDestination`

**المسار:** `lib/widgets/adaptive/adaptive_destination.dart`

**الحقول:**
```dart
final IconData icon;
final IconData? selectedIcon;
final String label;
final Widget Function(BuildContext) builder;
final String? requiredPermission;   // تكامل مع نظام الصلاحيات
final int? badgeCount;              // عدد الإشعارات
```

### 5.4 `MasterDetailLayout<T>`

**المسار:** `lib/widgets/adaptive/master_detail_layout.dart`

**التوقيع:**
```dart
const MasterDetailLayout<T>({
  required Widget Function(BuildContext, bool isSideBySide) masterBuilder,
  required Widget Function(BuildContext) detailBuilder,
  T? selectedItemId,
  double masterWidth = 320.0,
})
```

**سلوكه:**
- في `phoneXS`/`phoneSM`: يعرض الـ master وحده، الـ detail يُفتح عبر `Navigator.push`.
- في `tabletSM` فما فوق: Row(master على اليمين، detail على اليسار) — احترامًا لـ RTL.

### 5.5 `AdaptiveSearchBar`

**المسار:** `lib/widgets/adaptive/adaptive_search_bar.dart`

**التوقيع:**
```dart
const AdaptiveSearchBar({
  String hintText = 'بحث...',
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  TextEditingController? controller,
})
```

**سلوكه:**
- ديسكتوب: عرض ثابت 480px، يظهر `Ctrl+K` كـ suffix.
- موبايل/تابلت: عرض كامل.
- زوايا حادة (`BorderRadius.zero`) احترامًا لـ `AppShape`.

### 5.6 `ShiftPermissionBanner`

**المسار:** `lib/widgets/adaptive/shift_permission_banner.dart`

**التوقيع:**
```dart
const ShiftPermissionBanner({
  required String userName,
  String? roleName,
  VoidCallback? onTap,
  IconData icon = Icons.shield_outlined,
})
```

**سلوكه الـ Adaptive:**
- `phoneXS`: يختفي تماماً (`SizedBox.shrink`).
- `phoneSM`/`tabletSM`/`tabletLG`: شريط مضغوط 32dp مع نص قصير "وردية {name}".
- `desktopSM`/`desktopLG`: شريط كامل تحت الـ AppBar مع نص "صلاحيات التشغيل مرتبطة بنوبة الوردية - {name}".

> يستهلكه `home_screen.dart` فوق الـ Dashboard مباشرة، ومرشّح للاستخدام في أي شاشة تحتاج إظهار سياق الوردية الفعّالة.

### 5.7 `HomeUserMenu`

**المسار:** `lib/widgets/adaptive/home_user_menu.dart`

**التوقيع (مختصر):**
```dart
const HomeUserMenu({
  required String userName,
  required String userRole,
  required bool isDarkMode,
  required bool isEditMode,
  required bool macPanelEnabled,
  required VoidCallback onShowUserInfo,
  required VoidCallback onToggleTheme,
  required VoidCallback onOpenSettings,
  required VoidCallback onShowCalculator,
  required VoidCallback onToggleEditMode,
  required VoidCallback onLogout,
  VoidCallback? onToggleMacPanel,   // null ⇒ يُخفى تماماً (غير ديسكتوب)
  bool showEditMode = false,         // يظهر الخيار فقط في tabletLG+
})
```

**سلوكه الـ Adaptive:**
- `phoneXS`/`phoneSM`/`tabletSM`: أيقونة دائرية فقط بحرف من اسم المستخدم.
- `tabletLG`/`desktopSM`/`desktopLG`: أيقونة + اسم المستخدم + سهم نازل.
- يُخفي خيار "لوحة Mac" تلقائياً إذا `onToggleMacPanel == null` (على غير الديسكتوب).
- يُخفي خيار "تخصيص الوحدات" إذا `showEditMode == false`.

> راجع §9.7 (AppBar Consolidation Pattern) لاستخدامه في شاشات أخرى.

### 5.7.1 `AdaptiveFormContainer`

**المسار:** `lib/widgets/adaptive/adaptive_form_container.dart`

**التوقيع:**
```dart
const AdaptiveFormContainer({
  required Widget child,
  double maxWidth = 720,
})
```

**سلوكه الـ Adaptive:**
- `phoneXS` / `phoneSM` / `tabletSM`: يمرّر المحتوى كما هو (دون قيود).
- `tabletLG` / `desktopSM` / `desktopLG`: يلفّ المحتوى بـ `Center + ConstrainedBox(maxWidth)`.

**الاستخدام النموذجي**: لفّ جسم نموذج (`body: Form(...)`) لمنع امتداد الحقول
على الشاشات العريضة (نمط §9.3 Form Pattern).

```dart
Scaffold(
  appBar: AppBar(title: const Text('إضافة عميل')),
  body: AdaptiveFormContainer(
    child: Form(key: _formKey, child: ListView(...)),
  ),
)
```

> طُبِّقت في 4 نماذج بـ Phase 4. راجع جدول الشاشات في §10.2.

### 5.8 الـ Barrel Export

**المسار:** `lib/widgets/adaptive/adaptive.dart`

```dart
export 'adaptive_destination.dart';
export 'adaptive_scaffold.dart';
export 'master_detail_layout.dart';
export 'adaptive_search_bar.dart';
export 'shift_permission_banner.dart';
export 'home_user_menu.dart';
export '../../utils/screen_layout.dart' show DeviceVariant, ScreenLayout, ScreenLayoutX;
```

**الاستخدام:**
```dart
import 'package:basra_store_manager/widgets/adaptive/adaptive.dart';
```

سطر واحد يعطيك كل ما تحتاجه.

### 5.9 سلم المسافات `AppSpacing`

**المسار:** `lib/theme/app_spacing.dart`

| الرمز | القيمة | الاستخدام |
|---|---|---|
| `AppSpacing.xs` | 4 | فواصل دقيقة (أيقونة + نص) |
| `AppSpacing.sm` | 8 | حشوة أزرار |
| `AppSpacing.md` | 12 | حشوة بطاقات صغيرة |
| `AppSpacing.lg` | 16 | الهامش الأفقي الرئيسي |
| `AppSpacing.xl` | 24 | فواصل بين الأقسام |
| `AppSpacing.xxl` | 32 | فواصل كبيرة بين الكتل |

> **تحذير:** هذا سلّم ثوابت. للقيم المتجاوبة (مثل `pageHorizontalGap`) يبقى `screen_layout.dart`.

### 5.9.1 الألوان الدلالية `AppSemanticColors`

**المسار:** `lib/theme/design_tokens.dart`

| الثابت | الـ Hex | المُستهلكون النموذجيون |
|---|---|---|
| `AppSemanticColors.success` | `#16A34A` | فاتورة مدفوعة، حالة مكتملة، نجاح |
| `AppSemanticColors.warning` | `#F59E0B` | دين، آجل، تنبيه ناعم |
| `AppSemanticColors.supplier` | `#B45309` | عمليات الموردين، تحصيل |
| `AppSemanticColors.danger` | `#DC2626` | إلغاء، خطر — يفضّل `Theme.colorScheme.error` |
| `AppSemanticColors.info` | `#3B82F6` | معلومات، حالة محايدة |

**القاعدة**: أي لون دلالي مكرّر في أكثر من ملف **يجب** أن يُسجّل هنا.
Single Source of Truth لتعديلات الهوية المستقبلية.

### 5.10 التايبوغرافي الدلالي `AppTypography`

**المسار:** `lib/theme/app_typography.dart`

| الدالة | يُرجع |
|---|---|
| `AppTypography.pageTitle(ctx)` | `Theme.textTheme.headlineSmall` |
| `AppTypography.sectionTitle(ctx)` | `Theme.textTheme.titleLarge` |
| `AppTypography.body(ctx)` | `Theme.textTheme.bodyMedium` |
| `AppTypography.caption(ctx)` | `Theme.textTheme.bodySmall` |

> **مبدأ**: غلاف (Wrapper) فقط. لا أنماط hardcoded. لا تكرار لخط `Tajawal` الموجود في `theme.dart`.

### 5.11 ودجتس الحالات الثلاث (To Be Built)

كل شاشة يجب أن تدعم 3 حالات بشكل **موحد**:

| الحالة | الودجت المتوقع |
|---|---|
| Loading | `LoadingState()` — `CircularProgressIndicator` مركزي مع تسمية |
| Empty | `EmptyState(icon, label, action)` — أيقونة + نص + زر إجراء |
| Error | `ErrorState(message, onRetry)` — أيقونة تحذير + نص + زر إعادة |

> **الحالة الراهنة**: غير مبنية بعد. ستُبنى في PR منفصل قبل البدء بالشاشات التي تجلب بيانات.

---

## 6. قواعد الاتجاهات والوصول

### 6.1 RTL/LTR

- التطبيق عربي RTL افتراضيًا عبر `Locale('ar', 'SA')` — لا `Directionality` يدوي.
- **في Master-Detail**: الـ Master دائمًا على اليمين، الـ Detail على اليسار.
- **القوائم الجانبية**: تفتح من اليمين.
- **الأرقام**: غربية (0-9) عبر `intl`. للعملة العراقية: `lib/utils/iraqi_currency_format.dart`.
- **التواريخ**: `DateFormat.yMMMd('ar')` — لا تنسيق يدوي.
- **محتوى LTR أصيل فقط** (IBAN, barcode, code): يُغلّف بـ `Directionality(textDirection: TextDirection.ltr)`.

### 6.2 Accessibility

| المتطلب | كيفية التطبيق |
|---|---|
| تباين الألوان | استخدم `Theme.colorScheme.onSurface` على `surface`، إلخ. تجنب الألوان الـ hardcoded. |
| `textScaleFactor` | لا تستخدم `fontSize` ثابت في الـ widgets. استخدم `AppTypography`. |
| Keyboard focus (ديسكتوب) | استخدم `Focus` و`FocusableActionDetector` مع `MouseRegion`. |
| Screen readers | استخدم `Semantics(label: ...)` للأزرار الأيقونية. |
| `MediaQuery.disableAnimations` | احترمها، لا تفرض animations. |

---

## 7. دستور الشاشة الرئيسية

> هذا قسم خاص لـ `home_screen.dart` لأنه شاشة Pilot وأكثر تعقيدًا.

### 7.1 الثوابت العابرة للأجهزة (Invariants)

- اللون الأساسي من `AppColors.primary`.
- خط `Tajawal`.
- ترتيب الوحدات: Cash > Invoices > Inventory > Customers > Debts > Reports > Settings.
- زرّ الإشعارات وزرّ الحاسبة موجودان دائمًا (يتغير موقعهما، لا وجودهما).
- البحث متاح دائمًا (يتغير شكله، لا توفّره).

### 7.2 شريط البحث (Search Spec)

| الفئة | الشكل |
|---|---|
| `phoneXS` | أيقونة فقط، يفتح كامل العرض عند الضغط |
| `phoneSM` | شريط دائم، يختفي مع التمرير ويعود |
| `tabletSM` | شريط دائم بدون اختفاء |
| `tabletLG` | شريط دائم 70% من العرض + اقتراحات Dropdown |
| `desktopSM` | شريط 480px مع `Ctrl+K` |
| `desktopLG` | + قائمة “آخر البحثات” جانبية |

### 7.3 المحتوى الرئيسي (Dashboard Content)

| الفئة | أعمدة البطاقات | لوحة المعلومات | معلومات جانبية |
|---|---|---|---|
| `phoneXS` | 1 | شريحة واحدة قابلة للسحب | — |
| `phoneSM` | 2 | كاروسيل أفقي | — |
| `tabletSM` | 2-3 | شبكة 2×2 | — |
| `tabletLG` | 3-4 | شبكة موسعة | في Drawer |
| `desktopSM` | 4 | صف واحد | عمود جانبي (نشاطات + ملخص) |
| `desktopLG` | 5-6 | + رسوم بيانية مصغرة | عمودين (نشاطات + إشعارات حية) |

### 7.4 الإشعارات والحاسبة

| الفئة | الإشعارات | الحاسبة |
|---|---|---|
| `phoneXS` | BottomSheet كامل | في قائمة “المزيد” فقط |
| `phoneSM` | BottomSheet 90% | Floating قابل للسحب |
| `tabletSM`/`tabletLG` | Side Sheet 360-400px من اليمين | Floating |
| `desktopSM`/`desktopLG` | Popover من الـ AppBar | لوحة جانبية يسرى قابلة للإخفاء |

### 7.5 اختصارات الكيبورد (ديسكتوب فقط)

- `Ctrl/Cmd + K` → بحث.
- `Ctrl/Cmd + N` → فاتورة جديدة.
- `Ctrl/Cmd + ,` → الإعدادات.
- `Esc` → إغلاق Sheet/Dialog/Overlay.
- `Tab / Shift+Tab` → تنقل بين البطاقات.
- `Enter` → فتح البطاقة المركّز عليها.

### 7.6 قواعد الأداء

- ❌ ممنوع `BackdropFilter` (Glassmorphism) داخل قوائم/شبكات طويلة في الموبايل.
- ✅ `ListView.builder` / `GridView.builder` للقوائم الطويلة.
- ✅ `RepaintBoundary` حول الحاسبة العائمة.
- ✅ آخر النشاطات: 20 صفًا في الموبايل، 50 في غيرها.

---

## 8. دليل ترحيل الشاشة الواحدة

> هذه هي العملية اليومية. تُكرّر لكل شاشة. **سبع خطوات بالضبط**.

### الخطوة 0 — تصنيف الشاشة

| الفئة | أمثلة | النمط |
|---|---|---|
| **Dashboard** | home, reports | شبكة بطاقات متجاوبة |
| **List** | customers, products, debts | Master-Detail |
| **Detail** | product_detail, invoice_detail | عرض محدد + back button |
| **Form** | add_product, customer_form | Max-Width + معلومات جانبية |
| **POS** | cash, add_invoice | Row(منتجات + عربة) |
| **Settings** | settings_screen | Side Tabs |

### الخطوة 1 — جرد الميزات (إلزامي)

أنشئ ملف `docs/migration_checklists/<screen_name>_checklist.md`:

```markdown
# Migration Checklist: <screen_name>

## UI Features
- ☐ feature 1
- ☐ feature 2

## State & Providers
- ☐ Provider X
- ☐ Provider Y

## Navigation In/Out
- ☐ Pushes to: ...
- ☐ Pushed from: ...

## Deep Links
- ☐ scheme://host/...

## Permissions
- ☐ requires: ...

## Conditional Logic (existing breakpoints)
- ☐ w < 560 (legacy)
- ☐ shortestSide < 600

## Features at Risk of Loss
- ☐ feature Z (note why and decision)
```

> **قاعدة الذهب**: لا تكتب سطر كود قبل اكتمال هذا الملف 100%.

### الخطوة 2 — استخراج النية (Intent Mapping)

لكل ميزة في الجرد، صنّفها:
- **Functional** → تبقى، تنتقل لمكان جديد.
- **Visual** → تتغير حسب الـ variant.
- **Logical** → تُحذف/تُدمج/تنتقل لـ Provider.

> ممنوع حذف ميزة Functional بدون قرار صريح موثق في الـ checklist.

### الخطوة 3 — تطبيق نمط فئة الشاشة

ارجع إلى [القسم 9](#9-أنماط-الترحيل-حسب-فئة-الشاشة) واتبع النمط حرفيًا.

### الخطوة 4 — التنفيذ الفعلي

ترتيب صارم:

1. اقرأ الملف القديم كاملاً مرة واحدة.
2. اكتب الملف من الصفر في نفس المسار.
3. ابدأ بـ `AdaptiveScaffold` + النمط المناسب.
4. استورد عبر `widgets/adaptive/adaptive.dart` (barrel).
5. استخدم `AppSpacing.*` لكل القياسات.
6. استخدم `AppTypography.*` لكل النصوص العنوانية.
7. استخدم `design_tokens.dart` لكل الألوان.
8. استخدم `context.screenLayout.layoutVariant` للقرارات التخطيطية.
9. استخدم `context.screenLayout.isHandsetForLayout` فقط للقرارات المادية (لمس، كاميرا).

### الخطوة 5 — اجتياز DoD السبعة

راجع [القسم 3](#3-معيار-القبول-النهائي).

### الخطوة 6 — المراجعة الذاتية

| سؤال | الجواب المطلوب |
|---|---|
| هل يوجد `Color(0xFF...)`؟ | لا |
| هل يوجد `EdgeInsets.all(N)` بأرقام؟ | لا |
| هل يوجد `if (width < X)` يدوي؟ | لا |
| هل كل feature في الـ checklist موجود؟ | نعم 100% |
| هل routes_inventory.md لم يكسر؟ | نعم |
| هل عدلت ملفاً في طبقة مجمدة؟ | لا |
| هل `flutter analyze` نظيف؟ | نعم |

### الخطوة 7 — التوثيق

- حدّث متتبع الحالة في [القسم 10](#10-خريطة-الطريق-ومتتبع-الحالة).
- أرفق رابط الـ PR.
- أرفق لقطات Golden للستة variants.

---

## 9. أنماط الترحيل حسب فئة الشاشة

### 9.1 Dashboard Pattern

```dart
return AdaptiveScaffold(
  destinations: _destinations,
  selectedIndex: _index,
  onDestinationChanged: (i) => setState(() => _index = i),
  appBar: AppBar(title: Text(AppTypography.pageTitle(ctx))),
  searchBar: const AdaptiveSearchBar(),
  body: _buildDashboard(context),
);

Widget _buildDashboard(BuildContext context) {
  final variant = context.screenLayout.layoutVariant;
  final columns = switch (variant) {
    DeviceVariant.phoneXS => 1,
    DeviceVariant.phoneSM => 2,
    DeviceVariant.tabletSM => 2,
    DeviceVariant.tabletLG => 3,
    DeviceVariant.desktopSM => 4,
    DeviceVariant.desktopLG => 5,
  };
  return GridView.builder(
    padding: EdgeInsets.all(AppSpacing.lg),
    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
    ),
    itemCount: _cards.length,
    itemBuilder: (ctx, i) => _ModuleCard(card: _cards[i]),
  );
}
```

> **تطبيق فعلي**: راجع `lib/screens/inventory/inventory_screen.dart` →
> الدالة `_gridColumnsFor(BuildContext)` تطبق هذا النمط بدقة على `_StatsBar` و `_ModulesGrid` (Phase 3-ج).
> الجدول المُعتمد هناك: `phoneXS=1, phoneSM=2, tabletSM=3, tabletLG=3, desktopSM=4, desktopLG=4` —
> حسب حجم كل بطاقة، يُسمح بتخفيض `desktopLG` من 5 إلى 4 لتفادي عرض شاشات هزلية الطول.

### 9.2 List Pattern

```dart
return AdaptiveScaffold(
  appBar: AppBar(title: const Text('العملاء')),
  body: MasterDetailLayout<int>(
    selectedItemId: _selectedId,
    masterBuilder: (ctx, isSideBySide) => _CustomersList(
      onItemTap: (id) {
        if (isSideBySide) {
          setState(() => _selectedId = id);
        } else {
          Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => CustomerDetailScreen(id: id),
          ));
        }
      },
    ),
    detailBuilder: (ctx) => CustomerDetailScreen(id: _selectedId!),
  ),
);
```

> **تطبيق فعلي (Pilot List Screen — `invoices_screen.dart`)**:
>
> الشاشة المعيارية لـ Master-Detail Pattern. تحوي:
>
> 1. **`MasterDetailLayout`** يُفعَّل فقط على `isWideVariant` (`tabletLG+`).
>    على `phoneXS`/`phoneSM`/`tabletSM` تبقى التجربة الكلاسيكية (PDF preview ⇒ BottomSheet).
>
> 2. **`InvoiceDetailPanel`** ودجت مستقل قابل لإعادة الاستخدام —
>    يُدير تحميل الفاتورة async + يعرض حالة فارغة + يستهلك `onClose` callback.
>    *مرجع: `lib/widgets/invoice_detail_sheet.dart`.*
>
> 3. **تمييز البطاقة المختارة** بصرياً: `Border` جانبي + خلفية بلون `cs.primary` خفيف.
>
> 4. **Keyboard Shortcuts** عبر `Shortcuts + Actions + Focus`:
>    - `Ctrl+N` / `Cmd+N` ⇒ فاتورة جديدة.
>    - `Ctrl+F` / `Cmd+F` ⇒ تركيز شريط البحث.
>    - `Esc` ⇒ إغلاق الـ Detail Panel.
>
> 5. **AppBar Consolidation للهواتف**: 4 أيقونات ⇒ 2 ظاهرة + PopupMenu للباقي (راجع §9.7).
>
> 6. **Stats Bar متجاوبة** عبر `isPhoneVariant` + `c.maxWidth < 600` (احتساب
>    عرض الـ master pane أيضاً).
>
> ⚠️ ملاحظة معمارية: المُهم في refactoring `InvoiceDetailSheet` كان فصل
> **محتوى التفاصيل** (`_InvoiceDetailContent`) عن **الواجهة الحاضنة**
> (`showModalBottomSheet` vs `InvoiceDetailPanel`). نفس النمط نطبقه لاحقاً على
> `customers/`, `debts/`, `installments/`.

#### 9.2.1 Card Action Pill Pattern (Inline Actions داخل بطاقات القوائم)

نمط ERP عالمي لعرض إجراء سياقي بشكل compact داخل عنصر القائمة دون الحاجة
لفتح قائمة أو سياق آخر.

**القواعد الذهبية**:

1. **شرط الظهور قائم على بيانات العنصر نفسه** — تُحدَّد عبر دالة محلية مثل
   `_canReturnInvoice(Invoice)` تأخذ بعين الاعتبار **حالة الكيان** (مرتجع/سند/إلخ).
   لا يظهر الزر إلا حين يكون الإجراء قابلاً للتنفيذ منطقياً.

2. **حجم متواضع** — `Icon` 14px + Text 11px بـ `FontWeight.w700` +
   حشوة `EdgeInsets.symmetric(horizontal: 10, vertical: 7)`.

3. **اللون مستمد من `AppSemanticColors`** — للترجيع `danger`، للموافقة
   `success`، للتعليق `warning`. خلفية بنفس اللون بـ `alpha: 0.10` ⇒
   إشارة بصرية ناعمة لا تطغى على باقي البطاقة.

4. **`Material + InkWell` داخل `Material + InkWell` آخر** —
   الطبقة الداخلية تستهلك الـ tap، ولا يصعد لـ `InkWell` الأم
   (الذي يتولّى الـ `onTap` الرئيسي للبطاقة).

5. **Tooltip إجباري** — لتوضيح المعنى عند الـ hover على الديسكتوب.

6. **يحلّ محل `chevron`** عند توفّره — البطاقة تنتهي إما بـ "Action Pill" أو
   بـ `chevron_left` (في RTL)، لا الاثنين معاً، لتفادي الازدحام البصري.

**التطبيق المرجعي** — قواعد منع الإرجاع المعتمدة (Invoice):

| الحالة | الإرجاع | السبب |
|---|---|---|
| `isReturned == true` | ❌ | لا يُرتجع مرتجع |
| `originalInvoiceId != null` | ❌ | الفاتورة نفسها فاتورة ترجيع |
| `type == debtCollection` | ❌ | سند قبض، ليس بيعاً |
| `type == installmentCollection` | ❌ | سند قبض قسط |
| `type == supplierPayment` | ❌ | سند دفع مورد |
| كل البنود `isService=1` (بحتة خدمات) | ❌ | الخدمة قُدّمت، لا يمكن إرجاعها مادياً |
| فاتورة مختلطة (سلع + خدمات) | ✅ | تظهر، ويختار المستخدم السلع في شاشة الترجيع |
| `cash/credit/installment/delivery` بسلع | ✅ | المسار الطبيعي |

```dart
bool _canReturnInvoice(Invoice inv, Set<int> serviceProductIds) {
  if (inv.isReturned) return false;
  if (inv.originalInvoiceId != null) return false;
  switch (inv.type) {
    case InvoiceType.cash:
    case InvoiceType.credit:
    case InvoiceType.installment:
    case InvoiceType.delivery:
      break;
    case InvoiceType.debtCollection:
    case InvoiceType.installmentCollection:
    case InvoiceType.supplierPayment:
      return false;
  }
  // كل البنود خدمات ⇒ لا إرجاع.
  if (inv.items.isNotEmpty &&
      inv.items.every((it) =>
          it.productId != null &&
          serviceProductIds.contains(it.productId))) {
    return false;
  }
  return true;
}
```

**ملاحظة Performance**: تُحسب `serviceProductIds` مرة واحدة في
`build()` الرئيسي عبر `context.watch<ProductProvider>()`، ثم تُمرَّر إلى
`_InvoiceList → _InvoiceCard`. الفحص لكل بطاقة فاتورة يصبح **O(items)**
مع lookup ثابت `O(1)` لكل بند.

مرجع الكود: `lib/screens/invoices/invoices_screen.dart` → `_canReturnInvoice` و `_ReturnActionPill`.

### 9.3 Form Pattern

```dart
return AdaptiveScaffold(
  appBar: AppBar(title: const Text('إضافة عميل')),
  body: SingleChildScrollView(
    padding: EdgeInsets.all(AppSpacing.lg),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(/* ... */),
              SizedBox(height: AppSpacing.md),
              TextFormField(/* ... */),
              SizedBox(height: AppSpacing.xl),
              FilledButton(onPressed: _save, child: const Text('حفظ')),
            ],
          ),
        ),
      ),
    ),
  ),
);
```

في الديسكتوب، يُلفّ في `Row` مع عمود ثاني للمعلومات السياقية (recent customers, hints).

> **تطبيق فعلي (Phase 4)**: راجع `lib/widgets/adaptive/adaptive_form_container.dart` —
> ودجت موحّدة `AdaptiveFormContainer` تُغلِّف هذا النمط بـ getter متجاوب يفعّل القيد فقط على `tabletLG+`.
>
> ```dart
> Scaffold(
>   appBar: AppBar(title: const Text('إضافة عميل')),
>   body: AdaptiveFormContainer(
>     child: Form(key: _formKey, child: ListView(...)),
>   ),
> )
> ```
>
> طُبِّقت في 4 نماذج في Phase 4: `customer_form_screen.dart`، `service_order_form_screen.dart`،
> `add_service_screen.dart`، `add_installment_plan_screen.dart`. شاشة `user_form_screen.dart`
> تستخدم نسخة يدوية مكافئة من قبل (مقبولة كاستثناء).

### 9.4 POS Pattern

```dart
final variant = context.screenLayout.layoutVariant;
final isMobile = variant == DeviceVariant.phoneXS || variant == DeviceVariant.phoneSM;

return AdaptiveScaffold(
  appBar: AppBar(title: const Text('بيع جديد')),
  body: isMobile
    ? const _MobilePosTabs()  // Tabs(منتجات | عربة)
    : Row(
        children: [
          Expanded(flex: 2, child: _ProductsGrid()),
          const VerticalDivider(width: 1),
          SizedBox(width: 360, child: _CartPanel()),
        ],
      ),
);
```

> ملاحظة: في POS لا نستخدم `MasterDetailLayout` لأن العلاقة ليست “عنصر مختار”، بل “عملية بناء فاتورة”.

### 9.5 Settings Pattern

```dart
final variant = context.screenLayout.layoutVariant;
final useSideTabs = variant.index >= DeviceVariant.tabletSM.index;

return AdaptiveScaffold(
  appBar: AppBar(title: const Text('الإعدادات')),
  body: useSideTabs
    ? Row(
        children: [
          SizedBox(width: 240, child: _SettingsSideTabs(
            selected: _section,
            onChanged: (s) => setState(() => _section = s),
          )),
          const VerticalDivider(width: 1),
          Expanded(child: _SettingsContent(section: _section)),
        ],
      )
    : ListView(children: _allSettingsItems),
);
```

### 9.6 Detail Pattern

```dart
return AdaptiveScaffold(
  appBar: AppBar(title: Text(product.name)),
  body: Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: ListView(
        padding: EdgeInsets.all(AppSpacing.lg),
        children: [/* product details */],
      ),
    ),
  ),
);
```

### 9.7 AppBar Consolidation Pattern (HomeUserMenu)

**المشكلة الشائعة**: AppBars الشاشات الكبيرة تتراكم بأيقونات (إعدادات، مظهر، تحرير، حاسبة، خروج، ملف شخصي...) فيرتفع العبء الذهني (Cognitive Load) ويضيق الـ AppBar في الموبايل.

**القاعدة الذهبية (2026-05)**: في الـ AppBar **خارج القائمة المنسدلة** تبقى **3 إلى 4 أيقونات فقط كحدّ أقصى** — وكلها يجب أن تكون "حالات ديناميكية فعلية للنظام":
- ✅ مسموح خارجاً: إشعارات (شارة عدّاد)، تزامن (شارة خطأ)، حالة وردية، عناصر تخصّ النطاق الفعلي للشاشة.
- ❌ ممنوع خارجاً: إعدادات، مظهر، حاسبة، تخصيص واجهة، خروج، ملف شخصي — كلها داخل القائمة المنسدلة.

**الـ Pattern المرجعي** (مأخوذ من `home_screen.dart` بعد Pilot 1-ج/د):

```dart
List<Widget> _buildAppBarActions(BuildContext context, ...) {
  return [
    _shiftStatusButton(),       // حالة ديناميكية: يظهر فقط عند فتح وردية
    _syncStatusButton(),        // حالة ديناميكية: شارة خطأ عند الفشل
    _notificationsButton(),     // حالة ديناميكية: عدّاد غير المقروء
    _userMenuButton(...),       // كل الباقي
  ];
}
```

**`_userMenuButton`** = `HomeUserMenu` widget (`lib/widgets/adaptive/home_user_menu.dart`)
يقدم:
- شكلين حسب الـ DeviceVariant: أيقونة فقط (compact) أو أيقونة + اسم + سهم (wide).
- محتوى منسدل ديناميكي: يخفي/يظهر الخيارات حسب الفئة (مثلاً Mac panel على الديسكتوب فقط، Edit modules على tabletLG+ فقط).

**عند ترحيل أي شاشة بـ AppBar مكتظ، اتّبع الـ pattern ذاته**:
1. عدّ الأيقونات الحالية.
2. صنّف كل واحدة: "حالة ديناميكية" أم "إجراء/إعداد"؟
3. الحالات الديناميكية تبقى مرئية. الإجراءات والإعدادات تذهب لـ `PopupMenuButton` واحد بأيقونة `Icons.more_vert` أو `Icons.account_circle` (إذا تضمّن خيارات حساب).

---

### 9.8 Workspace Two-Pane Pattern (مختلف عن Master-Detail)

نمط لشاشات الـ **Workspace** التي تعرض موضوعاً واحداً (فاتورة، طلب، أمر شراء) مع
أصناف متعدّدة وملخّص فوري — مثل: `process_return_screen.dart`، `add_invoice_screen.dart`،
شاشات الـ POS، Builder forms.

#### الفرق عن `MasterDetailLayout`

| المعيار | `MasterDetailLayout` (§5.7 و §9.2) | **Workspace Two-Pane** (الجديد) |
|---|---|---|
| عدد العناصر في القائمة | متعدّد (فواتير، عملاء، ديون) | **عنصر واحد** (الفاتورة الجاري إرجاعها) |
| الـ side panel | تفاصيل العنصر **المختار** | **إجراءات/ملخّص** على نفس العنصر |
| تفاعل القائمة | تختار عنصراً ⇒ يفتح في اليسار | كلا الجانبَين يعملان معاً دائماً |
| `selectedItemId` | مطلوب | غير ذي معنى |
| التطبيق المرجعي | `invoices_screen.dart`, debts, customers | `process_return_screen.dart` |

**استعمال `MasterDetailLayout` لـ Workspace = إساءة استخدام**. هو مُصمَّم لـ list+detail
حيث الجانب الأيسر "يُفعَّل" باختيار عنصر من اليمين.

#### القواعد الذهبية

1. **الجانب الأيمن (`Expanded`)**: المحتوى الأساسي القابل للـ scroll (قائمة الأصناف،
   حقول الفورم الكبيرة).
2. **الجانب الأيسر (`SizedBox(width: 400)`)**: عرض ثابت — **لا** نسبي. يضمن
   ألا تتمدّد لوحة الإجراءات على شاشات 4K (تصبح 850px مهدورة لو استعملت `Flex`).
3. **`VerticalDivider(width: 1)`**: فاصل بصري ناعم بين اللوحتَين.
4. **اللوحة اليسرى = `SingleChildScrollView`**: لأن المحتوى قد يتجاوز ارتفاع
   الشاشة على ارتفاعات صغيرة.
5. **الزر الأساسي (تأكيد/حفظ) يبقى داخل اللوحة اليسرى**: لا في AppBar ولا
   عائماً (FAB) — اتّساقاً مع نمط ERP.
6. **في الموبايل (`!isWideVariant`)**: اللوحة اليسرى تتحوّل إلى **`bottomNavigationBar`**
   (Sticky Footer مع `Material(elevation: 8)`)، والقائمة في `body`.

#### القالب المرجعي

```dart
@override
Widget build(BuildContext context) {
  final isWide = context.screenLayout.isWideVariant;
  final summaryPanel = _ReturnSummaryPanel(...);
  return Scaffold(
    appBar: ...,
    body: isWide
        ? _buildWideBody(...)        // Row(Expanded(items), SizedBox(400, summary))
        : _buildNarrowBody(...),     // Column(barcode, header, Expanded(items))
    bottomNavigationBar: isWide
        ? null
        : Material(
            color: scheme.surface,
            elevation: 8,
            child: summaryPanel,     // نفس اللوحة، موضع مختلف
          ),
  );
}
```

#### تفاصيل الـ Sticky Footer على الموبايل

اللوحة في `bottomNavigationBar` يجب أن تحوي:
- **الـ Refund/Total الرئيسي فقط** + **زر التأكيد**.
- لا تضع تفاصيل ثانوية (خصم/ضريبة) في الـ footer لأنها تخنق القائمة (≥ 180px).
- تفاصيل الحساب الكامل تبقى ضمن الـ scroll body فوق الـ footer.

#### قواعد الـ Touch Target للأزرار +/-

| الفئة | حجم الأيقونة | Padding | Touch Target |
|---|---|---|---|
| `phoneXS/SM` | 22px | 8 | 38dp |
| `tabletSM/LG` | **26px** | **12** | **50dp** ✅ معيار 48dp |
| `desktopSM/LG` | 22px | 8 | 38dp (الفأرة دقيقة) |

التابلت يحصل على تكبير لأنه الأكثر استعمالاً كـ POS لمسي ميداني.

#### Quick Action: "إرجاع كامل" / "Add All to Cart"

في رأس قسم الأصناف، **TextButton صغير** لتنفيذ الإجراء الجماعي:
- `disabled` عندما لا يوجد ما يُضاف (مثلاً كل الكميات بالحد الأقصى أصلاً).
- **مُتعمَّد الضغط**: TextButton.icon صغير، **ليس** زراً ضخماً قرب التأكيد —
  لتفادي الضغط بالخطأ.
- لا حاجة لـ Confirmation Dialog لأن الإجراء قابل للتراجع يدوياً.

#### أمثلة موجودة في الكود

| الشاشة | الحالة |
|---|---|
| `process_return_screen.dart` | ✅ التطبيق المرجعي (Pilot Workspace Two-Pane) |
| `add_invoice_screen.dart` | تستحق الترقية لـ Two-Pane لاحقاً |
| شاشات الـ POS | تستحق الترقية لـ Two-Pane لاحقاً |

---

### 9.8.1 Cumulative-Returns Guard (حصاد الإرجاع التراكمي)

**الـ Bug التجاري المُصلَح:** قبل هذا التعديل كان بإمكان الكاشير إنشاء عدة
فواتير مرتجع متتالية لنفس الفاتورة الأصلية، وكل واحدة تُرجع نفس البند بكامل
كميته المباعة (مثال موثَّق: منتج بسعر 8,000 د.ع كميته الأصلية = 1 تم إرجاعه
3 مرات → خروج 24,000 د.ع من الصندوق ومن المخزون 3 وحدات وهمية).

**القاعدة التجارية الذهبية:**

> الكمية القابلة للإرجاع لأي بند = ‏الكمية المباعة − ‏مجموع ما أُرجع سابقاً
> عبر **كل** فواتير المرتجع التي `originalInvoiceId = X AND isReturned = 1`.

**التطبيق على ثلاث طبقات (Defense in Depth):**

| الطبقة | الموقع | الآلية |
|---|---|---|
| 1. Data Load | `_applyInvoice()` | استعلام مُجَمَّع `SUM(enteredQty)` من `invoice_items` للفواتير المرتجعة، يُحقن في كل `_LineReturn.alreadyReturnedEnteredQty`. مفتاح التجميع: `productId` أساسياً، `name|price` كـ Fallback للبنود اليدوية. |
| 2. UI Clamp | `onQuantityChanged` و `_setAllToMax` | الحد الأعلى = `maxReturnableEnteredQty = soldEnteredQty − alreadyReturned`. زر `+` يُعطَّل عند الوصول. |
| 3. Submit Guard | `_submitReturn()` | **يُعيد** الاستعلام لحظة الضغط (`_refetchAlreadyReturnedQtys`) — يحمي من race-condition مع شاشات أخرى/مستخدمين متوازين. |

**عناصر الـ UI:**

- شارة **`مُرجَع بالكامل`** (سيمانتك `success`) أو **`مُرجَع جزئياً`** (سيمانتك `warning`) داخل البطاقة.
- البطاقة المُرجَعة بالكامل تُعرض بـ `Opacity 0.6` + خلفية رمادية + كل الأزرار `disabled`.
- بانر علوي `_FullyReturnedBanner` لو **كل** بنود الفاتورة مُرجَعة بالكامل سابقاً.
- سطر تشخيصي تحت سعر البند يُظهر `مُرجَع سابقاً: X • المتبقي: Y`.

**ما لا يُغطى هنا** (قابل للتوسيع لاحقاً):

- التحقق على مستوى قائمة الفواتير (`invoices_screen`) — يتطلب جلب المرتجعات لكل فاتورة مرئية. القرار: تأجيل لتفادي N+1 query؛ شاشة المرتجع نفسها كافية لمنع الخطأ الفعلي.

---

## 10. خريطة الطريق ومتتبع الحالة

### 10.1 المراحل (Phases)

| المرحلة | المحتوى | الحالة |
|---|---|---|
| **استباقية** | Routes inventory + ScreenLayout extension + AppSpacing + AppTypography | ✅ مكتملة |
| **1** | المكونات المركزية (AdaptiveScaffold, MasterDetail, SearchBar) + Pilot home_screen | ✅ مكتملة (Pilots 1-أ/ج/د/هـ) — 1-ب مسجَّل كاستثناء |
| **2** | باقي شاشات Core & Auth (splash, login, signup) | ✅ مكتملة |
| **3-أ** | `cash/` (نقطة البيع) | ☑ مكتملة — `add_invoice_screen.dart` (5927 سطر) خالٍ تماماً من `isHandsetForLayout`؛ `cash_screen.dart` سليم |
| **3-ب** | `invoices/` (الفواتير) | ☑ مكتملة — List Pattern + Settings مهجَّرتان من `isHandsetForLayout` إلى `DeviceVariant` |
| **3-ج** | `inventory/` (المخزون) | 🔄 جزئياً — Hub مُرحَّل، List/Form سليمة معمارياً |
| **4** | services, reports, debts, installments, users, customers | ☑ مكتملة — Forms ⇐ `AdaptiveFormContainer` على شاشات `tabletLG+`؛ بقية الشاشات Compliant by Default |
| **5** | settings, tools, printing, shift, expenses, onboarding | ☑ مكتملة — 4 ملفات مهجَّرة من `isHandsetForLayout` إلى `isPhoneVariant`؛ بقية الشاشات Compliant |

### 10.1.1 سجل الـ Pilots داخل المرحلة 1

| الـ Pilot | المحتوى | الحالة |
|---|---|---|
| **1-أ** | استبدال `kWideBreakpoint` بـ `DeviceVariant` + حذف QuickActions + إدراج `ShiftPermissionBanner` | ✅ |
| **1-ب** | استبدال `_buildSearchBar` بـ `AdaptiveSearchBar` | 🚫 **استثناء معتمد** — راجع §10.3 |
| **1-ج** | بناء `HomeUserMenu` (PopupMenu موحّد) | ✅ |
| **1-د** | تقليص أيقونات الـ AppBar من 7 إلى 4 (Shift + Sync + Notifications + UserMenu) | ✅ |
| **1-هـ** | نقل قرار `useFluidLayout` في `dashboard_view.dart` و توزيع `HomeGlanceOrbit` إلى `DeviceVariant` | ✅ |

### 10.2 متتبع الشاشات (Per-Screen Tracker)

> يُحدّث مع كل ترحيل. مفتاح الرموز: ☑ مكتمل، 🔄 قيد، ⏳ منتظر.

| الشاشة | الفئة | المرحلة | الحالة | PR |
|---|---|---|---|---|
| `home_screen.dart` | Dashboard | 1 (Pilot — Hybrid) | ☑ (1-أ/ج/د/هـ) — Search ⇒ استثناء | — |
| `splash_screen.dart` | Detail | 2 | ☑ (logo scale ⇐ DeviceVariant) | — |
| `login_screen.dart` | Form (Auth) | 2 | ☑ (isWide ⇐ DeviceVariant.tabletLG) | — |
| `signup_screen.dart` | Form (Auth) | 2 | ☑ (isWide ⇐ DeviceVariant.tabletLG) | — |
| `cash_screen.dart` | POS | 3-أ | ☑ (سليمة — استخدام `MediaQuery.sizeOf` للارتفاع في empty-state صحيح فيزيائياً) | — |
| `add_invoice_screen.dart` | POS | 3-أ | ☑ (4 مواقع مهجَّرة: `_canUseEmbeddedScanner`, `Form body`, `_showWideQuickProductRail` ⇐ `DeviceVariant.tabletLG+`, `embedCheckoutInScroll`؛ ثابت `_kWideQuickProductRailMinWidth=800` محذوف) | — |
| `invoices_screen.dart` | List | 3-ب | ☑☑ **Golden Pilot** — `MasterDetailLayout` على `tabletLG+` + `AppSemanticColors` + Keyboard Shortcuts (`Ctrl+N`, `Ctrl+F`, `Esc`) + AppBar consolidation للهواتف | — |
| `sale_pos_settings_screen.dart` | Settings | 3-ب | ☑ (`showWideSaleLayoutControls` ⇐ `variant ∉ {phoneXS, phoneSM}`) | — |
| `parked_sales_screen.dart` | List | 3-ب | ☑ (سليمة — استخدام واحد `c.maxWidth < 560` داخل `LayoutBuilder` لقرار fit) | — |
| `process_return_screen.dart` | Form | 3-ب | ☑☑ **Workspace Two-Pane Pilot + Cumulative-Returns Guard** (§9.8 + §9.8.1) — منع إرجاع نفس البند مراراً عبر استعلام تجميعي + UI clamp + race-condition guard في `_submitReturn` + شارات `مُرجَع كلياً/جزئياً` + بانر `_FullyReturnedBanner` | — |
| `inventory_screen.dart` (Hub) | Dashboard | 3-ج | ☑ (`crossAxisCount` ⇐ `_gridColumnsFor(context)` للـ `_StatsBar` + `_ModulesGrid`) | — |
| `inventory_products_screen.dart` | List | 3-ج | ☑ (سليمة — `c.maxWidth` كلها قرارات fit داخلية صحيحة، `isNarrowWidth` ≡ phoneXS) | — |
| `add_product_screen.dart` | Form | 3-ج | ☑ (سليمة — `ConstrainedBox(maxWidth: 1200/1600)` + `c.maxWidth` للـ fit الداخلي للأقسام) | — |
| `services_hub_screen.dart` | Dashboard | 4 | ☑ (Compliant — Hub بسيط بدون مخالفات) | — |
| `service_orders_hub_screen.dart` | Dashboard | 4 | ☑ (Compliant — لا breakpoints) | — |
| `service_order_form_screen.dart` | Form | 4 | ☑ (⇐ `AdaptiveFormContainer`) | — |
| `service_order_detail_screen.dart` | Detail | 4 | ☑ (Compliant — Detail سائل) | — |
| `add_service_screen.dart` | Form | 4 | ☑ (⇐ `AdaptiveFormContainer`) | — |
| `reports_screen.dart` | Dashboard | 4 | ☑ (Compliant — `pageHorizontalGap` فيزيائي صحيح؛ لا breakpoints معمارية) | — |
| `debts_screen.dart` | List | 4 | ☑ **Golden 7** (TabController + Shortcuts Ctrl+F/F5/Esc + AppSemanticColors ×11 + `_DebtActionPill` ×2 + إبراز البطاقة المختارة في Tab 1) | — |
| `supplier_detail_screen.dart` | Detail | 4 | ☑ (Compliant) | — |
| `customer_debt_detail_screen.dart` | Detail | 4 | ☑ (Compliant) | — |
| `debt_settings_screen.dart` | Settings | 4 | ☑ (Compliant) | — |
| `installments_screen.dart` | List | 4 | ☑ (Compliant — List سائل) | — |
| `installment_details_screen.dart` | Detail | 4 | ☑ (Compliant) | — |
| `add_installment_plan_screen.dart` | Form | 4 | ☑ (⇐ `AdaptiveFormContainer`) | — |
| `installment_settings_screen.dart` | Settings | 4 | ☑ (Compliant) | — |
| `customers_screen.dart` | List | 4 | ☑ **Golden 7** (Shortcuts Ctrl+N/F/F5/Esc + `_CustomersStatsBar` 4 KPIs + `_CustomerActionPill` ×3 + MasterDetailLayout على wide + AppSemanticColors ×19 + إبراز البطاقة المختارة) | — |
| `customer_form_screen.dart` | Form | 4 | ☑ (⇐ `AdaptiveFormContainer`) | — |
| `customer_financial_detail_screen.dart` | Detail | 4 | ☑ **Golden 7** (extracted body → `customer_financial_detail_panel.dart` لإعادة الاستخدام في MasterDetail) | — |
| `customer_financial_detail_panel.dart` | Panel | 4 | ☑ **جديد** (Reusable Detail Panel — يقبل `CustomerRecord?` و `onClose`/`onEdit`، مع Empty State + reload عند تغيير العميل) | — |
| `customer_contacts_screen.dart` | List | 4 | ☑ (Compliant) | — |
| `users_screen.dart` | List | 4 | ☑ (Compliant) | — |
| `user_form_screen.dart` | Form | 4 | ☑ (يستخدم نمط `Center+ConstrainedBox(720)` يدوياً — مقبول كاستثناء، يطبّق على `tabletSM+` بدلاً من `tabletLG+`) | — |
| `staff_shifts_week_screen.dart` | Detail | 4 | ☑ (Compliant) | — |
| `employee_identity_screen.dart` | Detail | 4 | ☑ (Compliant) | — |
| `settings_screen.dart` | Settings | 5 | ☑ (`_MacStyleSettingsPanelTile` ⇐ `!isPhoneVariant`) | — |
| `market_pos_import_screen.dart` | Settings | 5 | ☑ (Compliant) | — |
| `dashboard_layout_settings_screen.dart` | Settings | 5 | ☑ (Compliant) | — |
| `calculator_screen.dart` | Tools | 5 | ☑ (Compliant — 60 سطر، شاشة بسيطة) | — |
| `printing_screen.dart` | Settings | 5 | ☑ (Compliant) | — |
| `open_shift_screen.dart` | Form | 5 | ☑ (`compact` + `horizontalPadding` ⇐ `isPhoneVariant`) | — |
| `close_shift_dialog.dart` | Dialog | 5 | ☑ (Compliant) | — |
| `work_shifts_calendar_screen.dart` | Detail | 5 | ☑ (Compliant) | — |
| `staff_qr_scan_screen.dart` | Tool | 5 | ☑ (Compliant) | — |
| `expenses_screen.dart` | List | 5 | ☑ **Golden 7** (AppBar Consolidation: 3 FABs → 1 FAB + AppBar overflow على phone + `_ExpensesStatsBar` 4 KPIs + AppSemanticColors ×9 + Esc shortcut) | — |
| `business_setup_wizard_screen.dart` | Wizard | 5 | ☑ (`compact` + `horizontalPadding` ⇐ `isPhoneVariant`) | — |
| `barcode_input_launcher.dart` (widget) | Utility | 5 | ☑ (`compact` overlay ⇐ `isPhoneVariant`) | — |

> القائمة غير شاملة. تُضاف باقي الشاشات بالتدريج عند الوصول إليها.

### 10.3 سجل الاستثناءات المعتمدة (Registered Exceptions)

أي شاشة/مكوّن لا يُحوَّل إلى ودجت Adaptive عامة **يجب** أن يُسجَّل هنا بسبب موثّق.
هذا يمنع تكرار النقاش لاحقاً ويعطي المراجعين سياقاً واضحاً.

#### 10.3.1 `_buildSearchBar()` في `home_screen.dart` — لا يُستبدل بـ `AdaptiveSearchBar`

- **القرار**: يبقى `_buildSearchBar()` كودًا متخصصًا داخل `home_screen.dart`.
- **التاريخ**: 2026-05
- **السبب التقني**:
  1. زر الباركود (`_scanFromDashboardSearch`) جزء أصيل من بحث الشاشة الرئيسية.
  2. لوحة المفاتيح الافتراضية (`VirtualKeyboardController`) خصوصية محلية لكاشير عراقي، تتفاعل مع `readOnly` ديناميكياً عند تثبيت اللوحة.
  3. النص البديل القصير/الطويل، زر المسح، الانطواء التلقائي في `PopupMenu` عند `width < 400` — كلها سلوكيات بحث رئيسية لا تنطبق على شاشات الفلاتر البسيطة.
- **البديل المقبول**: ضمان أن المنطق المتجاوب داخله يقرأ `context.screenLayout.layoutVariant` بدل breakpoints رقمية (تم).
- **`AdaptiveSearchBar` يُستخدم في**: شاشات بحث بسيط (المخزون، العملاء، التقارير، الموظفون).

#### 10.3.2 `home_screen.dart` لا يلتزم بـ `AdaptiveScaffold` كلياً (Hybrid Migration)

- **القرار**: تبقى `_buildBottomNavBar` و`_buildPersistentSidebar` و الـ inner `Navigator` خاصة بالشاشة الرئيسية.
- **التاريخ**: 2026-05
- **السبب التقني**:
  1. الـ BottomNav يدعم ميزات لا يوفرها `AdaptiveScaffold` العام: إعادة الترتيب بالسحب، Glassmorphism، عناصر فرعية موسّعة (Sub-items)، شارات أعداد ديناميكية، فحوصات صلاحيات، Easter Egg لاسم الشركة.
  2. الـ Sidebar يحوي رأس مستخدم + Logout + أزرار توسيع/طي + شارات تنبيهات.
  3. الـ inner Navigator يحفظ مسار التنقل داخل المحتوى دون إعادة بناء الـ Shell.
- **ما تم Adopt من الدستور**:
  - `DeviceVariant.layoutVariant` (بدل `kWideBreakpoint = 800`).
  - `ShiftPermissionBanner` (بدل البانر اليدوي).
  - `HomeUserMenu` (بدل 6 أزرار منفصلة + DarkMode toggle).
  - حذف ميزة `QuickActions` بالكامل (~430 سطراً).

---

## 11. الممنوعات المطلقة

### 11.1 ممنوعات تخطيط

| ❌ ممنوع | ✅ البديل |
|---|---|
| `if (size.width < 600)` يدوي | `context.screenLayout.isPhoneXS` |
| `if (MediaQuery.of(ctx).size.width < 1024)` | `context.screenLayout.isDesktopSM` |
| `enum ScreenType` جديد | `DeviceVariant` الموجود |
| ملف `AppBreakpoints` جديد | `screen_layout.dart` فقط |
| `sl.isHandsetForLayout` للقرارات المعمارية | `sl.isPhoneVariant` (Composite Helper) |
| `variant == phoneXS \|\| variant == phoneSM` متكرر | `sl.isPhoneVariant` (مختصر و قابل للقراءة) |
| `variant.index >= DeviceVariant.tabletLG.index` | `sl.isWideVariant` (مفيد لـ Master-Detail / Wide-Form) |

#### Composite Helpers — اختصارات معتمدة

| Helper | يكافئ | الاستخدام النموذجي |
|---|---|---|
| `isPhoneVariant` | `isPhoneXS \|\| isPhoneSM` | إخفاء عناصر / طيّ المحتوى للأجهزة الصغيرة |
| `isTabletVariant` | `isTabletSM \|\| isTabletLG` | تخطيطات وسطى |
| `isDesktopVariant` | `isDesktopSM \|\| isDesktopLG` | ميزات حصرية للديسكتوب (Mac Panel، Keyboard Shortcuts) |
| `isWideVariant` | `variant.index >= tabletLG.index` | Master-Detail، Wide-Form، شريط جانبي |

### 11.2 ممنوعات بصرية

| ❌ ممنوع | ✅ البديل |
|---|---|
| `Color(0xFF071A36)` | `AppColors.primary` |
| `Colors.blue` | `Theme.colorScheme.primary` |
| `Color(0xFF16A34A)` (success) | `AppSemanticColors.success` |
| `Color(0xFFF59E0B)` (warning/debt) | `AppSemanticColors.warning` |
| `Color(0xFFB45309)` (supplier) | `AppSemanticColors.supplier` |
| `Color(0xFFDC2626)` (danger) | `AppSemanticColors.danger` ⇒ يفضّل `Theme.colorScheme.error` |
| `BorderRadius.circular(30)` (بدون داعٍ) | `BorderRadius.zero` / `AppShape.none` |
| `fontSize: 18` | `AppTypography.sectionTitle(ctx)` |
| `EdgeInsets.all(16)` | `EdgeInsets.all(AppSpacing.lg)` |
| `fontFamily: 'Cairo'` | يأتي من الثيم تلقائيًا (Tajawal) |

### 11.3 ممنوعات معمارية

- تعديل `lib/services/**`, `lib/providers/**`, `lib/models/**`, `lib/navigation/**`.
- تغيير أسماء الـ Named Routes في `main.dart`.
- تغيير الـ URL Schemes للـ Deep Links.
- حذف Required Constructor Arguments من شاشات Detail.
- Find & Replace جماعي.
- ترك كود قديم بجانب الكود الجديد في نفس الملف.
- دمج شاشتين في PR واحد.

### 11.4 ممنوعات أداء

- `BackdropFilter` داخل `ListView.builder` كبير.
- `print()` / `debugPrint()` في كود الإنتاج.
- `MediaQuery.of(context).size` متكرر (استخدم `MediaQuery.sizeOf` أو `context.screenLayout`).
- `Directionality(textDirection: TextDirection.ltr)` إلا لمحتوى LTR أصيل.

---

## 12. الأسئلة الشائعة

**س: متى أستخدم `isHandsetForLayout` ومتى `isPhoneXS`؟**

`isHandsetForLayout` يعتمد على `shortestSide < 600` (مقياس مادي للجهاز) → استخدمه للقرارات المادية: حجم اللمس، فتح الكاميرا.

`isPhoneXS` يعتمد على `size.width < 360 || height < 600` (مقياس النافذة) → استخدمه للقرارات التخطيطية: عدد الأعمدة، نوع التنقل.

> مثال: تابلت في نافذة منبثقة 500×400 → `isPhoneXS = true` (تخطيطي)، `isHandsetForLayout = false` (مادي، لا يزال يحتاج لمس كبير).

---

**س: ماذا أفعل إذا اكتشفت خطأً معطلاً للبناء في طبقة مجمدة؟**

أصلح في PR منفصل قبل العودة لترحيل الشاشة. لا تدمج إصلاحًا تقنيًا مع ترحيل واجهة.

---

**س: شاشة تتفرع لـ 3 وحدات (مثل invoices: فواتير + مرتجعات + ملاحظات). كيف أرحلها؟**

اعتبر كل وحدة شاشة مستقلة (PR منفصل). الشاشة الأم (`invoices_hub_screen`) ترحل كـ Dashboard أو List حسب طبيعتها.

---

**س: المستخدم في الموبايل عنده 10 وحدات والشريط السفلي يأخذ 5. ماذا عن الباقي؟**

تذهب لـ BottomSheet عبر زر “المزيد”. هذا قرار UX مقصود (توصية Material Design).

---

**س: متى أبني `LoadingState` / `EmptyState` / `ErrorState`؟**

قبل البدء بأي شاشة تجلب بيانات. حاليًا غير مبنية، ستُبنى في PR مستقل.

---

**س: شريط البحث في الشاشة الرئيسية معقد جدًا (يحتوي virtual keyboard + debounce + 4 مصادر). هل أستخدم `AdaptiveSearchBar`؟**

`AdaptiveSearchBar` للحالات البسيطة. للحالات المعقدة، أنشئ ودجت متخصص يستخدم نفس البنية البصرية لكن منطقه الخاص.

---

**س: شاشة لديّ بحاجة سلوك Hover خاص. كيف أضمن أنه ينشط في الديسكتوب فقط؟**

```dart
final variant = context.screenLayout.layoutVariant;
final supportsHover = variant == DeviceVariant.desktopSM 
                    || variant == DeviceVariant.desktopLG;

if (supportsHover) {
  return MouseRegion(/* ... */);
}
return child; // بدون hover
```

---

**س: هل أحذف الكود القديم بعد كتابة الكود الجديد، أم في PR منفصل؟**

في **نفس الـ PR**. ممنوع أنماط مزدوجة. هذه قاعدة مطلقة.

---

## 13. المراجع وروابط الكود

### 13.1 الملفات الأساسية

| الملف | الدور |
|---|---|
| `lib/utils/screen_layout.dart` | `DeviceVariant` + `ScreenLayout` (المرجع الوحيد للمقاسات) |
| `lib/theme/design_tokens.dart` | `AppColors` + `AppShape` + `AppGlass` |
| `lib/theme/app_spacing.dart` | سلم المسافات (xs..xxl) |
| `lib/theme/app_typography.dart` | اختصارات التايبوغرافي الدلالية |
| `lib/utils/theme.dart` | ثيم Material مركزي (Tajawal) |

### 13.2 المكونات المتجاوبة

| الملف | الدور |
|---|---|
| `lib/widgets/adaptive/adaptive_scaffold.dart` | الإطار الخارجي |
| `lib/widgets/adaptive/adaptive_destination.dart` | عنصر تنقل (data class) |
| `lib/widgets/adaptive/master_detail_layout.dart` | نمط Master-Detail |
| `lib/widgets/adaptive/adaptive_search_bar.dart` | شريط بحث متجاوب |
| `lib/widgets/adaptive/adaptive.dart` | Barrel export |

### 13.3 وثائق المشروع

| الوثيقة | المحتوى |
|---|---|
| `docs/routes_inventory.md` | عقد المسارات والـ Deep Links |
| `docs/screen_migration_playbook.md` | **هذه الوثيقة** |
| `docs/migration_checklists/*.md` | جرد ميزات لكل شاشة (يُنشأ عند البدء) |
| `.cursor/rules/flutter-responsive-rtl.mdc` | قاعدة Cursor الفنية |

### 13.4 المراجع الخارجية

- [Material 3 Design](https://m3.material.io/)
- [Flutter Adaptive UI](https://docs.flutter.dev/development/ui/layout/adaptive-responsive)
- [Material 3 Navigation patterns](https://m3.material.io/components/navigation-bar/overview)

---

## ختاماً

هذه الوثيقة **هي الدستور**. أي تعارض بين سلوك مكتوب هنا وكود فعلي = الكود خاطئ ويجب إصلاحه.

التعديل على هذه الوثيقة يتطلب نقاشًا معماريًا صريحًا. لا تعدل بصمت.

**النية الواحدة الواضحة من كل هذا**: تطبيق يعمل بأناقة على كل حجم شاشة، بكود نظيف، بهوية موحدة، بدون ديون تقنية.

---

## 12. Brand DNA & Visual Identity (هوية بصرية موحَّدة)

> **الفلسفة**: شاشة البيع (`add_invoice_screen.dart`) كانت "وجه التطبيق" الجمالي
> (Navy + Gold + Inline Toast). أصبح ذلك الآن DNA موحَّد لكل الشاشات.

### 12.1 الـ Tokens الأساسية

ملف المصدر: `lib/theme/sale_brand.dart`

| Token | اللون | الاستخدام |
|---|---|---|
| `navy` | #152B47 | الـ AppBar، الأزرار الأساسية، خلفية Inline Toast |
| `gold` | #C9A85C | أيقونات actions، الحدود المميزة، شارات |
| `ivory` | #F7F4EF | خلفية لوحات الأقسام (light) |
| `ivoryDark` | #1A2433 | خلفية لوحات الأقسام (dark) |

### 12.2 الـ Palettes الجاهزة (User Preference)

8 ثيمات مُحدَّدة مسبقاً + Custom: `royal` (افتراضي)، `midnight`، `ocean`، `forest`، `wine`، `charcoal`، `slate`، `copper`، `custom`. يَختارها المستخدم من **إعدادات نقطة البيع** (سيُنقَل لاحقاً إلى إعدادات المظهر العامة).

### 12.3 Notification Strategy — `AppMessenger`

API موحَّد: `AppMessenger.show(context, message: ...)`.

| السياق | الإخراج |
|---|---|
| المستخدم فعَّل `useCompactSnackNotifications` (افتراضي) + الشاشة بها `AppInlineToastHost` | **Inline Toast** (Navy + Gold edge، فوق الـ footer، tap-to-dismiss) |
| Fallback | SnackBar (floating أو fixed حسب الإعداد) |

**Helpers جاهزة**:
- `AppMessenger.success(context, message: ...)` ← أيقونة check_circle
- `AppMessenger.error(context, message: ...)` ← أيقونة error_outline
- `AppMessenger.warning(context, message: ...)` ← أيقونة warning_amber

**Setup المطلوب لكل شاشة**:

```dart
return Scaffold(
  appBar: ...,
  bottomNavigationBar: const SafeArea(
    top: false,
    child: AppInlineToastBar(),  // ← مساحة محجوزة للـ toast
  ),
  body: ...,
).wrap(AppInlineToastHost(...));  // ← يَلف الـ Scaffold كاملاً
```

### 12.4 Section Title — `AppSectionTitle`

العنوان مع **الشريط الذهبي العمودي** + glow. يَستحق التطبيق على كل قسم في الشاشة:

```dart
AppSectionTitle(
  title: 'تفاصيل العميل',
  caption: 'البيانات الأساسية وأرقام الاتصال',
  trailing: IconButton(...),  // اختياري
  dense: false,                // true للقوائم المكدَّسة
)
```

ألوان النصوص contrast-aware آلياً:
- `title`: navy (light) / #F1EDE6 (dark)
- `caption`: navy.alpha(0.62) (light) / #CBD5E1 (dark)

### 12.5 Golden Panel — `AppGoldedPanel`

لوحة قسم بـ **حد ذهبي يميني سميك** + حدود رقيقة على الجوانب الثلاث الأخرى:

```dart
AppGoldedPanel(
  dense: false,           // true لقوائم كثيفة
  forceSharpCorners: false,
  child: Column(children: [
    AppSectionTitle(title: 'الإجمالي'),
    // محتوى القسم...
  ]),
)
```

- الخلفية: `ivory` (light) / `ivoryDark` (dark).
- الحد الأيمن: 3px (wide) / 2.5px (narrow) ذهبي.
- الحدود الباقية: edge subtle (navy.alpha(0.2) أو gold.alpha(0.4)).
- الزوايا: يَحترم `panelCornerStyle` للمستخدم (rounded أو sharp).

### 12.6 AppBar Branded (تلقائي)

`app_theme_resolver.dart` يُطبِّق Navy bg + White title + **Gold actions icons** تلقائياً عند `useSaleBrandSkin = true` (الافتراضي).

أي AppBar في التطبيق:
- `leading` (الرجوع/Drawer): أبيض.
- `actions` icons: ذهبية تلقائياً.
- Title: أبيض.

**استثناءات**: لو شاشة تَفرض `color: ...` صراحةً على `IconButton`، يَتجاوز هذا الإعداد.

### 12.7 Tracker للتطبيق

| الشاشة | AppBar Gold | Inline Toast | SectionTitle | GoldedPanel |
|---|---|---|---|---|
| `customers_screen.dart` | ✅ تلقائي | ✅ Pilot 1 | — | — |
| `debts_screen.dart` | ✅ تلقائي | ☐ | — | — |
| `expenses_screen.dart` | ✅ تلقائي | ☐ | — | — |
| `invoices_screen.dart` | ✅ تلقائي | ☐ | — | — |
| `add_invoice_screen.dart` | ✅ (المصدر) | ✅ (المصدر) | ✅ (المصدر) | ✅ (المصدر) |

### 12.8 Migration Guide لشاشة موجودة

1. **Import**: `import '../../widgets/brand/brand.dart';`
2. **AppInlineToastHost**: لُف الـ Scaffold الخارجي.
3. **AppInlineToastBar**: ضعه في `bottomNavigationBar` (مع SafeArea).
4. استبدل `ScaffoldMessenger.of(context).showSnackBar(...)` بـ `AppMessenger.show(...)`.
5. (اختياري) استبدل العناوين المكتوبة يدوياً بـ `AppSectionTitle`.
6. (اختياري) لُف البطاقات الكبرى بـ `AppGoldedPanel`.

### 12.9 Light/Dark Audit Checklist

كل widget جديد يَجب أن يَجتاز هذه الفحوص قبل المرجَعة:

- [ ] النصوص contrast ≥ 4.5:1 على الخلفية (WCAG AA).
- [ ] الأيقونات contrast ≥ 3:1 (للأيقونات الذهبية مع navy: ✅ بطبيعتها).
- [ ] الزوايا (rounded/sharp) تَحترم `panelCornerStyle`.
- [ ] الحدود الذهبية لا تَختفي في الـ dark mode (alpha ≥ 0.4 على gold).
- [ ] الـ shadows متوازنة (لا تَخلق نتوءات بصرية).

---

### 12.10 Button System (نظام الأزرار الكامل)

#### الأزرار الأساسية

| النوع | الاستخدام | المظهر | المرجع |
|---|---|---|---|
| **FilledButton** | الإجراء الأساسي (Save/Pay/Submit) | bg=navy، label=أبيض 700 وزن، icon=ذهبي، elevation=0 | `add_invoice_screen:1994` |
| **OutlinedButton** | الإجراء الثانوي (Park/Cancel) | side=gold 1.4px، foreground=navy (light) / ivory (dark)، icon=ذهبي | `add_invoice_screen:1986` |
| **TextButton** | إجراء خفيف داخل بطاقة (Edit link) | foreground=navy/gold، بدون حد | — |

```dart
// المثال المرجعي للزر الأساسي
FilledButton.icon(
  onPressed: ...,
  style: FilledButton.styleFrom(
    backgroundColor: palette.navy,
    foregroundColor: SaleAccessibleButtonColors.filledOnNavyLabel(),
    iconColor: SaleAccessibleButtonColors.filledOnNavyIcon(palette.gold),
    elevation: 0,
  ),
  icon: const Icon(Icons.payments_rounded),
  label: const Text('الدفع', style: TextStyle(fontWeight: FontWeight.bold)),
)
```

#### Choice Chip (طريقة الدفع، الفلاتر)

| الحالة | bg | border | label |
|---|---|---|---|
| **Selected** | `palette.navy` | gold 1.8px | أبيض 700 |
| **Unselected** | white (light) / #243047 (dark) | navy.alpha(0.28) 1px | navy/gold 500 |

```dart
ChoiceChip(
  selected: selected,
  selectedColor: palette.navy,
  backgroundColor: dark ? Color(0xFF243047) : Colors.white,
  side: BorderSide(
    color: selected ? palette.gold : palette.navy.withValues(alpha: 0.28),
    width: selected ? 1.8 : 1,
  ),
  showCheckmark: false,
  labelStyle: TextStyle(
    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
    fontSize: 13,
  ),
)
```

#### Action Pill (الأزرار المضغوطة في البطاقات)

النمط الذي تَستخدمه `_CustomerActionPill` و `_ReturnActionPill` و `_DebtActionPill`:

```dart
Material(
  color: color.withValues(alpha: 0.10),
  borderRadius: BorderRadius.circular(8),
  child: InkWell(
    onTap: ...,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    ),
  ),
)
```

#### Icon Pill (زر أيقونة في AppBar أو شريط)

```dart
AnimatedContainer(
  duration: Duration(milliseconds: 180),
  decoration: BoxDecoration(
    color: palette.navy.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: palette.gold.withValues(alpha: 0.22)),
  ),
  child: InkWell(
    onTap: ...,
    borderRadius: BorderRadius.circular(14),
    child: SizedBox(
      height: 44,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10),
        child: Icon(icon, size: 24, color: palette.gold),
      ),
    ),
  ),
)
```

---

### 12.11 Typography Scale (مقياس الخطوط)

| المستوى | الحجم | الوزن | letter-spacing | الاستخدام |
|---|---|---|---|---|
| **Display** | 24-28 | 800 | -0.4 | عناوين كبيرة (KPI، أرقام مالية بارزة) |
| **Title L** | 17 (wide) / 16 (narrow) | 800 | -0.2 | عنوان قسم (`AppSectionTitle`) |
| **Title M** | 15 | 800 | 0 | عنوان بطاقة، عنوان حوار |
| **Title S** | 13.5-14 | 700 | 0 | عنوان بند صغير |
| **Body L** | 13.5 | 600 | 0 | نص Inline Toast، نص أساسي |
| **Body M** | 13 | 500 | 0 | نص عادي |
| **Body S** | 12.5 | 500 | 0 | نص ثانوي |
| **Caption** | 11.5 (wide) / 11 (narrow) | 400-500 | 0 | تَوضيح تحت العنوان (line-height: 1.45) |
| **Micro** | 11 | 700 | 0 | شارات (badges)، Action Pill labels |

**قاعدة line-height**:
- عناوين: 1.25
- نص قراءة (caption/body): 1.35-1.45
- نص أرقام مالية: 1.15

**أوزان مسموحة**: 400 (regular), 500 (medium), 600 (semibold), 700 (bold), 800 (extrabold).
**لا تَستخدم 900 أو italic** — لا تَتناسب مع Brand DNA.

---

### 12.12 Semantic Notification Colors (الألوان الدلالية)

مصدر التعريف: `lib/theme/design_tokens.dart` → `AppSemanticColors`.

| المعنى | اللون | Hex | متى يُستخدم |
|---|---|---|---|
| **Success** | أخضر | `#16A34A` | تم الحفظ، تم الدفع، عملية ناجحة، badge "مدفوع" |
| **Warning** | برتقالي أصفر | `#F59E0B` | تنبيه ناعم، دين قيد الانتظار، "مُرجَع جزئياً" |
| **Supplier** | بنّي محاسبي | `#B45309` | فواتير مورد، تَحصيلات |
| **Danger** | أحمر | `#DC2626` | خطأ، حذف، إلغاء، badge "مرتجع كامل" |
| **Info** | أزرق | `#3B82F6` | معلومات، badge "ملاحظة"، "تم النسخ" |

**الـ AppMessenger يُطبِّقها آلياً**:
```dart
AppMessenger.success(context, message: 'تم الحفظ');  // ← خلفية خضراء
AppMessenger.error(context, message: 'فشل الحفظ');   // ← خلفية حمراء
AppMessenger.warning(context, message: 'كمية قليلة'); // ← خلفية برتقالية
AppMessenger.info(context, message: 'تم النسخ');      // ← خلفية زرقاء
AppMessenger.show(context, message: 'إشعار محايد');   // ← خلفية navy (Brand)
```

**استخدام في الـ Badges/Chips**:
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  decoration: BoxDecoration(
    color: AppSemanticColors.success.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: AppSemanticColors.success.withValues(alpha: 0.4)),
  ),
  child: Text('مدفوع', style: TextStyle(color: AppSemanticColors.success, fontWeight: FontWeight.w700)),
)
```

---

### 12.13 Golden Dividers & Lines (الخطوط الذهبية)

**القاعدة الذهبية**: الخط الذهبي يُستخدم **بشُح**. لا تَملأ الشاشة به — هو علامة (accent)، ليس زخرفة.

| الموضع | السماكة | alpha | المثال |
|---|---|---|---|
| Section Right Border (Panel) | 3 (wide) / 2.5 (narrow) | 1.0 | `_saleFlowPanel` |
| Section Title Vertical Bar | 4×46 (wide) / 3×42 (narrow) | 1.0 + glow 0.28 | `AppSectionTitle` |
| Footer Top Border | 1.5 | 0.55 | `_buildSaleCheckoutActionsFixedBar` |
| Toast Border | 1 | 0.45 | `AppInlineToastBar` |
| ChoiceChip Selected | 1.8 | 1.0 | `_paymentTypeChip` |
| OutlinedButton | 1.4 | 1.0 | "تعليق الفاتورة" |
| Icon Pill Border | 1 | 0.22 | `_saleScannerOpen` toggle |

**لا تَستخدم gold لـ**:
- خلفيات النصوص الطويلة (يُؤذي القراءة).
- حدود الـ TextField (يُربك مع focus state).
- أيقونة `leading` في AppBar (تبقى بيضاء — navigation).

---

### 12.14 Form Field Styling (حقول الإدخال)

نمط شاشة البيع للـ TextField (السطر 2179-2218):

```dart
TextField(
  style: TextStyle(fontSize: 13),
  decoration: InputDecoration(
    isDense: true,
    hintText: '...',
    hintStyle: TextStyle(fontSize: 12.5, color: muted),
    filled: true,
    fillColor: dark ? Color(0xFF334155).withValues(alpha: 0.35) : Colors.white,
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(
        color: dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.12),
      ),
    ),
  ),
)
```

**القواعد**:
- `isDense: true` لكل الحقول داخل البطاقات (يُوفر مساحة).
- `borderRadius: 8` — مستديرة لكن غير مبالغ فيها.
- `filled: true` دائماً (مع fillColor مناسب dark/light).
- حدود subtle (alpha ~0.12) — لا تَستخدم gold للحدود.
- على focus: تَترك Material 3 يَتولّى (يَستخدم primary من scheme = navy).
- `helperText` للإرشادات الطويلة (helperMaxLines: 2-3).
- `errorText` بلون `AppSemanticColors.danger` تلقائياً عبر theme.

---

### 12.15 Iconography & Sizes (الأيقونات والأحجام)

**أحجام موحَّدة**:

| السياق | الحجم |
|---|---|
| AppBar action | 22 |
| Icon Pill (Scanner toggle) | 24 |
| Card primary icon | 20-22 |
| List tile leading | 20 |
| Action Pill icon | 14 |
| Inline Toast icon | 20 |
| Section Title trailing button icon | 18-20 |
| Status badge icon | 14 |
| Quantity ± button | 22 (mobile/desktop) / 26 (tablet POS) |

**الألوان**:
- **افتراضي على navy bg**: `palette.gold`
- **افتراضي على ivory bg**: `palette.navy`
- **في Action Pill**: لون الـ semantic المرتبط (success/warning/danger/info)
- **في Form Field**: `colorScheme.onSurfaceVariant`

**Iconography Family**: استخدم **`_rounded`** variant افتراضياً (مثل `Icons.payments_rounded`)، لا `_outlined` ولا `_sharp` — يَتناسب مع DNA الناعم لـ Brand.

---

### 12.16 Sticky Footer / Bottom Bar

نمط `_buildSaleCheckoutActionsFixedBar`:

```dart
SafeArea(
  top: false,
  child: Material(
    color: colorScheme.surface,
    elevation: 10 (phone) / 4 (wide),
    shadowColor: palette.navy.withValues(alpha: 0.2),
    child: Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.gold.withValues(alpha: 0.55), width: 1.5),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // [Optional] AppInlineToastBar() هنا
            // [Required] الإجراءات (Pay button، Park button)
          ],
        ),
      ),
    ),
  ),
)
```

**القواعد**:
- **دائماً** ضمن `SafeArea(top: false)` لحماية إيماءة الـ home indicator (iOS).
- elevation 10 على الموبايل، 4 على الديسكتوب (الفصل البصري أقل لزوماً).
- الحد العلوي الذهبي **إلزامي** — يَفصل الـ footer عن المحتوى.
- مكان Inline Toast: داخل الـ footer **فوق** الأزرار (إن وُجد).

---

### 12.17 Banner Components (لوحات التَّنبيه الكبيرة)

البانر داخل الصفحة (ليس toast)، مثل `_FullyReturnedBanner` و `_BarcodeSwitchField`:

| النوع | bg | border | الأيقونة | متى |
|---|---|---|---|---|
| **Info** | `info.alpha(0.12)` | `info.alpha(0.4)` | `info_outline` | معلومة دائمة في الصفحة |
| **Warning** | `warning.alpha(0.12)` | `warning.alpha(0.45)` | `warning_amber_rounded` | تَنبيه يحتاج انتباه (مرتجع كامل) |
| **Success** | `success.alpha(0.12)` | `success.alpha(0.4)` | `check_circle_outline` | تأكيد دائم (تم الدفع) |
| **Error** | `danger.alpha(0.12)` | `danger.alpha(0.45)` | `error_outline_rounded` | خطأ يَستلزم تَدخّل |

```dart
Container(
  width: double.infinity,
  margin: EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: color.withValues(alpha: 0.45)),
  ),
  child: Row(
    children: [
      Icon(icon, color: color, size: 22),
      SizedBox(width: 12),
      Expanded(child: Text(message, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color, height: 1.5))),
    ],
  ),
)
```

**القواعد**:
- alpha 0.12 للخلفية + 0.4-0.45 للحد + 1.0 للنص/الأيقونة — تباين كافٍ.
- `Border.all` (وليس Border.symmetric) — البانر بإطار كامل.
- `borderRadius: 12` — أكبر قليلاً من البطاقات العادية.
- النص بـ `fontWeight: 700` ولون الحالة (ليس أبيض/أسود).

---

### 12.18 Card / Tile patterns (بطاقات السلة، القوائم)

```dart
AnimatedContainer(
  duration: Duration(milliseconds: 180),
  curve: Curves.easeOut,
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: ac.md, // = 12
    border: Border.all(
      color: active ? scheme.primary.withValues(alpha: 0.45) : scheme.outlineVariant,
      width: active ? 1.5 : 1,
    ),
    boxShadow: ac.isRounded ? [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.035),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ] : null,
  ),
  child: Padding(padding: EdgeInsets.all(14), child: ...),
)
```

**Active State** (تَمييز بطاقة محدَّدة):
- border يَتغيّر من `outlineVariant` → `primary.alpha(0.45)`.
- width يَتغيّر من 1 → 1.5.
- لا تُغيّر bg لتجنب الـ flickering.
- استخدم `AnimatedContainer` بـ 180ms.

**Disabled State** (مُرجَع بالكامل، إلخ):
- `Opacity(opacity: 0.6, child: ...)`
- bg → `surfaceContainerHighest.alpha(0.4)`
- أزرار +/- → `onPressed: null`

---

### 12.19 Spacing Rhythm (إيقاع المسافات)

**القاعدة الذهبية**: 4 → 6 → 8 → 10 → 12 → 14 → 16 → 18 → 22 → 24 → 28.
**لا تَستخدم** قيم عشوائية مثل 7, 11, 13 — هذا يَكسر الإيقاع.

| السياق | المسافة |
|---|---|
| داخل أيقونة + نص (Row gap) | 4-8 |
| بين عناصر داخل بطاقة | 6-10 |
| بين بطاقات | 10-12 |
| بين أقسام (Sections) | 16-22 |
| Page horizontal gap | 12 (phoneSM) / 16 (wide) — من `pageHorizontalGap` |
| Card internal padding | 13 (narrow) / 16 (wide) — من `_saleFlowPanel` |

---

### 12.20 Animation Standards (معايير الحركة)

| النوع | المدة | curve |
|---|---|---|
| Card active toggle | 180ms | `Curves.easeOut` |
| Section expand/collapse | 250ms | `Curves.easeInOut` |
| Toast fade in | 200ms | `Curves.easeOut` (Flutter default) |
| Modal/Dialog | 300ms | افتراضي Flutter |
| Hover (desktop) | 120ms | `Curves.linear` |

**لا تَستخدم**:
- `Curves.bounceOut` (مزعج في تطبيق ERP).
- `Curves.elasticOut` (نفس السبب).
- مدد > 400ms للتفاعلات الأساسية (يَشعر التطبيق بالبطء).

---

### 12.21 ✅ Checklist لتطبيق Brand DNA على شاشة موجودة

عند فحص أي صورة شاشة وطلب "طبّق الدستور عليها":

#### الفحوص البصرية (ترتيب الأولوية)

1. **AppBar**:
   - [ ] الأيقونات في `actions` ذهبية؟ (تلقائي عبر theme، تَحقق من عدم وجود override).
   - [ ] الـ `leading` (الرجوع) أبيض؟
   - [ ] الـ title أبيض بـ font weight 700+؟

2. **Section Titles**:
   - [ ] هل يوجد عنوان قسم بدون شريط ذهبي عمودي؟ ← استبدل بـ `AppSectionTitle`.
   - [ ] الـ caption alpha 0.62 navy / #CBD5E1 dark؟

3. **Cards/Panels**:
   - [ ] البطاقات الكبيرة (Section containers) تَستخدم `AppGoldedPanel` بـ حد ذهبي يميني؟
   - [ ] البطاقات الصغيرة (List items) تَستخدم `outlineVariant` border + radius 12؟

4. **Buttons**:
   - [ ] الأزرار الأساسية: Filled navy + white label + gold icon؟
   - [ ] الأزرار الثانوية: Outlined gold 1.4px + gold icon؟
   - [ ] الأزرار الصغيرة في بطاقات: `Action Pill` بلون semantic؟

5. **Notifications**:
   - [ ] هل يوجد `AppInlineToastHost` يَلف الـ Scaffold؟
   - [ ] هل يوجد `AppInlineToastBar` في `bottomNavigationBar`؟
   - [ ] هل كل `ScaffoldMessenger.of(context).showSnackBar` استُبدل بـ `AppMessenger.show/success/error/warning/info`؟

6. **Forms**:
   - [ ] الحقول بـ `isDense: true` + `borderRadius: 8` + `filled: true`؟
   - [ ] الـ helperText للحقول الحساسة (المقدّم، الفائدة، إلخ)؟

7. **Typography**:
   - [ ] العناوين بـ weight 800 + letter-spacing -0.2 لـ Title L؟
   - [ ] لا يوجد `Color.fromRGBO` أو `Colors.red/green/blue` صلب — كله من `AppSemanticColors` أو `palette`؟

8. **Spacing**:
   - [ ] المسافات من السلَّم: 4/6/8/10/12/14/16/18/22/24/28 فقط؟
   - [ ] `pageHorizontalGap` من `ScreenLayout` (ليس قيمة صلبة)؟

9. **Sticky Footer** (للشاشات بـ Pay/Save button):
   - [ ] `SafeArea(top: false)` ✅
   - [ ] حد ذهبي علوي 1.5px alpha 0.55 ✅
   - [ ] elevation 10 (phone) / 4 (wide) ✅

10. **Banners** (التَّنبيهات الكبيرة):
    - [ ] لون الحالة (success/warning/danger/info) + alpha 0.12/0.45 ✅
    - [ ] أيقونة + نص bold weight 700 ✅

#### الأشكال الرسومية الممنوعة

- ❌ Container بـ `color: Colors.red` مباشرة → استخدم `AppSemanticColors.danger`.
- ❌ AppBar بلون مختلف عن navy → احذف `backgroundColor`.
- ❌ نص بـ `fontWeight: w900` → غيِّر إلى w800.
- ❌ borderRadius عشوائي (مثل 11 أو 7) → استخدم 8/10/12/14.
- ❌ shadow بـ blurRadius > 12 → استخدم 4-8.
- ❌ Icons من `_outlined` بدل `_rounded` → استبدل (إلا في حالات الـ "خطورة" مثل error/warning).

---

> "خير المتاجر ما اتسعت أبوابه لكل عميل، وخير الواجهات ما اتسعت لكل شاشة، وخير الهوية ما اتَّحدت في كل قسم وكل زر وكل خط ذهبي."
