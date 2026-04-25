---
name: flutter-responsive-rtl
description: Flutter responsive layout, RTL, and desktop UX conventions for the Naboo / Basra Store Manager project. Use when building or modifying screens in lib/screens, reusable widgets in lib/widgets, theme files in lib/theme, or when the user asks about mobile/tablet/desktop layouts, RTL, Tajawal font, Provider state, empty/loading/error states, or keyboard shortcuts on Windows/macOS.
---

# واجهة Flutter — متجاوب وعصري (Naboo / Basra Store Manager)

> يُكمِّل هذا الـ skill قواعدَ `arabic-rtl.mdc` — لا تُكرّر ما هناك.
> المشروع: Flutter 3.11+ / `provider` (ليس Riverpod) / Locale `ar_SA`.

## المنصات المستهدفة
`android/` · `ios/` · `macos/` · `windows/` — نفس الكود لكل المنصات.
كل شاشة يجب أن تعمل على:
- موبايل  < 640px   → تخطيط عمودي، شريط سفلي عند اللزوم
- تابلت   640–1024px → `NavigationRail` على الجانب
- ديسكتوب > 1024px  → `Drawer` دائم + محتوى متعدد الأعمدة

> الحد الأدنى لنافذة الديسكتوب الذي يجب اختباره: 800×600.

## أدوات التخطيط الموجودة (لا تُعد كتابتها)

**`lib/utils/screen_layout.dart`** — الموسوم الفعلي للمشروع:

```dart
import '../../utils/screen_layout.dart';

final layout = context.screenLayout;
layout.isHandsetForLayout      // shortestSide < 600
layout.useWideSaleTwoColumnLayout // !handset && width >= 700
layout.pageHorizontalGap       // 10/12/16 حسب العرض
layout.sheetInitialFraction    // للـ DraggableScrollableSheet
```

للتقسيم الثلاثي (موبايل/تابلت/ديسكتوب):

```dart
@override
Widget build(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 640)  return _MobileLayout(data: data);
  if (w < 1024) return _TabletLayout(data: data);
  return _DesktopLayout(data: data);
}
```

**لا تُنشئ** `lib/core/utils/screen_type.dart` أو enum جديد — استخدم الموجود.

## RTL والأرقام
- RTL مُفعَّل تلقائياً عبر `Locale('ar', 'SA')` في `main.dart` — لا `Directionality` يدوي.
- التفاصيل في `arabic-rtl.mdc` (استخدم `EdgeInsetsDirectional`, `AlignmentDirectional`, ...).
- الأرقام: أرقام غربية (0-9) عبر `intl`؛ للعملة العراقية استخدم `lib/utils/iraqi_currency_format.dart`.
- التواريخ: `DateFormat.yMMMd('ar')` — لا تنسيق يدوي.

## حالات البيانات الثلاث (إلزامية في كل شاشة تجلب بيانات)

المشروع يستخدم `provider` — النمط:

```dart
Consumer<CustomersProvider>(
  builder: (context, prov, _) {
    if (prov.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (prov.error != null) {
      return _ErrorView(
        message: prov.error!,
        onRetry: () => prov.refresh(),
      );
    }
    if (prov.items.isEmpty) {
      return _EmptyView(
        icon: Icons.people_outline,
        label: 'لا يوجد عملاء بعد',
        action: TextButton(
          onPressed: onCreate,
          child: const Text('إضافة أول عميل'),
        ),
      );
    }
    return _CustomersList(items: prov.items);
  },
)
```

- لا يوجد `ErpLoadingWidget/ErpErrorWidget/ErpEmptyWidget` جاهزة — اكتب widget محلياً أو استخدم primitives.
- رسائل الخطأ بالعربية وواضحة للمستخدم (ليست stacktrace).

## الجداول والقوائم الكبيرة

```dart
// ✅ ListView.builder دائماً — لا children: [] لأكثر من ~10 عناصر
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, i) => CustomerCard(item: items[i]),
)
```

- بحث على جداول SQLite: debounce 300ms إلزامي قبل الاستعلام.
- جداول عريضة على الديسكتوب: `SingleChildScrollView(scrollDirection: Axis.horizontal)` حول `DataTable`.

## Material 3 والثيم

الثيم مُعرَّف مركزياً في:
- `lib/utils/theme.dart` — `AppTheme.lightTheme` / `darkTheme`
- `lib/theme/app_theme_resolver.dart` — يدمج إعدادات المستخدم (لون، خط، زوايا)
- `lib/theme/design_tokens.dart` — `AppColors.primary = 0xFF1E3A5F`

**قواعد:**
- لا ألوان `hardcoded` في الـ widgets:
  ```dart
  Theme.of(context).colorScheme.primary
  Theme.of(context).colorScheme.surface
  Theme.of(context).colorScheme.onSurfaceVariant
  ```
- الخط الافتراضي `Tajawal` (مُسجَّل في `pubspec.yaml`) — لا `fontFamily: 'Cairo'` في الـ widgets.
- المشروع يفضّل زوايا حادّة (`AppShape.none`). لا تُضف `BorderRadius.circular(N)` دون داعٍ.
- احترم `MediaQuery.of(context).disableAnimations`.

## خاص بالديسكتوب (Windows/macOS)

```dart
Shortcuts(
  shortcuts: {
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
      const CreateInvoiceIntent(),
    LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF):
      const FocusSearchIntent(),
    LogicalKeyboardKey.escape: const CloseDialogIntent(),
  },
  child: Actions(
    actions: { CreateInvoiceIntent: CreateInvoiceAction() },
    child: child,
  ),
)
```

- قوائم سياقية (right-click) على الجداول في الديسكتوب.
- تغيير عرض الأعمدة عند الإمكان.
- اختبر على نافذة 800×600 (الحد الأدنى لـ Windows).

## ما لا تفعله أبداً

- ❌ لا قيم عرض/ارتفاع ثابتة — `Flexible`, `Expanded`, `FractionallySizedBox`، أو `context.screenLayout`.
- ❌ لا `Colors.blue` مباشرة — `Theme.of(context).colorScheme`.
- ❌ لا `setState` لحالة مشتركة — أضف Provider في `lib/providers/` أو وسّع الموجود.
- ❌ لا `print()` / `debugPrint()` في كود الإنتاج — استخدم لوجر مركزي (أو `developer.log`).
- ❌ لا `MediaQuery.of(context).size` المتكرر داخل `build` — استخدم `MediaQuery.sizeOf(context)` أو `context.screenLayout`.
- ❌ لا `Directionality(textDirection: TextDirection.ltr)` إلا لمحتوى LTR أصيل (IBAN، باركود، كود).
- ❌ لا تنسَ اختبار الشاشة على RTL + تابلت + ديسكتوب قبل الـ PR.
