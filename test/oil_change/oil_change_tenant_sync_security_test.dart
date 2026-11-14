import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/service_order_kinds.dart';
import 'package:naboo/services/service_orders_sql_ops.dart';
import 'package:naboo/services/sync_entity_types.dart';
import 'package:naboo/verticals/oil_change/models/oil_change_whatsapp_notify_outcome.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_whatsapp_outbox.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_lookup_normalize.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_order_status.dart';

import 'fixtures/basra_oil_visit_fixture.dart';
import 'helpers/oil_change_test_harness.dart';

void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('عزل المستأجر + IDOR + الحذف الناعم', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      builder = ServiceOrderBuilder(harness);
    });

    test('بطاقة مستأجر آخر بنفس اللوحة لا تُقرأ ولا تُحدَّث', () async {
      final ours = await builder.createPending(plate: basraPlate);
      final tid = await harness.tenantId();
      final db = await harness.database;

      final foreignId = await ServiceOrdersSqlOps.insertServiceOrder(
        db,
        999,
        oilTestOrderPayload(
          deviceSerial: basraPlate,
          technicianName: 'فني محل آخر',
          agreedPriceFils: 999999999,
        ),
      );

      final byId = await OilChangeOrdersRepository.instance
          .getOilChangeOrderById(foreignId);
      expect(byId, isNull);

      final latest = await OilChangeOrdersRepository.instance
          .getLatestOilChangeByPlate(basraPlate);
      expect(latest, isNotNull);
      expect(latest!['id'], ours);
      expect(latest['technicianName'], isNot('فني محل آخر'));

      final changed = await ServiceOrdersSqlOps.updateServiceOrderById(
        db,
        tid,
        id: foreignId,
        values: {'agreedPriceFils': 1},
      );
      expect(changed, 0);

      final foreignRow = await db.query(
        'service_orders',
        where: 'id = ?',
        whereArgs: [foreignId],
      );
      expect(foreignRow.single['agreedPriceFils'], 999999999);
      expect(foreignRow.single['tenantId'], 999);
    });

    test('الحذف الناعم يخفي البطاقة من السجل والجلب باللوحة', () async {
      final id = await builder.createPending(plate: 'SOFT-14212');
      final tid = await harness.tenantId();
      final db = await harness.database;
      final now = DateTime.now().toUtc().toIso8601String();

      final n = await ServiceOrdersSqlOps.softDeleteServiceOrderById(
        db,
        tid,
        id: id,
        nowIso: now,
      );
      expect(n, 1);

      final hard = await db.query(
        'service_orders',
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(hard, hasLength(1));
      expect(hard.first['deletedAt'], isNotNull);

      expect(
        await OilChangeOrdersRepository.instance.getOilChangeOrderById(id),
        isNull,
      );
      final log = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        searchQuery: 'SOFT-14212',
      );
      expect(log.any((r) => (r['id'] as num?)?.toInt() == id), isFalse);
      expect(
        await OilChangeOrdersRepository.instance
            .getLatestOilChangeByPlate('SOFT-14212'),
        isNull,
      );
    });

    test('حقن SQL في البحث لا يفرّغ الجدول ولا يكسر العزل', () async {
      await builder.createPending(plate: 'SAFE-100');
      await builder.createPending(plate: 'SAFE-200');
      final db = await harness.database;
      await ServiceOrdersSqlOps.insertServiceOrder(
        db,
        999,
        oilTestOrderPayload(deviceSerial: 'HACK-999'),
      );

      const payloads = [
        "' OR 1=1 --",
        "'; DROP TABLE service_orders; --",
        '%\' OR deviceSerial LIKE \'%',
        '1; DELETE FROM service_orders',
      ];
      for (final q in payloads) {
        final hits =
            await OilChangeOrdersRepository.instance.getOilChangeLogPage(
          searchQuery: q,
        );
        expect(
          hits.any((r) => (r['deviceSerial'] ?? '') == 'HACK-999'),
          isFalse,
          reason: 'البحث تسريب مستأجر آخر عبر: $q',
        );
      }

      final still =
          await OilChangeOrdersRepository.instance.getOilChangeLogPage();
      expect(
        still.where((r) => (r['deviceSerial'] ?? '').toString().startsWith('SAFE-')),
        hasLength(2),
      );
    });

    test('جلب اللوحة بالأرقام العربية يطابق البطاقة المحلية فقط', () async {
      await builder.createPending(plate: basraPlate);
      final hit = await OilChangeOrdersRepository.instance
          .getLatestOilChangeByPlate(basraPlateArabicIndic);
      expect(hit, isNotNull);
      expect(hit!['deviceSerial'], basraPlate);
      expect(
        OilChangeLookupNormalize.normalizePlateKey(basraPlateArabicIndic),
        OilChangeLookupNormalize.normalizePlateKey(basraPlateSpaced),
      );
    });
  });

  group('مزامنة طابور بطاقات غيار الزيت', () {
    late OilChangeTestHarness harness;
    late ServiceOrderBuilder builder;
    late OfflineHelper offline;
    late RealtimeSimulator realtime;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      builder = ServiceOrderBuilder(harness);
      offline = OfflineHelper(harness);
      realtime = RealtimeSimulator(harness);
    });

    test('إنشاء أوفلاين يبقي الطابور معلّقاً حتى عودة الشبكة', () async {
      offline.down();
      final id = await builder.createPending(plate: 'SYNC-14212');
      expect(
        await harness.countSyncQueuePending(
          entityType: SyncEntityTypes.serviceOrder,
        ),
        greaterThan(0),
      );

      final log = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        searchQuery: 'SYNC-14212',
      );
      expect(log.any((r) => (r['id'] as num?)?.toInt() == id), isTrue);

      offline.up();
      await realtime.processPendingSync();
      expect(await harness.countSyncQueuePending(), 0);
    });

    test('ترقيم السجل بالمؤشر لا يستخدم OFFSET', () async {
      for (var i = 0; i < 12; i++) {
        await builder.createPending(plate: 'PAGE-$i');
      }
      final first = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        limit: 5,
      );
      expect(first, hasLength(5));
      final lastId = (first.last['id'] as num).toInt();
      final second =
          await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        afterId: lastId,
        limit: 5,
      );
      expect(second, hasLength(5));
      final firstIds = first.map((r) => r['id']).toSet();
      expect(second.every((r) => !firstIds.contains(r['id'])), isTrue);
      expect(
        second.every((r) => ((r['id'] as num).toInt()) < lastId),
        isTrue,
      );
    });

    test('المعلّقة لا تختلط بالسجل النشط بعد المزامنة', () async {
      await builder.createPending(plate: 'ACT-SYNC');
      await builder.createSuspended(plate: 'SUS-SYNC');
      final active = await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.active,
      );
      final suspended =
          await OilChangeOrdersRepository.instance.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.suspended,
      );
      expect(active.any((r) => r['deviceSerial'] == 'SUS-SYNC'), isFalse);
      expect(suspended.any((r) => r['deviceSerial'] == 'ACT-SYNC'), isFalse);
    });
  });

  group('طابور واتساب المحلي — عزل المستأجر', () {
    late OilChangeTestHarness harness;

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
    });

    test('صف مستأجر آخر لا يظهر في المعلّق ولا يزيد العداد', () async {
      final outbox = OilChangeWhatsappOutbox.instance;
      await outbox.enqueueFailure(
        customerPhone: basraCustomerPhone,
        customerName: basraCustomerName,
        shopName: basraStoreTitle,
        detailsBlock: 'تفاصيل بطاقة بليزر 14212',
        messageText: '',
        templateParams: const {'customer': basraCustomerName},
        reason: OilChangeWhatsappNotifyReason.noInternet,
        orderId: 14212,
        employeeName: basraTechnician,
      );
      expect(await outbox.pendingCount(), 1);

      final db = await harness.database;
      await db.insert('oil_change_wa_outbox', {
        'tenantId': 999,
        'orderId': 777,
        'customerPhone': '07900000000',
        'customerName': 'محل آخر',
        'shopName': 'غيرنا',
        'detailsBlock': 'سر',
        'messageText': '',
        'employeeName': 'x',
        'templateParams': '{}',
        'reason': 'noInternet',
        'attempts': 1,
        'createdAt': DateTime.now().toIso8601String(),
      });

      expect(await outbox.pendingCount(), 1);
      final pending = await outbox.loadPending();
      expect(pending, hasLength(1));
      expect(pending.single.customerPhone, basraCustomerPhone);
      expect(pending.any((e) => e.orderId == 777), isFalse);
    });
  });

  group('تطبيع اللوحة — أرقام عربية وحقن', () {
    test('يزيل الفواصل ويحوّل الأرقام العربية/الفارسية', () {
      expect(
        OilChangeLookupNormalize.normalizePlateKey('14-212'),
        '14212',
      );
      expect(
        OilChangeLookupNormalize.normalizePlateKey('١٤٢١٢'),
        '14212',
      );
      expect(
        OilChangeLookupNormalize.normalizePlateKey('۱۴۲۱۲'),
        '14212',
      );
      expect(
        OilChangeLookupNormalize.toWesternDigits('٠٧٨٨٤٢٨٩٧١١'),
        '07884289711',
      );
    });

    test('مدخل SQL يبقى قيمة مُعلَّمة لا عبارة تُنفَّذ', () {
      final key = OilChangeLookupNormalize.normalizePlateKey(
        "14212'; DROP TABLE service_orders;--",
      );
      expect(key, contains('14212'));
      expect(OilChangeLookupNormalize.normalizePlateKey(basraPlate), '14212');
      expect(key, isNot(equals('14212')));
    });
  });
}
