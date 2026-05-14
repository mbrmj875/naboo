import 'package:flutter/material.dart';
import '../../utils/screen_layout.dart';
import '../../theme/app_spacing.dart';
import 'adaptive_destination.dart';

/// الإطار الهيكلي الذكي للتطبيق.
///
/// يلتف حول [Scaffold] افتراضي للحفاظ على الـ Snackbars،
/// ويبدل نوع التنقل (BottomBar / Rail / Sidebar) تلقائياً
/// بناءً على [DeviceVariant].
///
/// الـ Slots المدعومة:
/// - [appBar] / [appBarTitle] / [appBarActions]: شريط التطبيق العلوي.
/// - [searchBar]: شريط بحث (يظهر بين AppBar والـ body).
/// - [bottomBanner]: شريط معلومات/تنبيهات يظهر تحت AppBar والـ searchBar
///   (مثل بانر صلاحيات الوردية). يظهر في كل الـ variants.
/// - [body]: المحتوى الرئيسي.
/// - [endPanel]: عمود معلومات سياقي إضافي (يظهر في الديسكتوب فقط).
/// - [floatingActionButton]: زر إجراء عائم.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationChanged,
    this.body,
    this.searchBar,
    this.bottomBanner,
    this.endPanel,
    this.endPanelWidth = 320.0,
    this.floatingActionButton,
    this.appBar,
    this.appBarTitle,
    this.appBarActions,
    this.maxMobileDestinations,
  });

  /// قائمة وجهات التنقل الأساسية.
  final List<AdaptiveDestination> destinations;

  /// الفهرس المحدد حالياً.
  final int selectedIndex;

  /// دالة الاستدعاء عند تغيير التبويب.
  final ValueChanged<int> onDestinationChanged;

  /// المحتوى المخصص (إن لم يُمرر سيتم استخدام builder الخاص بالوجهة).
  final Widget? body;

  /// شريط البحث (يُعرض حسب تصميم كل فئة).
  final Widget? searchBar;

  /// بانر معلومات يظهر تحت AppBar/searchBar في كل الـ variants.
  ///
  /// يُترك للودجت نفسه قرار إخفاء/إظهار نفسه أو تصغيره حسب الـ variant
  /// (مثل [ShiftPermissionBanner]).
  final Widget? bottomBanner;

  /// عمود معلومات سياقية إضافي (ديسكتوب فقط).
  ///
  /// يظهر يسار المحتوى الرئيسي (في RTL) في [DeviceVariant.desktopSM]
  /// و [DeviceVariant.desktopLG]. يتم تجاهله في كل الـ variants الأخرى.
  final Widget? endPanel;

  /// عرض [endPanel] في الديسكتوب.
  final double endPanelWidth;

  /// زر الإجراء العائم.
  final Widget? floatingActionButton;

  /// AppBar جاهز للاستخدام في كل الـ variants.
  ///
  /// - في الموبايل والتابلت: يُمرر مباشرة لـ [Scaffold.appBar].
  /// - في الديسكتوب: يُعرض داخل عمود المحتوى (فوق الـ searchBar).
  final PreferredSizeWidget? appBar;

  /// عنوان الـ AppBar (fallback إذا لم يُمرر [appBar]).
  final String? appBarTitle;

  /// أزرار الإجراءات (fallback إذا لم يُمرر [appBar]).
  final List<Widget>? appBarActions;

  /// عدد عناصر التنقل الظاهرة في الموبايل (4 أو 5 افتراضياً حسب الفئة).
  ///
  /// لو حُدد، يُستبدل المنطق الافتراضي (4 لـ phoneXS، 5 لـ phoneSM).
  final int? maxMobileDestinations;

  PreferredSizeWidget? _resolveAppBar() {
    if (appBar != null) return appBar;
    if (appBarTitle == null) return null;
    return AppBar(
      title: Text(appBarTitle!),
      actions: appBarActions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final variant = context.screenLayout.layoutVariant;
    final Widget currentBody =
        body ?? destinations[selectedIndex].builder(context);

    switch (variant) {
      case DeviceVariant.phoneXS:
      case DeviceVariant.phoneSM:
        return _buildMobileLayout(context, currentBody, variant);

      case DeviceVariant.tabletSM:
      case DeviceVariant.tabletLG:
        return _buildTabletLayout(context, currentBody, variant);

      case DeviceVariant.desktopSM:
      case DeviceVariant.desktopLG:
        return _buildDesktopLayout(context, currentBody, variant);
    }
  }

  Widget _buildMobileLayout(
    BuildContext context,
    Widget currentBody,
    DeviceVariant variant,
  ) {
    final isXS = variant == DeviceVariant.phoneXS;
    final maxVisible = maxMobileDestinations ?? (isXS ? 4 : 5);
    final visibleDestinations = destinations.take(maxVisible).toList();
    final hasMore = destinations.length > maxVisible;

    return Scaffold(
      appBar: _resolveAppBar(),
      body: Column(
        children: [
          if (searchBar != null) searchBar!,
          if (bottomBanner != null) bottomBanner!,
          Expanded(child: currentBody),
        ],
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex < maxVisible ? selectedIndex : maxVisible,
        onDestinationSelected: (index) {
          if (index == maxVisible && hasMore) {
            _showMoreBottomSheet(context, maxVisible);
          } else {
            onDestinationChanged(index);
          }
        },
        destinations: [
          ...visibleDestinations.map(
            (d) => NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon ?? d.icon),
              label: d.label,
            ),
          ),
          if (hasMore)
            const NavigationDestination(
              icon: Icon(Icons.menu),
              label: 'المزيد',
            ),
        ],
      ),
    );
  }

  void _showMoreBottomSheet(BuildContext context, int startIndex) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = startIndex; i < destinations.length; i++)
                ListTile(
                  leading: Icon(destinations[i].icon),
                  title: Text(destinations[i].label),
                  selected: selectedIndex == i,
                  onTap: () {
                    Navigator.pop(ctx);
                    onDestinationChanged(i);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabletLayout(
    BuildContext context,
    Widget currentBody,
    DeviceVariant variant,
  ) {
    final isExtended = variant == DeviceVariant.tabletLG;

    return Scaffold(
      appBar: _resolveAppBar(),
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          NavigationRail(
            extended: isExtended,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationChanged,
            destinations: destinations
                .map(
                  (d) => NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon ?? d.icon),
                    label: Text(d.label),
                  ),
                )
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Column(
              children: [
                if (searchBar != null) searchBar!,
                if (bottomBanner != null) bottomBanner!,
                Expanded(child: currentBody),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    Widget currentBody,
    DeviceVariant variant,
  ) {
    final sidebarWidth = variant == DeviceVariant.desktopLG ? 280.0 : 240.0;
    final resolvedAppBar = _resolveAppBar();

    // المحتوى الرئيسي + عمود endPanel جانبي (لو وُجد).
    final Widget mainArea = Row(
      children: [
        Expanded(
          child: Column(
            children: [
              if (searchBar != null) searchBar!,
              Expanded(child: currentBody),
            ],
          ),
        ),
        if (endPanel != null) ...[
          const VerticalDivider(thickness: 1, width: 1),
          SizedBox(width: endPanelWidth, child: endPanel!),
        ],
      ],
    );

    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          SizedBox(
            width: sidebarWidth,
            child: Material(
              elevation: 0,
              child: ListView(
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  for (int i = 0; i < destinations.length; i++)
                    ListTile(
                      leading: Icon(destinations[i].icon),
                      title: Text(destinations[i].label),
                      selected: selectedIndex == i,
                      onTap: () => onDestinationChanged(i),
                    ),
                ],
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Column(
              children: [
                if (resolvedAppBar != null)
                  SizedBox(
                    height: resolvedAppBar.preferredSize.height,
                    child: resolvedAppBar,
                  ),
                if (bottomBanner != null) bottomBanner!,
                Expanded(child: mainArea),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
