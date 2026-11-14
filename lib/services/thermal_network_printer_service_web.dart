import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../utils/app_logger.dart';

/// على الويب: لا TCP مباشر — نحاول جسر طباعة محلي على الجهاز (localhost).
///
/// الجسر الافتراضي: `http://127.0.0.1:19100/print` (انظر `infra/print_bridge/`).
/// يمرّر [host]/[port] كهدف للطابعة الحرارية على الشبكة المحلية عبر الجسر.
class ThermalNetworkPrinterService {
  ThermalNetworkPrinterService._();
  static final ThermalNetworkPrinterService instance =
      ThermalNetworkPrinterService._();

  /// منفذ جسر الطباعة المحلي على جهاز الكاشير.
  static const int bridgePort = 19100;

  Future<void> sendBytes({
    required String host,
    required int port,
    required Uint8List payload,
    int timeoutMs = 4000,
  }) async {
    final h = host.trim();
    if (h.isEmpty) {
      throw const FormatException('عنوان الطابعة فارغ.');
    }
    if (port <= 0 || port > 65535) {
      throw const FormatException('منفذ الطابعة غير صالح.');
    }
    if (payload.isEmpty) {
      throw const FormatException('لا توجد بيانات للطباعة.');
    }

    final uri = Uri.parse('http://127.0.0.1:$bridgePort/print');
    try {
      final res = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'host': h,
              'port': port,
              'payloadBase64': base64Encode(payload),
            }),
          )
          .timeout(Duration(milliseconds: timeoutMs + 2000));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return;
      }
      throw FormatException(
        'جسر الطباعة ردّ بخطأ (${res.statusCode}). تأكد أن خدمة الطباعة المحلية تعمل.',
      );
    } on TimeoutException {
      throw TimeoutException('انتهت مهلة الاتصال بجسر الطباعة المحلي.');
    } catch (e, st) {
      AppLogger.error('ThermalLAN', 'web bridge sendBytes failed', e, st);
      if (e is FormatException) rethrow;
      throw const FormatException(
        'الطباعة الحرارية من المتصفح تحتاج تشغيل جسر الطباعة المحلي على جهاز الكاشير (منفذ 19100)، أو استخدم حفظ/طباعة PDF.',
      );
    }
  }
}
