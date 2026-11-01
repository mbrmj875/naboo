import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/navigation/content_navigation.dart';
import 'package:naboo/navigation/shell/content_shell_controller.dart';
import 'package:naboo/navigation/shell/shell_nav_item.dart';
import 'package:naboo/providers/business_features_provider.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:provider/provider.dart';

ShellNavItem _item(String routeId, {List<ShellNavSubItem>? subs}) {
  return ShellNavItem(
    icon: Icons.circle,
    title: routeId,
    iconColor: Colors.red,
    routeId: routeId,
    destination: (_) => Text('page-$routeId'),
    subItems: subs,
  );
}

/// صفحة تعدّ مرات بنائها الأول: الوحدة الحية لا تُبنى من جديد.
class _CountingPage extends StatefulWidget {
  const _CountingPage(this.onInit);
  final VoidCallback onInit;

  @override
  State<_CountingPage> createState() => _CountingPageState();
}

class _CountingPageState extends State<_CountingPage> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Text('counted');
}

Future<ContentShellController> _pumpShell(
  WidgetTester tester, {
  List<ShellNavItem>? items,
}) async {
  final shell = ContentShellController(onRouteChanged: (_) {});
  addTearDown(shell.dispose);
  shell.updateItems(
    items ??
        [
          _item(AppContentRoutes.home),
          _item(AppContentRoutes.inventory),
          _item(AppContentRoutes.cash),
          _item(AppContentRoutes.expenses),
          _item(AppContentRoutes.printing),
          _item(AppContentRoutes.settings),
        ],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => BusinessFeaturesProvider.testing(
        BusinessSetupSettingsData.createForVertical(BusinessVertical.oilChange),
      ),
      child: MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: shell,
            builder: (context, _) => Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: shell.keptModuleId != null,
                  child: Navigator(
                    key: shell.contentNavigatorKey,
                    observers: [shell.contentObserver],
                    onGenerateInitialRoutes: (_, _) => [
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(
                          name: AppContentRoutes.home,
                        ),
                        builder: (_) => const Text('home-page'),
                      ),
                    ],
                  ),
                ),
                shell.buildKeptModules(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return shell;
}

