import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/debt_settings_data.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/models/recent_activity_entry.dart';
import 'package:naboo/owner/models/owner_command_center_snapshot.dart';
import 'package:naboo/owner/models/owner_date_range.dart';
import 'package:naboo/owner/models/owner_kpi_models.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/owner_command_center_repository.dart';
import 'package:naboo/owner/providers/owner_command_center_provider.dart';
import 'package:naboo/owner/services/business_audit_log_service.dart';
import 'package:naboo/owner/specs/owner_dashboard_profile.dart';
import 'package:naboo/owner/theme/owner_dashboard_tokens.dart';
import 'package:naboo/owner/widgets/v4/owner_oil_dashboard_v4.dart';
import 'package:naboo/owner/widgets/v4/owner_v4_actions.dart';
import 'package:naboo/owner/widgets/v4/owner_v4_attention_section.dart';
import 'package:naboo/owner/widgets/v4/owner_v4_manage_section.dart';
import 'package:naboo/owner/widgets/v4/owner_v4_top_bar.dart';
import 'package:naboo/services/business_setup_settings.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _tenantId = 1;

/// يسجّل كل لمسة: اسم الإجراء أو `route:<id>`.
class _Recorder {
  final calls = <String>[];

  OwnerV4Actions get actions => OwnerV4Actions(
    openSales: () => calls.add('sales'),
    openCash: () => calls.add('cash'),
    openOilLog: () => calls.add('oilLog'),
    openDebts: () => calls.add('debts'),
    debtReminders: () => calls.add('debtReminders'),
    purchasePdf: () => calls.add('purchasePdf'),
    openInventory: () => calls.add('inventory'),
    openInstallments: () => calls.add('installments'),
    openSensitive: () => calls.add('sensitive'),
    openStaffActivity: () => calls.add('staffActivity'),
    openRoute: (id) => calls.add('route:$id'),
  );
}

OwnerCommandCenterSnapshot _fullSnapshot({
  int warnDays = 30,
  int lateDebtors = 2,
  int sensitive = 1,
  int shortages = 3,
  int stale = 1,
}) {
  final at = DateTime(2026, 11, 9, 9);
  OwnerSectionResult<T> ok<T>(T d) => OwnerSectionResult.success(d, at);
  const range = OwnerDateRange.today();
  return OwnerCommandCenterSnapshot(
    sales: ok(const SalesKpi(salesFils: 160674117000, range: range)),
    cash: ok(
      const CashSummary(
        balanceFils: 160674117000,
        todayInFils: 130000000,
        todayOutFils: 5000000,
      ),
    ),
    openShifts: ok(
      OpenShiftsKpi(
        items: [
          OpenShiftRow(
            id: 1,
            staffName: 'علي الفني',
            openedAt: DateTime(2026, 11, 9, 8, 5).toIso8601String(),
          ),
        ],
      ),
    ),
    debts: ok(
      const DebtSummary(
        totalReceivableFils: 2450000000,
        indebtedCustomerCount: 7,
      ),
    ),
    inventoryValue: ok(
      const InventoryValueKpi(totalCostFils: 98765432000, productCount: 142),
    ),
    salesSparkline: ok(const [
      90000000,
      0,
      120000000,
      75000000,
      40000000,
      110000000,
      130000000,
    ]),
    oilActiveCars: ok(
      OilActiveCarsKpi(activeCount: 4, staleWaitingCount: stale),
    ),
    oilChangesCount: ok(
      const OilChangesKpi(
        changeCount: 9,
        revenueFils: 0,
        range: range,
        washCount: 2,
        directSaleCount: 3,
        oilInvoiceCount: 9,
      ),
    ),
    oilStockShortages: ok(InventoryAlert(shortageCount: shortages)),
    oilAvgTicket: ok(
      const OilAvgTicketKpi(
        avgTicketFils: 35000000,
        changeCount: 9,
        range: range,
      ),
    ),
    installments: ok(const InstallmentAlert(overdueCount: 0, dueTodayCount: 0)),
    ownerAttention: ok(
      OwnerAttentionKpi(
        warnDebtAgeDays: warnDays,
        lateDebtorCount: lateDebtors,
        lateDebtFils: 600000000,
        sensitiveTodayCount: sensitive,
      ),
    ),
  );
}

Future<List<RecentActivityEntry>> _fakeActivity() async => [
  RecentActivityEntry(
    kind: RecentActivityKind.invoice,
    at: DateTime(2026, 11, 9, 10, 15),
    title: 'فاتورة غيار زيت #120',
    subtitle: '',
    actorName: 'علي الفني',
  ),
];

