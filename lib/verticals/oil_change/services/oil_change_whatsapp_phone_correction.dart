import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/database_helper.dart';
import '../../../services/service_orders_repository.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/customer_validation.dart';
import 'oil_change_orders_repository.dart';
import 'oil_change_whatsapp_gateway_service.dart';
import 'oil_change_whatsapp_outbox.dart';

/// يصحّح رقم الزبون في البطاقة + ملف العميل + الطابور المحلي + سجل السحابة،
/// ثم يعيد إرسال بطاقة واتساب للرقم الجديد.
class OilChangeWhatsappPhoneCorrection {
  OilChangeWhatsappPhoneCorrection._();

  static final OilChangeWhatsappPhoneCorrection instance =
      OilChangeWhatsappPhoneCorrection._();

  /// يعيد null عند النجاح، أو رسالة عربية عند الفشل.
  Future<String?> correctPhoneAndResend({
    required String newPhoneRaw,
    required String oldPhoneRaw,
    required String logId,
    required String orderRef,
    required String customerName,
    required String shopName,
    required String detailsBlock,
    required Map<String, String> templateParams,
    required String employeeName,
  }) async {
    final e164 = CustomerValidation.toE164IraqMobile(newPhoneRaw);
    if (e164 == null) {
      return 'أدخل رقم واتساب صالحاً (مثل 07XXXXXXXXX)';
    }
    final newPhone = e164;
    final oldPhone = CustomerValidation.toE164IraqMobile(oldPhoneRaw) ??
        oldPhoneRaw.trim();

    final orderId = int.tryParse(orderRef.trim()) ?? 0;
    try {
      if (orderId > 0) {
        await OilChangeOrdersRepository.instance.updateOilChangeOrder(
          orderId,
          customerPhone: newPhone,
        );
        final order =
            await ServiceOrdersRepository.instance.getServiceOrderById(orderId);
        final customerId = (order?['customerId'] as num?)?.toInt() ?? 0;
        if (customerId > 0) {
          await _updateCustomerPhones(
            customerId: customerId,
            oldPhone: oldPhone,
            newPhone: newPhone,
          );
        }
        await OilChangeWhatsappOutbox.instance.updatePhoneForOrder(
          orderId: orderId,
          newPhone: newPhone,
        );
      }

      await _updateCloudLogPhone(logId: logId, newPhone: newPhone);

      // ثابت لنفس (سجل + رقم جديد) — بدون timestamp حتى لا يُكرَّر بعد Timeout.
      final phoneKey =
          CustomerValidation.normalizePhoneDigits(newPhone) ?? newPhone;
      final attemptId =
          'phonefix_${logId.trim().isEmpty ? 'order_$orderId' : logId.trim()}_$phoneKey';
      final result =
          await OilChangeWhatsappGatewayService.instance.sendOilChangeCard(
        customerPhone: newPhone,
        customerName: customerName,
        shopName: shopName,
        detailsBlock: detailsBlock,
        templateParams: {
          ...templateParams,
          if (customerName.isNotEmpty) 'customer': customerName,
        },
        orderId: orderId > 0 ? orderId : null,
        employeeName: employeeName,
        resend: true,
        attemptId: attemptId,
        originalLogId: logId.isEmpty ? null : logId,
      );

      if (!result.ok) {
        AppLogger.warn(
          'wa_phone_fix',
          'resend after phone fix failed: ${result.reason} ${result.detail}',
        );
        return 'تم حفظ الرقم، لكن تعذّر إرسال واتساب الآن — أعد المحاولة من القائمة';
      }
      return null;
    } catch (e, st) {
      AppLogger.error('wa_phone_fix', 'correctPhoneAndResend failed', e, st);
      return 'تعذّر تصحيح الرقم — أعد المحاولة';
    }
  }

  Future<void> _updateCustomerPhones({
    required int customerId,
    required String oldPhone,
    required String newPhone,
  }) async {
    final db = await DatabaseHelper().database;
    final rows = await db.query(
      'customers',
      columns: ['id', 'phone', 'name'],
      where: 'id = ?',
      whereArgs: [customerId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final current = (rows.first['phone'] ?? '').toString().trim();
    final oldDigits = CustomerValidation.normalizePhoneDigits(oldPhone) ?? '';
    final currentDigits =
        CustomerValidation.normalizePhoneDigits(current) ?? '';

    if (current.isEmpty ||
        currentDigits == oldDigits ||
        oldDigits.isEmpty) {
      await db.update(
        'customers',
        {'phone': newPhone},
        where: 'id = ?',
        whereArgs: [customerId],
      );
    }

    if (oldDigits.isNotEmpty) {
      final extras = await db.query(
        'customer_extra_phones',
        columns: ['id', 'phone'],
        where: 'customerId = ?',
        whereArgs: [customerId],
      );
      for (final row in extras) {
        final p = (row['phone'] ?? '').toString();
        final d = CustomerValidation.normalizePhoneDigits(p) ?? '';
        if (d == oldDigits) {
          await db.update(
            'customer_extra_phones',
            {'phone': newPhone},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    }
  }

  Future<void> _updateCloudLogPhone({
    required String logId,
    required String newPhone,
  }) async {
    if (logId.trim().isEmpty) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('whatsapp_message_logs')
          .update({'to_phone': newPhone})
          .eq('id', logId)
          .eq('tenant_user_id', user.id)
          .eq('status', 'failed');
    } catch (e) {
      AppLogger.warn('wa_phone_fix', 'cloud to_phone update: $e');
    }
  }
}
