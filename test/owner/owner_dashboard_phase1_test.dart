import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/models/owner_section_ttl.dart';
import 'package:naboo/owner/specs/owner_kpi_catalog_entry.dart';
import 'package:naboo/owner/widgets/owner_data_status_line.dart';
import 'package:naboo/owner/widgets/owner_oil_kpi_stitch_tile.dart';
import 'package:naboo/services/network_status_service.dart';
import 'package:naboo/utils/iqd_money.dart';
import 'package:naboo/utils/iraqi_currency_format.dart';

Widget _host(Widget child, {double width = 360, double textScale = 1}) {
  return MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 900),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('آخر مزامنة', () {
    test('Arabic age wording', () {
      expect(ownerSyncAgeAr(const Duration(seconds: 20)), 'الآن');
      expect(ownerSyncAgeAr(const Duration(minutes: 1)), 'قبل دقيقة');
      expect(ownerSyncAgeAr(const Duration(minutes: 2)), 'قبل دقيقتين');
      expect(ownerSyncAgeAr(const Duration(minutes: 3)), 'قبل 3 دقائق');
      expect(ownerSyncAgeAr(const Duration(minutes: 25)), 'قبل 25 دقيقة');
      expect(ownerSyncAgeAr(const Duration(hours: 5)), 'قبل 5 ساعات');
      expect(ownerSyncAgeAr(const Duration(days: 2)), 'قبل يومين');
    });

    test('status text online, offline and never synced', () {
      final now = DateTime(2026, 11, 8, 12);
      expect(
        ownerDataStatusText(
          lastSyncAt: now.subtract(const Duration(minutes: 3)),
          isOffline: false,
          now: now,
        ),
        'آخر مزامنة: قبل 3 دقائق',
      );
      expect(
        ownerDataStatusText(lastSyncAt: null, isOffline: false, now: now),
        'آخر مزامنة: لم تتم بعد',
      );
      final offline = ownerDataStatusText(
        lastSyncAt: now.subtract(const Duration(minutes: 3)),
        isOffline: true,
        now: now,
      );
      expect(offline, contains('لا إنترنت'));
      expect(offline, contains('من هذا الجهاز فقط'));
      expect(offline, contains('قبل 3 دقائق'));
    });

    testWidgets('line updates when a sync lands', (tester) async {
      final last = ValueNotifier<DateTime?>(null);
      final now = DateTime(2026, 11, 8, 12);
      await tester.pumpWidget(
        _host(
          OwnerDataStatusLine(
            lastSyncAt: last,
            isOffline: false,
            now: () => now,
          ),
        ),
      );
      expect(find.text('آخر مزامنة: لم تتم بعد'), findsOneWidget);

      last.value = now.subtract(const Duration(minutes: 5));
      await tester.pump();
      expect(find.text('آخر مزامنة: قبل 5 دقائق'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
    });

    testWidgets('offline line shows warning icon and text', (tester) async {
      final now = DateTime(2026, 11, 8, 12);
      await tester.pumpWidget(
        _host(
          OwnerDataStatusLine(
            lastSyncAt: ValueNotifier(now),
            isOffline: true,
            now: () => now,
          ),
        ),
      );
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.textContaining('لا إنترنت'), findsOneWidget);
    });
  });

  group('NetworkStatusService', () {
    tearDown(() => NetworkStatusService.instance.debugReset());

    test('follows the real connectivity stream, unknown at start', () async {
      final svc = NetworkStatusService.instance;
      await svc.debugReset();
      final ctrl = StreamController<List<ConnectivityResult>>();
      final initial = Completer<List<ConnectivityResult>>();
      svc.ensureStarted(
        stream: ctrl.stream,
        initialCheck: () => initial.future,
      );

      expect(svc.online, isNull);
      expect(
        svc.isOffline,
        isFalse,
        reason: 'لا نُظهر «بلا اتصال» قبل أن نعرف',
      );

      initial.complete([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      expect(svc.isOffline, isFalse);

      ctrl.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(svc.isOffline, isTrue);

      ctrl.add([ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      expect(svc.isOffline, isFalse);
      await ctrl.close();
    });
  });

  group('بطاقات الأرقام لا تقص', () {
    const bigFils = 624000000000; // 624,000,000 د.ع
    final bigText = IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(bigFils));

    OwnerOilKpiStitchTile inventoryTile() => OwnerOilKpiStitchTile(
      catalogId: OwnerCatalogIds.inventoryValue,
      title: 'قيمة المخزون',
      section: OwnerSectionResult.success(
        const InventoryValueKpi(totalCostFils: bigFils, productCount: 312),
        DateTime(2026, 11, 8),
      ),
      sectionId: OwnerSectionIds.inventoryValue,
      onRetry: () {},
      layout: OwnerOilKpiStitchLayout.inventoryRow,
    );

    for (final scale in [1.0, 1.6, 2.0]) {
      for (final width in [170.0, 343.0]) {
        testWidgets('inventory value full at width $width, text x$scale', (
          tester,
        ) async {
          await tester.pumpWidget(
            _host(inventoryTile(), width: width, textScale: scale),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(bigText), findsOneWidget);
          final title = tester.widget<Text>(find.text('قيمة المخزون'));
          expect(title.overflow, isNot(TextOverflow.ellipsis));
          expect(title.maxLines, isNull);
          final value = tester.widget<Text>(find.text(bigText));
          expect(value.overflow, isNot(TextOverflow.ellipsis));
          expect(value.maxLines, isNull);
        });
      }
    }

    testWidgets('compact tile title wraps and grows with large text', (
      tester,
    ) async {
      final tile = OwnerOilKpiStitchTile(
        catalogId: OwnerCatalogIds.debtsSummary,
        title: 'ديون العملاء',
        section: OwnerSectionResult.success(
          const DebtSummary(
            totalReceivableFils: 165000000000,
            indebtedCustomerCount: 41,
          ),
          DateTime(2026, 11, 8),
        ),
        sectionId: OwnerSectionIds.debts,
        onRetry: () {},
      );
      await tester.pumpWidget(_host(tile, width: 160, textScale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final text = IraqiCurrencyFormat.formatIqd(
        IqdMoney.fromFils(165000000000),
      );
      expect(find.text(text), findsOneWidget);
      expect(find.text('ديون العملاء'), findsOneWidget);
      expect(
        tester.getSize(find.byType(OwnerOilKpiStitchTile)).height,
        greaterThan(OwnerOilKpiStitchMetrics.compactHeight),
        reason: 'البطاقة تكبر بدل قص الرقم',
      );
    });
  });
}
