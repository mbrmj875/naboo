import 'package:sqflite/sqflite.dart';

import '../../../services/database_helper.dart';
import '../../../services/returns/returns_offers_db_schema.dart';
import '../../../services/service_order_kinds.dart';
import '../../../services/service_orders_repository.dart';
import '../../../services/tenant_context_service.dart';
import '../../../utils/app_logger.dart';
import '../../car_wash/services/car_wash_checkout_service.dart';
import '../../car_wash/services/wash_offer_engine.dart';
import '../models/oil_card_wash.dart';
import '../utils/oil_change_order_status.dart';

/// طلب الغسيل المرتبط ببطاقة غيار فيها غسلة.
///
/// الغسلة تُعدّ في سجل الغسيل وتقريره كأنها غسلة مستقلة: طلب `car_wash` بلا
/// فاتورة (الفاتورة للبطاقة)، يحمل `parentOrderGlobalId` = global_id البطاقة،
/// وسعره قبل العرض في `estimatedPriceFils` وبعده في `agreedPriceFils`.
class CardWashOrderSync {
  CardWashOrderSync._();
  static final CardWashOrderSync instance = CardWashOrderSync._();

  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// حالة البطاقة لطلب غسيلها: حية، أو منتهية بدليل (ملغاة/مرتجعة)، أو غير
  /// معروفة بعد (الفاتورة لم تصل من جهاز آخر) فلا يُلمس شيء.
  static CardWashParentState parentState({
    required Map<String, Object?> card,
    Map<String, Object?>? invoice,
    bool invoiceReturned = false,
  }) {
    final deleted = (card['deletedAt'] ?? '').toString().trim().isNotEmpty;
    final status = (card['status'] ?? '').toString().trim();
    if (deleted || status == OilChangeOrderStatus.cancelled) {
      return CardWashParentState.ended;
    }
    if (status == OilChangeOrderStatus.suspended) {
      return CardWashParentState.ended;
    }
    final invoiceId = (card['invoiceId'] as num?)?.toInt() ?? 0;
    if (invoiceId <= 0) return CardWashParentState.ended;
    if (invoice == null) return CardWashParentState.unknown;
    final invDeleted = (invoice['deleted_at'] ?? '').toString().trim().isNotEmpty;
    final returned = ((invoice['isReturned'] as num?)?.toInt() ?? 0) != 0;
    if (invDeleted || returned || invoiceReturned) {
      return CardWashParentState.ended;
    }
    return CardWashParentState.alive;
  }