Widget _host({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

BusinessSetupSettingsData _features() =>
    BusinessSetupSettingsData.defaults().copyWith(enableDebts: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ownerV4BreakpointFor', () {
    test('phone < 600 ≤ tablet < 1200 ≤ desktop', () {
      expect(ownerV4BreakpointFor(360), OwnerV4Breakpoint.phone);
      expect(ownerV4BreakpointFor(599), OwnerV4Breakpoint.phone);
      expect(ownerV4BreakpointFor(600), OwnerV4Breakpoint.tablet);
      expect(ownerV4BreakpointFor(1199), OwnerV4Breakpoint.tablet);
      expect(ownerV4BreakpointFor(1200), OwnerV4Breakpoint.desktop);
    });
  });

  group('OwnerDashboardTokens', () {
    test('identity colors: navy ink and icon gold in light mode', () {
      expect(OwnerDashboardTokens.light.ink, const Color(0xFF071A36));
      expect(OwnerDashboardTokens.light.gold, const Color(0xFFB8960C));
      expect(OwnerDashboardTokens.dark.background, const Color(0xFF08111F));
    });

    test('muted text keeps ≥ 4.5:1 contrast on cards (light and dark)', () {
      double ratio(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final hi = la > lb ? la : lb;
        final lo = la > lb ? lb : la;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final t in [OwnerDashboardTokens.light, OwnerDashboardTokens.dark]) {
        expect(ratio(t.inkMuted, t.card), greaterThanOrEqualTo(4.5));
        expect(ratio(t.ink, t.card), greaterThanOrEqualTo(7));
        expect(ratio(t.ink, t.dangerSoft), greaterThanOrEqualTo(4.5));
        expect(ratio(t.ink, t.warningSoft), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('buildOwnerV4Alerts', () {
    test('late debtors use the debt settings age, with reminder action', () {
      final r = _Recorder();
      final alerts = buildOwnerV4Alerts(
        snapshot: _fullSnapshot(),
        actions: r.actions,
        garageStaleHours: 2,
        debtsEnabled: true,
        installmentsEnabled: false,
      );
      final ids = alerts.map((a) => a.id).toList();
      expect(ids, ['late_debtors', 'shortages', 'stale_cars', 'sensitive']);
      final late = alerts.first;
      expect(late.title, 'عملاء متأخرون بالسداد: 2');
      expect(late.subtitle, contains('دين عمره 30 يوماً أو أكثر'));
      late.onAction!();
      late.onTap();
      alerts[1].onAction!();
      expect(r.calls, ['debtReminders', 'debts', 'purchasePdf']);
    });

    test('age warning disabled → general debt line with a hint', () {
      final alerts = buildOwnerV4Alerts(
        snapshot: _fullSnapshot(warnDays: 0, lateDebtors: 0),
        actions: _Recorder().actions,
        garageStaleHours: 2,
        debtsEnabled: true,
        installmentsEnabled: false,
      );
      expect(alerts.first.id, 'debtors');
      expect(alerts.first.title, 'عملاء عليهم ديون: 7');
      expect(alerts.first.subtitle, contains('تحذير عمر الدين'));
    });

    test('nothing pending → no alerts; debts disabled hides debt lines', () {
      final calm = buildOwnerV4Alerts(
        snapshot: _fullSnapshot(
          lateDebtors: 0,
          sensitive: 0,
          shortages: 0,
          stale: 0,
        ),
        actions: _Recorder().actions,
        garageStaleHours: 2,
        debtsEnabled: true,
        installmentsEnabled: true,
      );
      expect(calm, isEmpty);

      final noDebts = buildOwnerV4Alerts(
        snapshot: _fullSnapshot(),
        actions: _Recorder().actions,
        garageStaleHours: 2,
        debtsEnabled: false,
        installmentsEnabled: false,
      );
      expect(noDebts.map((a) => a.id), isNot(contains('late_debtors')));
    });
  });

  group('OwnerOilDashboardV4 layout', () {
    late OwnerCommandCenterProvider center;

    setUp(() => center = OwnerCommandCenterProvider());
    tearDown(() => center.dispose());

    for (final width in [360.0, 800.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final brightness in Brightness.values) {
          testWidgets('width $width · text ×$scale · ${brightness.name}: '
              'no layout errors, six sections, full values', (tester) async {
            tester.view.physicalSize = Size(width, 2400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(
              _host(
                brightness: brightness,
                textScale: scale,
                child: OwnerOilDashboardV4(
                  center: center,
                  snapshot: _fullSnapshot(),
                  features: _features(),
                  actions: _Recorder().actions,
                  activityLoader: _fakeActivity,
                  today: DateTime(2026, 11, 9),
                ),
              ),
            );
            await tester.pump();

            expect(tester.takeException(), isNull);
            for (final id in [
              'today',
              'attention',
              'workshop',
              'numbers',
              'trend',
              'manage',
            ]) {
              expect(
                find.byKey(ValueKey('v4-section-$id')),
                findsOneWidget,
                reason: id,
              );
            }
            // الأرقام كاملة، بلا قص ولا «…».
            expect(find.textContaining('160,674,117'), findsWidgets);
            expect(find.textContaining('98,765,432'), findsOneWidget);
            expect(find.text('عملاء متأخرون بالسداد: 2'), findsOneWidget);
            expect(find.text('9 غيار · 2 غسيل · 3 بيع مباشر'), findsOneWidget);
            expect(find.text('علي الفني · منذ 08:05'), findsOneWidget);
            expect(find.text('علي الفني · 10:15'), findsOneWidget);
            expect(find.text('فاتورة غيار زيت #120'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('v4-trend-today')),
              findsOneWidget,
            );
            final ellipsized = tester
                .widgetList<Text>(find.byType(Text))
                .where((t) => t.overflow == TextOverflow.ellipsis);
            expect(ellipsized, isEmpty);
          });
        }
      }
    }

    testWidgets('same reading order on phone: today → … → manage', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          child: OwnerOilDashboardV4(
            center: center,
            snapshot: _fullSnapshot(),
            features: _features(),
            actions: _Recorder().actions,
            activityLoader: _fakeActivity,
          ),
        ),
      );
      await tester.pump();
      double y(String id) =>
          tester.getTopLeft(find.byKey(ValueKey('v4-section-$id'))).dy;
      final order = [
        'today',
        'attention',
        'workshop',
        'numbers',
        'trend',
        'manage',
      ];
      for (var i = 1; i < order.length; i++) {
        expect(y(order[i]), greaterThan(y(order[i - 1])), reason: order[i]);
      }
    });

    testWidgets('trend summary names the highest day and the 7-day total', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          child: OwnerOilDashboardV4(
            center: center,
            snapshot: _fullSnapshot(),
            features: _features(),
            actions: _Recorder().actions,
            activityLoader: _fakeActivity,
            today: DateTime(2026, 11, 9), // الاثنين
          ),
        ),
      );
      await tester.pump();
      // 130,000 اليوم هو الأعلى؛ المجموع 565,000.
      expect(find.textContaining('أعلى يوم: اليوم'), findsOneWidget);
      expect(find.textContaining('565,000'), findsOneWidget);

      // أعلى يوم ليس اليوم → اسمه: الموضع 2 من 7 = الخميس 5/11.
      await tester.pumpWidget(
        _host(
          child: OwnerOilDashboardV4(
            center: center,
            snapshot: _fullSnapshot().copyWith(
              salesSparkline: OwnerSectionResult.success(const [
                0,
                0,
                120000000,
                0,
                0,
                0,
                1000,
              ], DateTime(2026, 11, 9)),
            ),
            features: _features(),
            actions: _Recorder().actions,
            activityLoader: _fakeActivity,
            today: DateTime(2026, 11, 9),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('أعلى يوم: خميس'), findsOneWidget);
      expect(find.text('اليوم'), findsWidgets);
    });

    testWidgets('every tile and management button opens its destination', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final r = _Recorder();
      await tester.pumpWidget(
        _host(
          child: OwnerOilDashboardV4(
            center: center,
            snapshot: _fullSnapshot(),
            features: _features(),
            actions: r.actions,
            activityLoader: _fakeActivity,
          ),
        ),
      );
      await tester.pump();

      Future<String> tapKey(String key) async {
        r.calls.clear();
        final f = find.byKey(ValueKey(key));
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pump();
        expect(r.calls, hasLength(1), reason: key);
        return r.calls.single;
      }

      expect(await tapKey('v4-sales'), 'sales');
      expect(await tapKey('v4-cash'), 'cash');
      expect(await tapKey('v4-ops'), 'oilLog');
      expect(await tapKey('v4-cars'), 'oilLog');
      expect(await tapKey('v4-shifts'), 'staffActivity');
      expect(await tapKey('v4-staff-all'), 'staffActivity');
      expect(await tapKey('v4-avg'), 'oilLog');
      expect(await tapKey('v4-inventory-value'), 'inventory');
      expect(await tapKey('v4-debts'), 'debts');
      expect(await tapKey('v4-shortages'), 'inventory');
      expect(await tapKey('v4-alert-action-shortages'), 'purchasePdf');
      expect(await tapKey('v4-alert-action-sensitive'), 'sensitive');

      final expected = <String, String>{
        'reports': 'route:reports',
        'oil_services_log': 'route:oil_services_log',
        'customers': 'route:customers',
        'inventory': 'route:inventory',
        'cash': 'route:cash',
        'owner_purchase_pdf': 'purchasePdf',
        'users': 'route:users',
        'oil_change_ratings': 'route:oil_change_ratings',
        'return_policy': 'route:return_policy',
        'wash_offers': 'route:wash_offers',
        'store_settings': 'route:store_settings',
        OwnerV4ManageItem.sensitiveRoute: 'sensitive',
      };
      expect(
        OwnerV4ManageItem.all.map((e) => e.routeId).toSet(),
        expected.keys.toSet(),
      );
      for (final e in expected.entries) {
        expect(await tapKey('v4-manage-${e.key}'), e.value, reason: e.key);
      }
    });
  });

  group('OwnerV4PeriodTabs', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('360 wide · text ×$scale: four tabs, custom label whole', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        OwnerDateRange? picked;
        await tester.pumpWidget(
          _host(
            textScale: scale,
            child: OwnerV4PeriodTabs(
              selected: const OwnerDateRange.today(),
              onChanged: (r) => picked = r,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('اليوم'), findsOneWidget);
        expect(find.text('مخصص'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('v4-period-thisWeek')));
        expect(picked?.kind, OwnerDateRangeKind.thisWeek);
      });
    }
  });

  group('OwnerV4TopBar', () {
    for (final width in [360.0, 1280.0]) {
      testWidgets('$width wide: title, shop name, labelled employee mode', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var gate = 0;
        await tester.pumpWidget(
          _host(
            child: OwnerV4TopBar(
              shopName: 'محل البصرة للزيوت',
              onEmployeeGate: () => gate++,
              onDashboardSyncBusy: (_) {},
              onAfterCloudSync: () async {},
              showAccountMenu: false,
              showAssistant: false,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('لوحة المالك'), findsOneWidget);
        expect(find.text('محل البصرة للزيوت'), findsOneWidget);
        if (width >= 600) {
          expect(find.text('وضع الموظفين'), findsOneWidget);
        } else {
          expect(find.byTooltip('وضع الموظفين'), findsOneWidget);
        }
        await tester.tap(find.byKey(const ValueKey('v4-employee-gate')));
        expect(gate, 1);
      });
    }
  });

  group('data correctness (SQLite)', () {
    late DatabaseHelper dbHelper;
    late OwnerCommandCenterRepository repo;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      await dbHelper.ensureServiceOrdersReadRepair();
      final db = await dbHelper.database;
      await db.delete('service_orders');
      await db.delete('invoices');
      repo = OwnerCommandCenterRepository();
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    test(
      'late payers: same rule as the debts screen (age ≥ setting, open)',
      () async {
        final db = await dbHelper.database;
        await dbHelper.saveDebtSettings(
          DebtSettingsData.defaults().copyWith(warnDebtAgeDays: 30),
        );
        final now = DateTime(2026, 11, 9, 12);
        String daysAgo(int d) =>
            DateTime(now.year, now.month, now.day - d, 10).toIso8601String();

        // عميل 5: فاتورتان متأخرتان = عميل واحد.
        await _credit(db, date: daysAgo(40), customerId: 5, totalFils: 100000);
        await _credit(db, date: daysAgo(31), customerId: 5, totalFils: 50000);
        // بلا معرّف — بالاسم فقط، متأخر.
        await _credit(
          db,
          date: daysAgo(30),
          name: 'أبو حيدر',
          totalFils: 20000,
        );
        // ليست متأخرة / مسددة / مرتجعة / محذوفة / محل آخر / نقدية.
        await _credit(db, date: daysAgo(10), customerId: 6, totalFils: 70000);
        await _credit(
          db,
          date: daysAgo(60),
          customerId: 7,
          totalFils: 90000,
          advanceFils: 90000,
        );
        await _credit(
          db,
          date: daysAgo(60),
          customerId: 8,
          totalFils: 1,
          returned: true,
        );
        await _credit(
          db,
          date: daysAgo(60),
          customerId: 9,
          totalFils: 9000,
          deleted: true,
        );
        await _credit(
          db,
          date: daysAgo(60),
          customerId: 5,
          totalFils: 9000,
          tenant: 2,
        );
        await _credit(
          db,
          date: daysAgo(60),
          customerId: 10,
          totalFils: 9000,
          type: InvoiceType.cash,
        );

        final k = await repo.loadOwnerAttention(tenantId: _tenantId, now: now);
        expect(k.warnDebtAgeDays, 30);
        expect(k.lateDebtorCount, 2);
        expect(k.lateDebtFils, 170000);
      },
    );

    test('late payers off when the debt age warning is 0', () async {
      final db = await dbHelper.database;
      await dbHelper.saveDebtSettings(
        DebtSettingsData.defaults().copyWith(warnDebtAgeDays: 0),
      );
      await _credit(
        db,
        date: DateTime(2020, 1, 1).toIso8601String(),
        customerId: 5,
        totalFils: 100000,
      );
      final k = await repo.loadOwnerAttention(tenantId: _tenantId);
      expect(k.lateDebtorCount, 0);
      expect(k.lateDebtFils, 0);
    });

    test('sensitive edits today count only sensitive events', () async {
      await BusinessAuditLogService.instance.record(
        eventType: 'price_change',
        entityType: 'product',
        entityId: '1',
        tenantId: _tenantId,
      );
      await BusinessAuditLogService.instance.record(
        eventType: 'session_locked',
        entityType: 'session',
        entityId: '1',
        tenantId: _tenantId,
      );
      final k = await repo.loadOwnerAttention(tenantId: _tenantId);
      expect(k.sensitiveTodayCount, 1);
    });

    test(
      "oil shop: today's 7-day bar equals today's sales (all invoices)",
      () async {
        final db = await dbHelper.database;
        final now = DateTime.now();
        final today = DateTime(
          now.year,
          now.month,
          now.day,
          10,
        ).toIso8601String();
        final yesterday = DateTime(
          now.year,
          now.month,
          now.day - 1,
          10,
        ).toIso8601String();
        // غيار + غسيل + بيع مباشر اليوم، مرتجع ومحذوفة لا تُحسب، وأمس منفصل.
        await _cashInvoice(db, today, 35000);
        await _cashInvoice(db, today, 10000);
        await _cashInvoice(db, today, 7500);
        await _cashInvoice(db, today, 99000, returned: true);
        await _cashInvoice(db, today, 99000, deleted: true);
        await _cashInvoice(db, yesterday, 20000);

        final sales = await repo.loadSales(
          tenantId: _tenantId,
          range: const OwnerDateRange.today(),
        );
        final bars = await repo.loadSalesSparkline(tenantId: _tenantId);
        expect(sales.salesFils, 52500);
        expect(bars.last, sales.salesFils);
        expect(bars[bars.length - 2], 20000);

        final rows = await repo.listPeriodSales(
          tenantId: _tenantId,
          range: const OwnerDateRange.today(),
          profile: OwnerDashboardProfile.oilChangeService,
        );
        expect(rows, hasLength(3));
      },
    );
  });
}

Future<int> _credit(
  Database db, {
  required String date,
  int? customerId,
  String name = 'عميل',
  required int totalFils,
  int advanceFils = 0,
  bool returned = false,
  bool deleted = false,
  int tenant = _tenantId,
  InvoiceType type = InvoiceType.credit,
}) {
  return db.insert('invoices', {
    'tenantId': tenant,
    'date': date,
    'type': type.index,
    'customerId': customerId,
    'customerName': name,
    'total': totalFils / 1000.0,
    'totalFils': totalFils,
    'advancePayment': advanceFils / 1000.0,
    'advancePaymentFils': advanceFils,
    'isReturned': returned ? 1 : 0,
    'deleted_at': deleted ? date : null,
    'updatedAt': date,
  });
}

Future<int> _cashInvoice(
  Database db,
  String date,
  int totalFils, {
  bool returned = false,
  bool deleted = false,
}) {
  return db.insert('invoices', {
    'tenantId': _tenantId,
    'date': date,
    'type': InvoiceType.cash.index,
    'total': totalFils / 1000.0,
    'totalFils': totalFils,
    'isReturned': returned ? 1 : 0,
    'deleted_at': deleted ? date : null,
    'updatedAt': date,
  });
}
