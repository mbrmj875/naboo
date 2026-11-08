import 'package:sqflite/sqflite.dart';

import '../../../services/service_order_kinds.dart';
import '../../oil_change/utils/oil_change_lookup_normalize.dart';
import '../../oil_change/utils/oil_change_order_status.dart';
import 'wash_offer_engine.dart';

/// يقرأ غسلات وغيارات سيارة من القاعدة المحلية لمحرّك العروض.
///
/// يُستبعد: المحذوف، والملغى، والمعلّق، وما أُرجعت فاتورته.
/// قيد معروف: بطاقة من جهاز آخر لم تُزامن بعد لا تُحسب حتى تصل.
abstract final class WashOfferHistoryLoader {
  static Future<WashOfferHistory> load(
    DatabaseExecutor db,
    int tenantId, {
    required String plate,
    required DateTime since,
    int? excludeOrderId,
  }) async {
    final key = OilChangeLookupNormalize.normalizePlateKey(plate);
    if (key.isEmpty) return const WashOfferHistory();
    final rows = await db.rawQuery(
      '''
      SELECT so.id, so.orderKind, so.createdAt, so.deviceSerial,
             so.requestedServices, so.washOfferCode
      FROM service_orders so
      LEFT JOIN invoices i ON i.id = so.invoiceId AND i.tenantId = so.tenantId
      WHERE so.tenantId = ?
        AND so.deletedAt IS NULL
        AND so.orderKind IN (?, ?)
        AND so.status NOT IN (?, ?)
        AND so.createdAt >= ?
        AND IFNULL(i.isReturned, 0) = 0
        AND (i.id IS NULL OR NOT EXISTS (
          SELECT 1 FROM invoices r
          WHERE r.isReturned = 1 AND r.originalInvoiceId = i.id
            AND r.tenantId = so.tenantId AND r.deleted_at IS NULL
        ))
      ORDER BY so.createdAt ASC
      ''',
      [
        tenantId,
        ServiceOrderKinds.carWash,
        ServiceOrderKinds.oilChange,
        OilChangeOrderStatus.cancelled,
        OilChangeOrderStatus.suspended,
        since.toUtc().toIso8601String(),
      ],
    );
    final washes = <WashVisit>[];
    final oil = <DateTime>[];
    for (final r in rows) {
      if (excludeOrderId != null &&
          (r['id'] as num?)?.toInt() == excludeOrderId) {
        continue;
      }
      final serial = (r['deviceSerial'] ?? '').toString();
      if (OilChangeLookupNormalize.normalizePlateKey(serial) != key) continue;
      final at = DateTime.tryParse((r['createdAt'] ?? '').toString());
      if (at == null) continue;
      if (r['orderKind'] == ServiceOrderKinds.carWash) {
        final names = (r['requestedServices'] ?? '')
            .toString()
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final code = (r['washOfferCode'] ?? '').toString().trim();
        washes.add(
          WashVisit(
            at: at,
            offerCode: code.isEmpty ? null : code,
            serviceNames: names,
          ),
        );
      } else {
        oil.add(at);
      }
    }
    return WashOfferHistory(washes: washes, oilChanges: oil);
  }
}
