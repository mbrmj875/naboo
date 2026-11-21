import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../utils/app_logger.dart';

/// إرسال ESC/POS خام إلى طابعة شبكة عبر TCP (غالباً المنفذ 9100).
class ThermalNetworkPrinterService {
  ThermalNetworkPrinterService._();
  static final ThermalNetworkPrinterService instance =
      ThermalNetworkPrinterService._();

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

    Socket? socket;
    try {
      socket = await Socket.connect(
        h,
        port,
        timeout: Duration(milliseconds: timeoutMs),
      );
      socket.add(payload);
      await socket.flush().timeout(Duration(milliseconds: timeoutMs));
    } on TimeoutException {
      throw TimeoutException('انتهت مهلة الاتصال بالطابعة.');
    } catch (e, st) {
      AppLogger.error('ThermalLAN', 'sendBytes failed', e, st);
      rethrow;
    } finally {
      await socket?.close();
    }
  }
}
