import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/navigation/content_navigation.dart';

/// ملاح اختباري: `/a` ثم ما يُدفع فوقه، مع مراقب المكدس.
Future<NavigatorState> _pumpNavigator(
  WidgetTester tester,
  ContentRouteStackObserver observer,
) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: key,
      navigatorObservers: [observer],
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'root'),
        builder: (_) => const Text('root'),
      ),
    ),
  );
  return key.currentState!;
}

Route<void> _named(String name, {bool blockPop = false}) {
  return MaterialPageRoute<void>(
    settings: RouteSettings(name: name),
    builder: (_) => PopScope(canPop: !blockPop, child: Text(name)),
  );
}

void main() {
  group('ContentRouteStackObserver', () {
    testWidgets('يرى المكدس كاملاً ويعود إلى مسار وسيط', (tester) async {
      final observer = ContentRouteStackObserver();
      final nav = await _pumpNavigator(tester, observer);
      unawaited(nav.push(_named('a')));
      unawaited(nav.push(_named('b')));
      await tester.pumpAndSettle();

      expect(observer.containsRouteId('a'), isTrue);
      expect(observer.containsRouteId('missing'), isFalse);
      expect(observer.topNamedRoute?.settings.name, 'b');

      expect(await observer.popBackTo('a'), isTrue);
      await tester.pumpAndSettle();
      expect(observer.topNamedRoute?.settings.name, 'a');
      expect(observer.containsRouteId('b'), isFalse);
    });

    testWidgets('يرى المسار الأول الذي أنشأه الملاح نفسه', (tester) async {
      final observer = ContentRouteStackObserver();
      await _pumpNavigator(tester, observer);

      expect(observer.containsRouteId('root'), isTrue);
      expect(observer.topNamedRoute?.settings.name, 'root');
    });

    testWidgets('لا يفرغ المكدس إذا لم يكن المسار موجوداً', (tester) async {
      final observer = ContentRouteStackObserver();
      final nav = await _pumpNavigator(tester, observer);
      unawaited(nav.push(_named('a')));
      await tester.pumpAndSettle();

      expect(await observer.popBackTo('missing'), isFalse);
      await tester.pumpAndSettle();
      expect(observer.topNamedRoute?.settings.name, 'a');
    });

    testWidgets('يتوقف عند شاشة تمنع الخروج فلا تضيع المسودة', (tester) async {
      final observer = ContentRouteStackObserver();
      final nav = await _pumpNavigator(tester, observer);
      unawaited(nav.push(_named('a')));
      unawaited(nav.push(_named('draft', blockPop: true)));
      unawaited(nav.push(_named('top')));
      await tester.pumpAndSettle();

      expect(await observer.popBackTo('a'), isFalse);
      await tester.pumpAndSettle();
      expect(observer.topNamedRoute?.settings.name, 'draft');
    });

    testWidgets('يتجاوز المسارات بلا اسم عند قراءة الأعلى', (tester) async {
      final observer = ContentRouteStackObserver();
      final nav = await _pumpNavigator(tester, observer);
      unawaited(nav.push(_named('a')));
      unawaited(
        nav.push(MaterialPageRoute<void>(builder: (_) => const Text('x'))),
      );
      await tester.pumpAndSettle();

      expect(observer.topNamedRoute?.settings.name, 'a');
    });
  });

  group('شجرة مسار التنقل', () {
    test('سجل الزيت لا يتكرر مرتين في المسار', () {
      final trail = buildBreadcrumbTrail(
        AppContentRoutes.oilServicesLog,
        'سجل غيارات الزيت',
        null,
      );
      expect(trail.map((s) => s.id), [
        AppContentRoutes.home,
        AppContentRoutes.oilServicesLog,
      ]);
    });

    test('شاشات الزيت تشير إلى المسار الفعلي للسجل', () {
      for (final id in [
        AppContentRoutes.oilChangeCreate,
        AppContentRoutes.oilInvoices,
        AppContentRoutes.oilDirectSale,
        AppContentRoutes.oilChangeServices,
        AppContentRoutes.oilChangeEditId(7),
      ]) {
        expect(getParentRouteId(id), AppContentRoutes.oilServicesLog, reason: id);
      }
    });

    test('شاشات الإعدادات والديون لا تقفز فوق أبيها', () {
      expect(
        getParentRouteId(AppContentRoutes.settingsRestore),
        AppContentRoutes.settings,
      );
      expect(
        getParentRouteId(AppContentRoutes.settingsSyncQueueHealth),
        AppContentRoutes.settings,
      );
      expect(
        getParentRouteId('${AppContentRoutes.debts}_customer_5'),
        AppContentRoutes.debts,
      );
    });

    test('المعرّفات الداخلية لا تظهر كعناوين', () {
      for (final id in [
        AppContentRoutes.customersAdd,
        AppContentRoutes.settingsRestore,
        AppContentRoutes.settingsSyncQueueHealth,
      ]) {
        expect(breadcrumbFallbackTitleForRouteId(id), isNot(id));
      }
    });

    test('أب مخصص يساوي المسار نفسه لا يكرر الخطوة', () {
      final trail = buildBreadcrumbTrail(
        AppContentRoutes.customers,
        'العملاء',
        AppContentRoutes.customers,
      );
      expect(trail.map((s) => s.id), [
        AppContentRoutes.home,
        AppContentRoutes.customers,
      ]);
    });
  });

  group('Breadcrumb Navigation System (Spec v1.1.0) Tests', () {
    test('Standard parent mapping resolves correctly', () {
      expect(getParentRouteId(AppContentRoutes.invoices), AppContentRoutes.home);
      expect(getParentRouteId(AppContentRoutes.addInvoice), AppContentRoutes.invoices);
      expect(getParentRouteId(AppContentRoutes.addProduct), AppContentRoutes.inventoryProducts);
    });

    test('Dynamic prefix route parent resolves correctly', () {
      // reports
      expect(getParentRouteId('app_reports_3'), AppContentRoutes.home);
      // returns
      expect(getParentRouteId('app_process_return_992'), AppContentRoutes.invoices);
      // oil edit
      expect(getParentRouteId('app_oil_change_edit_123'), AppContentRoutes.oilServicesLog);
    });

    test('buildBreadcrumbTrail constructs full tree from leaf to root without duplicates', () {
      final trail = buildBreadcrumbTrail(
        AppContentRoutes.oilChangeCreate,
        'بطاقة جديدة',
        null,
      );

      // Expected trail: الرئيسية -> سجل غيارات الزيت -> بطاقة جديدة
      expect(trail.length, 3);
      expect(trail[0].id, AppContentRoutes.home);
      expect(trail[0].title, 'الرئيسية');
      expect(trail[1].id, AppContentRoutes.oilServicesLog);
      expect(trail[1].title, 'سجل غيارات الزيت');
      expect(trail[2].id, AppContentRoutes.oilChangeCreate);
      expect(trail[2].title, 'بطاقة جديدة');
    });

    test('buildBreadcrumbTrail respects optional parentOverride dynamic overrides', () {
      final trail = buildBreadcrumbTrail(
        AppContentRoutes.customers,
        'العملاء',
        AppContentRoutes.addInvoice, // Override parent to be the POS Add Invoice screen
      );

      // Expected trail: الرئيسية -> الفواتير -> بيع جديد -> العملاء
      expect(trail.length, 4);
      expect(trail[0].id, AppContentRoutes.home);
      expect(trail[1].id, AppContentRoutes.invoices);
      expect(trail[2].id, AppContentRoutes.addInvoice);
      expect(trail[3].id, AppContentRoutes.customers);
      expect(trail[3].title, 'العملاء');
    });
  });
}
