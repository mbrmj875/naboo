import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_invoice_builder.dart';
import 'package:naboo/verticals/oil_change/services/oil_change_orders_repository.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_agreed_total.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_filter_format.dart';
import 'package:naboo/verticals/oil_change/utils/oil_change_order_status.dart';

import 'helpers/oil_change_test_harness.dart';

/// دورة حياة بطاقة غيار الزيت: إنشاء → تعديل → تعليق → استكمال منطقياً →
/// حذف معلّقة → إنشاء بطاقة جديدة لنفس اللوحة.
void main() {
  setUpAll(initOilChangeTestEnvironment);

  group('دورة حياة بطاقة الزيت (إنشاء/تعديل/تعليق/حذف/جديد)', () {
    late OilChangeTestHarness harness;
    late OilChangeOrdersRepository repo;

    const oilLiters = 6.0;
    const sellPerLiterFils = 12000000; // 12,000 د.ع
    const oilFils = 72000000; // 72,000
    const filterFils = 25000000; // 25,000
    const fullFils = oilFils + filterFils; // 97,000
    const plate = 'LIFE-97097';

    setUp(() async {
      harness = OilChangeTestHarness.instance;
      await harness.reset();
      await harness.configureServiceOnly();
      repo = OilChangeOrdersRepository.instance;
    });

    Future<int> _createCardWithOilAndFilter({
      required int agreedFils,
      String status = 'pending',
    }) {
      final filtersJson = encodeOilFiltersJson(const [
        OilFilterLineData(
          code: 'engine',
          name: 'فلتر محرك',
          priceFils: filterFils,
        ),
      ]);
      return repo.createOilChangeOrder(
        customerNameSnapshot: 'جعفر اختبار',
        deviceName: 'تويوتا',
        deviceSerial: plate,
        carModel: 'كورولا',
        oilType: 'كاسترول',
        oilViscosity: '5W-30',
        oilSize: '6L',
        oilLitersUsed: oilLiters,
        oilSellPerLiterFils: sellPerLiterFils,
        engineFilterName: 'فلتر محرك',
        engineFilterPriceFils: filterFils,
        oilFiltersJson: filtersJson,
        estimatedPriceFils: fullFils,
        agreedPriceFils: agreedFils,
        advancePaymentFils: agreedFils,
        status: status,
        technicianName: 'فني اختبار',
      );
    }

    test('إنشاء بطاقة جديدة بزيت+فلتر يحفظ البنود والإجمالي الكامل', () async {
      final id = await _createCardWithOilAndFilter(agreedFils: fullFils);
      final row = await repo.getOilChangeOrderById(id);
      expect(row, isNotNull);
      expect(row!['deviceSerial'], plate);
      expect(row['agreedPriceFils'], fullFils);
      expect(
        OilChangeAgreedTotal.estimateOilAndFiltersFilsFromRow(row),
        fullFils,
      );
      final filters = oilFilterLinesDataFromRow(row);
      expect(filters, isNotEmpty);
      expect(filters.first.priceFils, filterFils);
    });

    test('تعديل بطاقة: تحديث ملاحظات وإجمالي بعد إصلاح قيمة ناقصة', () async {
      final id = await _createCardWithOilAndFilter(agreedFils: oilFils);
      var row = await repo.getOilChangeOrderById(id);
      expect(row, isNotNull);

      final components =
          OilChangeAgreedTotal.estimateOilAndFiltersFilsFromRow(row!);
      expect(components, fullFils);

      final manual = OilChangeAgreedTotal.isManualOnHydration(
        agreedFils: (row['agreedPriceFils'] as num?)?.toInt(),
        cardGrandFils: components,
      );
      expect(manual, isFalse, reason: 'الإجمالي الناقص يجب ألا يُجمَّد يدوياً');

      final corrected = OilChangeAgreedTotal.agreedFilsForSave(
        agreedFils: (row['agreedPriceFils'] as num?)?.toInt() ?? 0,
        cardGrandFils: components,
        manuallyEdited: manual,
      );
      expect(corrected, fullFils);

      await repo.updateOilChangeOrder(
        id,
        agreedPriceFils: corrected,
        advancePaymentFils: corrected,
        issueDescription: 'تم تصحيح الإجمالي',
        technicianName: 'فني محدّث',
      );

      row = await repo.getOilChangeOrderById(id);
      expect(row!['agreedPriceFils'], fullFils);
      expect(row['issueDescription'], 'تم تصحيح الإجمالي');
      expect(row['technicianName'], 'فني محدّث');
    });

    test('تعليق → قراءة كاستكمال → حفظ إجمالي كامل → إعادة تعليق', () async {
      final id = await _createCardWithOilAndFilter(
        agreedFils: oilFils,
        status: OilChangeOrderStatus.suspended,
      );

      var row = await repo.getOilChangeOrderById(id);
      expect(OilChangeOrderStatus.isSuspended(row!), isTrue);

      final components =
          OilChangeAgreedTotal.estimateOilAndFiltersFilsFromRow(row);
      final manual = OilChangeAgreedTotal.isManualOnHydration(
        agreedFils: (row['agreedPriceFils'] as num?)?.toInt(),
        cardGrandFils: components,
      );
      final checkout = OilChangeAgreedTotal.checkoutTotalFils(
        agreedFils: (row['agreedPriceFils'] as num?)?.toInt() ?? 0,
        cardGrandFils: components,
        manuallyEdited: manual,
      );
      expect(checkout, fullFils);

      await repo.updateOilChangeOrder(
        id,
        agreedPriceFils: checkout,
        advancePaymentFils: checkout,
        status: OilChangeOrderStatus.suspended,
        issueDescription: 'إعادة تعليق بعد التصحيح',
      );

      row = await repo.getOilChangeOrderById(id);
      expect(OilChangeOrderStatus.isSuspended(row!), isTrue);
      expect(row['agreedPriceFils'], fullFils);
      expect(
        OilChangeAgreedTotal.estimateOilAndFiltersFilsFromRow(row),
        fullFils,
      );
    });

    test('حذف معلّقة (إسقاط) ثم إنشاء بطاقة جديدة لنفس اللوحة', () async {
      final oldId = await _createCardWithOilAndFilter(
        agreedFils: fullFils,
        status: OilChangeOrderStatus.suspended,
      );

      final discarded = await repo.discardSuspendedOilChangeOrder(oldId);
      expect(discarded, isTrue);

      final gone = await repo.getOilChangeOrderById(oldId);
      expect(gone, isNull, reason: 'الحذف المنطقي يخفي البطاقة من الاستعلام');

      final suspended = await repo.getOilChangeLogPage(
        statusFilter: OilChangeLogStatusFilter.suspended,
      );
      expect(
        suspended.any((r) => (r['id'] as num?)?.toInt() == oldId),
        isFalse,
      );

      final newId = await _createCardWithOilAndFilter(agreedFils: fullFils);
      expect(newId, isNot(oldId));
      final neu = await repo.getOilChangeOrderById(newId);
      expect(neu!['deviceSerial'], plate);
      expect(neu['agreedPriceFils'], fullFils);
      expect(neu['status'], 'pending');
    });

    test('لا يُسمح بإسقاط بطاقة غير معلّقة', () async {
      final pendingId = await _createCardWithOilAndFilter(agreedFils: fullFils);
      expect(await repo.discardSuspendedOilChangeOrder(pendingId), isFalse);

      final deliveredId = await _createCardWithOilAndFilter(agreedFils: fullFils);
      await repo.updateOilChangeOrder(deliveredId, status: 'delivered');
      expect(await repo.discardSuspendedOilChangeOrder(deliveredId), isFalse);
    });

    test('فاتورة من بطاقة مصحّحة لا تُنقِص الفلتر', () async {
      final id = await _createCardWithOilAndFilter(agreedFils: fullFils);
      final row = await repo.getOilChangeOrderById(id);
      expect(row, isNotNull);

      expect(OilChangeInvoiceBuilder.orderTotalFils(row!), fullFils);
      final items = await OilChangeInvoiceBuilder.buildItems(row);
      expect(OilChangeInvoiceBuilder.itemsTotalFils(items), fullFils);
    });

    test('فاتورة بإجمالي ناقص محفوظ قديم تُصحَّح عبر سياسة الحفظ قبل البناء', () async {
      final id = await _createCardWithOilAndFilter(agreedFils: oilFils);
      final row = await repo.getOilChangeOrderById(id);
      final components =
          OilChangeAgreedTotal.estimateOilAndFiltersFilsFromRow(row!);
      final fixed = OilChangeAgreedTotal.agreedFilsForSave(
        agreedFils: oilFils,
        cardGrandFils: components,
        manuallyEdited: false,
      );
      await repo.updateOilChangeOrder(id, agreedPriceFils: fixed);

      final fixedRow = await repo.getOilChangeOrderById(id);
      final items = await OilChangeInvoiceBuilder.buildItems(fixedRow!);
      expect(OilChangeInvoiceBuilder.itemsTotalFils(items), fullFils);
    });
  });
}
