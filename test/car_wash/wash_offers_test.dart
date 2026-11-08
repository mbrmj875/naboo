import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/store_policy.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/verticals/car_wash/services/wash_offer_engine.dart';
import 'package:naboo/verticals/car_wash/services/wash_offer_history_loader.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final now = DateTime(2026, 11, 8, 12);
  DateTime ago(int days, [int hours = 0]) =>
      now.subtract(Duration(days: days, hours: hours));
  const price = {'داخلي وخارجي': 10000000}; // 10,000 د.ع بالفلس

  StorePolicy repeat({
    int req = 3,
    int days = 5,
    WashRewardType type = WashRewardType.free,
    double value = 0,
    double max = 0,
    List<String> covered = const [],
  }) => StorePolicy(
    washRepeat: WashRepeatOffer(
      enabled: true,
      washesRequired: req,
      periodDays: days,
      rewardType: type,
      rewardValue: value,
      maxDiscount: max,
      coveredServiceNames: covered,
    ),
  );

  WashOfferResult eval(
    StorePolicy p,
    WashOfferHistory h, [
    Map<String, int> prices = price,
  ]) => WashOfferEngine.evaluate(
    policy: p,
    history: h,
    currentServicePrices: prices,
    now: now,
  );

  group('عرض تكرار الغسل', () {
    test('مطفأ افتراضياً: لا خصم ولا سطر', () {
      final r = eval(const StorePolicy(), const WashOfferHistory());
      expect(r.hasDiscount, isFalse);
      expect(r.encouragementAr, isNull);
    });

    test('غسلتان خلال الفترة ← الثالثة مجانية', () {
      final h = WashOfferHistory(
        washes: [
          WashVisit(at: ago(3)),
          WashVisit(at: ago(1)),
        ],
      );
      final r = eval(repeat(), h);
      expect(r.discountFils, 10000000);
      expect(r.code, WashOfferCodes.repeat);
      expect(r.reasonAr, contains('مجانية'));
    });

    test('السطر التشجيعي قبل المكافأة', () {
      final one = eval(
        repeat(),
        WashOfferHistory(washes: [WashVisit(at: ago(1))]),
      );
      expect(one.hasDiscount, isFalse);
      expect(one.encouragementAr, 'غسلتان من 3 — الغسلة القادمة مجانية');
      final none = eval(repeat(), const WashOfferHistory());
      expect(none.encouragementAr, contains('الغسلة 1 من 3'));
    });

    test('الفترة متحركة: الغسلة القديمة خارجها لا تُحسب', () {
      final h = WashOfferHistory(
        washes: [
          WashVisit(at: ago(6)),
          WashVisit(at: ago(1)),
        ],
      );
      expect(eval(repeat(), h).hasDiscount, isFalse);
    });

    test('العدّ يبدأ من جديد بعد المكافأة', () {
      final h = WashOfferHistory(
        washes: [
          WashVisit(at: ago(4)),
          WashVisit(at: ago(3)),
          WashVisit(at: ago(2), offerCode: WashOfferCodes.repeat),
          WashVisit(at: ago(1)),
        ],
      );
      final r = eval(repeat(), h);
      expect(r.hasDiscount, isFalse);
      expect(r.encouragementAr, contains('غسلتان من 3'));
    });

    test('نسبة، ومبلغ ثابت، وحد أعلى', () {
      final h = WashOfferHistory(
        washes: [
          WashVisit(at: ago(2)),
          WashVisit(at: ago(1)),
        ],
      );
      expect(
        eval(repeat(type: WashRewardType.percent, value: 50), h).discountFils,
        5000000,
      );
      expect(
        eval(repeat(type: WashRewardType.fixed, value: 3000), h).discountFils,
        3000000,
      );
      expect(eval(repeat(max: 4000), h).discountFils, 4000000);
    });

    test('الأنواع المشمولة: غسلة غير مشمولة لا تُحسب ولا تُخصم', () {
      final p = repeat(covered: ['داخلي وخارجي']);
      final h = WashOfferHistory(
        washes: [
          WashVisit(at: ago(2), serviceNames: ['خارجي']),
          WashVisit(at: ago(1), serviceNames: ['داخلي وخارجي']),
        ],
      );
      expect(eval(p, h).hasDiscount, isFalse);
      final h2 = WashOfferHistory(
        washes: [
          WashVisit(at: ago(2), serviceNames: ['داخلي وخارجي']),
          WashVisit(at: ago(1), serviceNames: ['داخلي وخارجي']),
        ],
      );
      final mixed = eval(p, h2, {'داخلي وخارجي': 10000000, 'تلميع': 5000000});
      expect(mixed.discountFils, 10000000);
    });
  });

  group('خصم زبون الزيت', () {
    const oil = StorePolicy(
      oilWash: OilCustomerWashDiscount(
        enabled: true,
        tiers: [
          OilCustomerTier(1, 10),
          OilCustomerTier(3, 25),
          OilCustomerTier(5, 100),
        ],
        countingPeriodDays: 180,
        washesPerOilChange: 1,
      ),
    );

    test('الشرائح حسب عدد الغيارات في الفترة', () {
      expect(
        eval(oil, WashOfferHistory(oilChanges: [ago(10)])).discountFils,
        1000000,
      );
      expect(
        eval(
          oil,
          WashOfferHistory(oilChanges: [ago(100), ago(50), ago(10)]),
        ).discountFils,
        2500000,
      );
      final five = eval(
        oil,
        WashOfferHistory(
          oilChanges: [for (var i = 1; i <= 5; i++) ago(i * 20)],
        ),
      );
      expect(five.discountFils, 10000000);
      expect(five.reasonAr, contains('مجانية'));
      expect(
        eval(oil, WashOfferHistory(oilChanges: [ago(200)])).hasDiscount,
        isFalse,
      );
    });

    test('غسلة مخصومة واحدة لكل غيار', () {
      final used = WashOfferHistory(
        oilChanges: [ago(10)],
        washes: [WashVisit(at: ago(5), offerCode: WashOfferCodes.oilTier)],
      );
      final r = eval(oil, used);
      expect(r.hasDiscount, isFalse);
      expect(r.encouragementAr, contains('يتجدد'));
    });

    test('الأكبر يفوز حين ينطبق العرضان', () {
      final both = oil.copyWith(washRepeat: repeat().washRepeat);
      final h = WashOfferHistory(
        oilChanges: [ago(10)],
        washes: [
          WashVisit(at: ago(2)),
          WashVisit(at: ago(1)),
        ],
      );
      final r = eval(both, h);
      expect(r.code, WashOfferCodes.repeat);
      expect(r.discountFils, 10000000);
      final early = eval(both, WashOfferHistory(oilChanges: [ago(10)]));
      expect(early.code, WashOfferCodes.oilTier);
      expect(early.encouragementAr, contains('الغسلة 1 من 3'));
    });
  });

  group('قراءة سجل السيارة', () {
    late Database db;
    setUpAll(sqfliteFfiInit);
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE service_orders (
          id INTEGER PRIMARY KEY, tenantId INTEGER, orderKind TEXT, status TEXT,
          deviceSerial TEXT, deletedAt TEXT, createdAt TEXT, requestedServices TEXT,
          washOfferCode TEXT, invoiceId INTEGER
        )''');
      await db.execute('''
        CREATE TABLE invoices (
          id INTEGER PRIMARY KEY, isReturned INTEGER DEFAULT 0,
          originalInvoiceId INTEGER, deleted_at TEXT, tenantId INTEGER DEFAULT 1
        )''');
      var id = 0;
      Future<void> add(
        String kind,
        DateTime at, {
        String plate = '12345 بصرة',
        String status = 'delivered',
        String? deleted,
        int? invoiceId,
        String? code,
      }) => db.insert('service_orders', {
        'id': ++id,
        'tenantId': 1,
        'orderKind': kind,
        'status': status,
        'deviceSerial': plate,
        'deletedAt': deleted,
        'createdAt': at.toUtc().toIso8601String(),
        'requestedServices': 'داخلي,خارجي',
        'washOfferCode': code,
        'invoiceId': invoiceId,
      });
      await db.insert('invoices', {'id': 100});
      await db.insert('invoices', {'id': 101});
      await db.insert('invoices', {
        'id': 102,
        'isReturned': 1,
        'originalInvoiceId': 101,
      });
      // مرتجع في محل آخر يشير لرقم 100: لا يُسقط غسلة هذا المحل.
      await db.insert('invoices', {
        'id': 103,
        'isReturned': 1,
        'originalInvoiceId': 100,
        'tenantId': 2,
      });
      await add(
        ServiceOrderKinds.carWash,
        ago(1),
        invoiceId: 100,
        code: 'repeat',
      );
      await add(ServiceOrderKinds.carWash, ago(2), invoiceId: 101); // مرتجعة
      await add(ServiceOrderKinds.carWash, ago(2), status: 'cancelled');
      await add(ServiceOrderKinds.carWash, ago(2), deleted: '2026-11-07');
      await add(ServiceOrderKinds.carWash, ago(2), plate: '999 بغداد');
      await add(ServiceOrderKinds.carWash, ago(40)); // قبل الفترة
      await add(ServiceOrderKinds.oilChange, ago(3), plate: ' 12345  بصرة ');
    });
    tearDown(() => db.close());

    test(
      'يستبعد الملغى والمحذوف والمرتجع وسيارات أخرى وما قبل الفترة',
      () async {
        final h = await WashOfferHistoryLoader.load(
          db,
          1,
          plate: '12345 بصرة',
          since: ago(30),
        );
        expect(h.washes, hasLength(1));
        expect(h.washes.single.offerCode, 'repeat');
        expect(h.washes.single.serviceNames, ['داخلي', 'خارجي']);
        expect(h.oilChanges, hasLength(1));
      },
    );

    test('محل آخر لا يرى شيئاً', () async {
      final h = await WashOfferHistoryLoader.load(
        db,
        2,
        plate: '12345 بصرة',
        since: ago(30),
      );
      expect(h.washes, isEmpty);
      expect(h.oilChanges, isEmpty);
    });
  });

  group('تعديل السعر أو الخصم في بطاقة الغسيل', () {
    WashPriceChange run({
      bool manual = true,
      int selection = 10000000,
      int total = 10000000,
      bool discount = false,
      bool elevated = false,
      bool owner = false,
    }) => WashPriceChange.evaluate(
      totalManual: manual,
      selectionFils: selection,
      totalFils: total,
      discountOverridden: discount,
      elevated: elevated,
      isOwner: owner,
    );

    test('الموظف المحدود يحتاج موافقة لتغيير الخصم', () {
      final r = run(discount: true);
      expect(r.discountChanged, isTrue);
      expect(r.needsApproval, isTrue);
    });

    test('الموظف المحدود يحتاج موافقة لتغيير السعر', () {
      final r = run(total: 8000000);
      expect(r.priceChanged, isTrue);
      expect(r.needsApproval, isTrue);
    });

    test('المالك والموظف الكامل لا يحتاجان موافقة', () {
      expect(run(discount: true, owner: true).needsApproval, isFalse);
      expect(run(total: 8000000, elevated: true).needsApproval, isFalse);
    });

    test('بلا تغيير لا موافقة', () {
      expect(run().changed, isFalse);
      expect(run(manual: false, total: 8000000).needsApproval, isFalse);
    });
  });
}