void main() {
  testWidgets('الوحدة تبقى حية ولا تُبنى عند العودة إليها', (tester) async {
    var inits = 0;
    final shell = await _pumpShell(tester);
    Widget page(BuildContext _) => _CountingPage(() => inits++);

    shell.open(AppContentRoutes.inventory, 'المخزون', page);
    await tester.pumpAndSettle();
    shell.open(AppContentRoutes.cash, 'الصندوق', (_) => const Text('cash'));
    await tester.pumpAndSettle();
    shell.open(AppContentRoutes.inventory, 'المخزون', page);
    await tester.pumpAndSettle();

    expect(inits, 1);
    expect(shell.currentRouteId, AppContentRoutes.inventory);
  });

  testWidgets('فتح الوحدة مرتين لا يكرّرها', (tester) async {
    final shell = await _pumpShell(tester);
    Widget page(BuildContext _) => const Text('inventory');

    shell.open(AppContentRoutes.inventory, 'المخزون', page);
    shell.open(AppContentRoutes.inventory, 'المخزون', page);
    await tester.pumpAndSettle();

    expect(shell.keptModuleOrder, [AppContentRoutes.inventory]);
  });

  testWidgets('الضغط المزدوج على صفحة فرعية يفتحها مرة واحدة', (tester) async {
    final shell = await _pumpShell(tester);
    Widget page(BuildContext _) => const Text('card');

    shell.open(AppContentRoutes.oilChangeCreate, 'بطاقة', page);
    await tester.pumpAndSettle();
    shell.open(AppContentRoutes.oilChangeCreate, 'بطاقة', page);
    await tester.pumpAndSettle();

    await tester.state<NavigatorState>(find.byType(Navigator).last).maybePop();
    await tester.pumpAndSettle();
    expect(shell.currentRouteId, AppContentRoutes.home);
  });

  testWidgets('لا يتجاوز حد الوحدات الحية ولا يطرد الظاهرة', (tester) async {
    final shell = await _pumpShell(tester);
    for (final id in [
      AppContentRoutes.inventory,
      AppContentRoutes.cash,
      AppContentRoutes.expenses,
      AppContentRoutes.printing,
      AppContentRoutes.settings,
    ]) {
      shell.open(id, id, (_) => Text(id));
      await tester.pumpAndSettle();
    }

    expect(shell.keptModuleOrder.length, ContentShellController.keptModuleCap);
    expect(shell.keptModuleOrder, isNot(contains(AppContentRoutes.inventory)));
    expect(shell.keptModuleOrder.last, AppContentRoutes.settings);
  });

  testWidgets('الرجوع يغلق الوحدة الظاهرة ثم لا يستهلك الحدث', (tester) async {
    final shell = await _pumpShell(tester);
    shell.open(AppContentRoutes.cash, 'الصندوق', (_) => const Text('cash'));
    await tester.pumpAndSettle();

    expect(shell.handleSystemBack(), isTrue);
    await tester.pumpAndSettle();

    expect(shell.keptModuleId, isNull);
    expect(shell.currentRouteId, AppContentRoutes.home);
    expect(shell.handleSystemBack(), isFalse);
  });

  testWidgets('المسار يشير إلى الصفحة الفرعية بعد إعادة إظهار الوحدة', (
    tester,
  ) async {
    final shell = await _pumpShell(tester);
    shell.open(
      AppContentRoutes.inventory,
      'المخزون',
      (_) => const Text('inventory'),
    );
    await tester.pumpAndSettle();
    unawaited(
      shell.visibleNavigator!.push<void>(
        contentMaterialRoute<void>(
          routeId: AppContentRoutes.addProduct,
          breadcrumbTitle: 'إضافة منتج',
          builder: (_) => const Text('add'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    shell.open(AppContentRoutes.cash, 'الصندوق', (_) => const Text('cash'));
    await tester.pumpAndSettle();

    shell.open(
      AppContentRoutes.inventory,
      'المخزون',
      (_) => const Text('inventory'),
    );
    await tester.pumpAndSettle();

    expect(shell.currentRouteId, AppContentRoutes.addProduct);
  });

  testWidgets('خطوة في المسار تعيد الصفحة الفرعية إلى وحدتها', (tester) async {
    final shell = await _pumpShell(tester);
    shell.open(
      AppContentRoutes.inventory,
      'المخزون',
      (_) => const Text('inventory'),
    );
    await tester.pumpAndSettle();
    unawaited(
      shell.visibleNavigator!.push<void>(
        contentMaterialRoute<void>(
          routeId: AppContentRoutes.inventoryProducts,
          breadcrumbTitle: 'المنتجات',
          builder: (_) => const Text('products'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await shell.onBreadcrumbTap(
      const BreadcrumbSegment(id: AppContentRoutes.inventory, title: 'المخزون'),
    );
    await tester.pumpAndSettle();

    expect(shell.currentRouteId, AppContentRoutes.inventory);
    expect(find.text('products'), findsNothing);
  });

  testWidgets('المسار الفرعي يبرز وحدته صعوداً عبر الآباء', (tester) async {
    final shell = await _pumpShell(tester);
    shell.open(
      AppContentRoutes.inventory,
      'المخزون',
      (_) => const Text('inventory'),
    );
    await tester.pumpAndSettle();
    unawaited(
      shell.visibleNavigator!.push<void>(
        contentMaterialRoute<void>(
          routeId: AppContentRoutes.addProduct,
          breadcrumbTitle: 'إضافة منتج',
          builder: (_) => const Text('add'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(shell.activeIndex, 1);
  });
}