  Future<int> _tenantId() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return t.requireActiveTenantId();
  }

  Future<({Map<String, Object?>? invoice, bool returned})> _invoiceOf(
    DatabaseExecutor db,
    int tenantId,
    int invoiceId,
  ) async {
    if (invoiceId <= 0) return (invoice: null, returned: false);
    final inv = await db.rawQuery(
      'SELECT id, deleted_at, isReturned FROM invoices '
      'WHERE id = ? AND tenantId = ? LIMIT 1',
      [invoiceId, tenantId],
    );
    if (inv.isEmpty) return (invoice: null, returned: false);
    final ret = await db.rawQuery(
      'SELECT 1 FROM invoices WHERE originalInvoiceId = ? AND tenantId = ? '
      'AND IFNULL(isReturned, 0) = 1 AND deleted_at IS NULL LIMIT 1',
      [invoiceId, tenantId],
    );
    return (invoice: inv.first, returned: ret.isNotEmpty);
  }

  /// بعد حفظ البطاقة أو تعديلها أو بيعها: ينشئ طلب الغسيل أو يحدّثه أو يلغيه.
  /// يُستدعى خارج معاملة الحفظ. الفشل يُسجَّل ولا يُفسد البطاقة المحفوظة.
  Future<void> syncForCardId(int cardId) async {
    try {
      final tid = await _tenantId();
      final db = await _dbHelper.database;
      await ensureReturnsAndOffersSchema(db);
      final rows = await db.rawQuery(
        'SELECT * FROM service_orders WHERE id = ? AND tenantId = ? LIMIT 1',
        [cardId, tid],
      );
      if (rows.isEmpty) return;
      await _syncCard(db, tid, rows.first, allowCreate: true);
    } catch (e, st) {
      AppLogger.error('CardWashOrderSync', 'syncForCardId $cardId', e, st);
    }
  }

  /// يطابق طلبات الغسيل المرتبطة مع بطاقاتها (إرجاع أو إلغاء من أي شاشة أو
  /// جهاز). لا ينشئ طلباً جديداً حتى لا يكرّر جهازان الغسلة نفسها.
  Future<void> reconcileLinked() async {
    try {
      final tid = await _tenantId();
      final db = await _dbHelper.database;
      await ensureReturnsAndOffersSchema(db);
      final cards = await db.rawQuery(
        '''
        SELECT p.* FROM service_orders p
        WHERE p.tenantId = ? AND p.global_id IN (
          SELECT w.parentOrderGlobalId FROM service_orders w
          WHERE w.tenantId = ? AND w.orderKind = ?
            AND w.parentOrderGlobalId IS NOT NULL AND w.parentOrderGlobalId != ''
        )
        ''',
        [tid, tid, ServiceOrderKinds.carWash],
      );
      for (final c in cards) {
        await _syncCard(db, tid, c, allowCreate: false);
      }
    } catch (e, st) {
      AppLogger.error('CardWashOrderSync', 'reconcileLinked', e, st);
    }
  }

  Future<void> _syncCard(
    DatabaseExecutor db,
    int tid,
    Map<String, Object?> card,
    {required bool allowCreate}
  ) async {
    final gid = (card['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return;
    final linked = await db.rawQuery(
      'SELECT * FROM service_orders WHERE tenantId = ? AND orderKind = ? '
      'AND parentOrderGlobalId = ? ORDER BY id ASC',
      [tid, ServiceOrderKinds.carWash, gid],
    );
    final existing = linked.isEmpty ? null : linked.first;
    final inv = await _invoiceOf(
      db,
      tid,
      (card['invoiceId'] as num?)?.toInt() ?? 0,
    );
    final state = parentState(
      card: card,
      invoice: inv.invoice,
      invoiceReturned: inv.returned,
    );
    if (state == CardWashParentState.unknown) return;
    final wash = OilCardWash.fromOrder(Map<String, dynamic>.from(card));
    final repo = ServiceOrdersRepository.instance;

    if (state == CardWashParentState.ended || wash == null) {
      // نسخ زائدة من خطأ سابق تُلغى كلها أيضاً.
      for (final w in linked) {
        if ((w['status'] ?? '') == OilChangeOrderStatus.cancelled) continue;
        await repo.updateServiceOrderById(
          (w['id'] as num).toInt(),
          extraColumns: {'status': OilChangeOrderStatus.cancelled},
        );
      }
      return;
    }

    final plate = (card['deviceSerial'] ?? '').toString().trim();
    final columns = <String, Object?>{
      'parentOrderGlobalId': gid,
      'washOfferCode': wash.offerCode ?? WashOfferCodes.withOil,
      'washOfferNote': wash.offerNote,
      'status': OilChangeOrderStatus.delivered,
      'deletedAt': null,
      'invoiceId': null,
    };
    final label = CarWashCheckoutService.washLabel(
      lines: [
        for (final l in wash.lines)
          CarWashLine(name: l.name, priceFils: l.priceFils),
      ],
      plate: plate,
    );
    final services = wash.serviceNames.join(',');
    final customer = (card['customerNameSnapshot'] ?? '').toString().trim();
    final customerId = (card['customerId'] as num?)?.toInt();
    final phone = (card['customerPhone'] ?? '').toString().trim();

    if (existing == null) {
      if (!allowCreate) return;
      await repo.createServiceOrder(
        customerNameSnapshot: customer.isEmpty
            ? CarWashCheckoutService.fallbackCustomerName
            : customer,
        deviceName: label,
        deviceSerial: plate,
        customerId: customerId,
        estimatedPriceFils: wash.grossFils,
        agreedPriceFils: wash.netFils,
        advancePaymentFils: wash.netFils,
        requestedServices: services,
        customerPhone: phone,
        technicianName: wash.washerName,
        orderKind: ServiceOrderKinds.carWash,
        status: OilChangeOrderStatus.delivered,
        issueDescription: 'مع بطاقة الغيار',
        extraColumns: columns,
      );
      return;
    }

    await repo.updateServiceOrderById(
      (existing['id'] as num).toInt(),
      customerNameSnapshot: customer.isEmpty
          ? CarWashCheckoutService.fallbackCustomerName
          : customer,
      deviceName: label,
      deviceSerial: plate,
      estimatedPriceFils: wash.grossFils,
      agreedPriceFils: wash.netFils,
      advancePaymentFils: wash.netFils,
      requestedServices: services,
      customerPhone: phone,
      technicianName: wash.washerName,
      patchCustomerIdField: true,
      customerId: customerId,
      extraColumns: columns,
    );
    for (final dup in linked.skip(1)) {
      if ((dup['status'] ?? '') == OilChangeOrderStatus.cancelled) continue;
      await repo.updateServiceOrderById(
        (dup['id'] as num).toInt(),
        extraColumns: {'status': OilChangeOrderStatus.cancelled},
      );
    }
  }
}

enum CardWashParentState { alive, ended, unknown }
