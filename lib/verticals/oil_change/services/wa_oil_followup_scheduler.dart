import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';
import 'wa_oil_followup_copy.dart';

/// جدولة تذكير بعد حفظ بطاقة غيار — مستقل عن إرسال البطاقة الفوري.
class WaOilFollowupScheduler {
  WaOilFollowupScheduler._();

  static final WaOilFollowupScheduler instance = WaOilFollowupScheduler._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> enqueueAfterSave({
    required int? orderId,
    required String customerPhone,
    required Map<String, dynamic> order,
    required String storeTitle,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null || orderId == null || orderId <= 0) return;
    final phone = customerPhone.trim();
    if (phone.length < 8) return;

    final name = (order['customerNameSnapshot'] ?? '').toString().trim();
    final car = _carLabel(order);
    final odoCur = (order['odometerCurrent'] ?? '').toString().trim();
    final odoNext = (order['odometerNext'] ?? '').toString().trim();
    final visit = _visitDate(order);

    final payload = {
      'customer_name': name.isEmpty ? 'عميلنا الكريم' : name,
      'car': car,
      'shop': storeTitle.trim().isEmpty ? 'المحل' : storeTitle.trim(),
      'odometer_current': odoCur.isEmpty ? '—' : odoCur,
      'odometer_next': odoNext.isEmpty ? '—' : odoNext,
      'visit_date': visit,
    };

    try {
      await _client.rpc('wa_followup_schedule_job', params: {
        'p_order_ref': orderId.toString(),
        'p_phone': phone,
        'p_payload': payload,
        'p_saved_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      if (_isMissingSchema(e)) {
        AppLogger.warn('wa_followup', 'schema missing — skip schedule');
        return;
      }
      AppLogger.warn('wa_followup', 'schedule failed: ${e.message}');
    } catch (e, st) {
      AppLogger.error('wa_followup', 'schedule error', e, st);
    }
  }

  static String _carLabel(Map<String, dynamic> order) {
    final parts = <String>[
      (order['deviceName'] ?? '').toString().trim(),
      (order['carModel'] ?? '').toString().trim(),
    ].where((s) => s.isNotEmpty);
    if (parts.isEmpty) return 'سيارتكم';
    return parts.join(' · ');
  }

  static String _visitDate(Map<String, dynamic> order) {
    final raw = order['createdAt'] ?? order['created_at'] ?? order['date'];
    final dt = DateTime.tryParse(raw?.toString() ?? '');
    if (dt == null) {
      return DateFormat('d MMMM y', 'ar_SA').format(DateTime.now());
    }
    return DateFormat('d MMMM y', 'ar_SA').format(dt.toLocal());
  }

  bool _isMissingSchema(PostgrestException e) {
    final m = (e.message).toLowerCase();
    return e.code == '42P01' ||
        e.code == '42883' ||
        m.contains('wa_followup') ||
        m.contains('does not exist');
  }
}
