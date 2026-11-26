import 'dart:convert';

import '../../notifications/notification_event_outbox.dart';
import '../../owner/services/business_audit_log_service.dart';
import '../../utils/app_logger.dart';

/// سطر صار رصيده سالباً بعد بيع أو صرف.
typedef NegativeStockLine = ({int productId, String name, double after});

/// ق-6: البيع بلا رصيد يمر في كل المسارات، ويصل للمالك إشعار «بيع أدى إلى
/// رصيد سالب»، ويُسجَّل الحدث باسم الموظف ومرجعه ليظهر في تقرير المنتجات.
class NegativeStockAlerts {
  NegativeStockAlerts._();

  static const auditType = 'negative_stock_sale';

  /// [source]: `sale` أو `card` أو `direct_sale` أو `voucher_out`.
  static Future<void> notify({
    required String source,
    required String ref,
    required List<NegativeStockLine> lines,
    String staffName = '',
    String actorRole = '',
    String staffGlobalId = '',
    int? userId,
  }) async {
    if (lines.isEmpty) return;
    try {
      await BusinessAuditLogService.instance.record(
        eventType: auditType,
        entityType: source,
        entityId: ref,
        newValueJson: jsonEncode({
          'source': source,
          'lines': [
            for (final l in lines)
              {'productId': l.productId, 'name': l.name, 'after': l.after},
          ],
        }),
        userId: userId,
        username: staffName.isEmpty ? null : staffName,
      );
    } catch (e, st) {
      AppLogger.error('NegativeStock', 'تعذّر تسجيل الرصيد السالب', e, st);
    }
    // مسار الفاتورة العادية يرسل الإشعار بنفسه منذ قبل، فلا يتكرر.
    if (source == 'sale') return;
    await NotificationEventOutbox.instance.record(
      type: 'negative_stock_sale',
      ref: '$source:$ref',
      staffName: staffName,
      actorRole: actorRole,
      staffGlobalId: staffGlobalId,
      payload: {
        'source': source,
        'ref': ref,
        'product_name': lines.first.name,
        'product_id': lines.first.productId,
        'lines_count': lines.length,
      },
    );
  }
}
