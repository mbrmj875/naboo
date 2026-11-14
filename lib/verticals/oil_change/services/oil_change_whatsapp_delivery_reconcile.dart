import '../../../utils/app_logger.dart';
import '../utils/whatsapp_delivery_proof_key.dart';
import 'oil_change_whatsapp_gateway_service.dart';
import 'oil_change_whatsapp_messages_repository.dart';
import 'oil_change_whatsapp_outbox.dart';

/// ينظّف «لم يتم الإرسال» عندما يثبت سجل آخر أن نفس البطاقة وصلت.
///
/// قراءة ثم إسقاط محلي أو تعليم السجل الفاشل مرفوضاً. لا يستدعي الإرسال.
class OilChangeWhatsappDeliveryReconcile {
  OilChangeWhatsappDeliveryReconcile._();

  static Future<Set<String>> loadProofKeys() async {
    try {
      final proofs = await OilChangeWhatsappMessagesRepository.instance
          .loadRecentDeliveryProofs();
      final keys = <String>{};
      for (final row in proofs) {
        final key = whatsappDeliveryProofKey(
          orderRef: row.orderRef,
          phone: row.toPhone,
        );
        if (key != null) keys.add(key);
      }
      return keys;
    } catch (e) {
      AppLogger.warn('wa_delivery_reconcile', 'proof load failed :: $e');
      return const {};
    }
  }

  /// يمسح صفوف الجهاز التي لها إثبات وصول. لا يعيد الإرسال.
  static Future<void> discardProvenOutbox() async {
    final proofs = await loadProofKeys();
    if (proofs.isEmpty) return;
    final pending = await OilChangeWhatsappOutbox.instance.loadPending();
    for (final entry in pending) {
      final key = whatsappDeliveryProofKey(
        orderRef: '${entry.orderId}',
        phone: entry.customerPhone,
      );
      if (key == null || !proofs.contains(key)) continue;
      await OilChangeWhatsappOutbox.instance.discard(entry.id);
      AppLogger.info(
        'wa_delivery_reconcile',
        'dropped local outbox id=${entry.id} order=${entry.orderId}',
      );
    }
  }

  /// يُسقط التوأم الفاشل في السحابة إن وُجد إثبات لبطاقة أخرى بنفس الرقم.
  /// يعيد معرّفات السجلات التي أُسقطت من القائمة.
  static Future<Set<String>> dismissProvenFailedTwins(
    List<OilChangeMessageLogEntry> failedRows,
  ) async {
    if (failedRows.isEmpty) return const {};
    final proofs = await loadProofKeys();
    if (proofs.isEmpty) return const {};
    final hidden = <String>{};
    for (final row in failedRows) {
      if (!row.status.isFailure) continue;
      final key = whatsappDeliveryProofKey(
        orderRef: row.orderRef,
        phone: row.toPhone,
      );
      if (key == null || !proofs.contains(key)) continue;
      final result = await OilChangeWhatsappGatewayService.instance
          .dismissFailedMessage(logId: row.id);
      if (!result.ok) continue;
      hidden.add(row.id);
      AppLogger.info(
        'wa_delivery_reconcile',
        'dropped failed twin log=${row.id} order=${row.orderRef}',
      );
    }
    return hidden;
  }
}
