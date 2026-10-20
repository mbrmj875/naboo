import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

/// مولّد QR ثابت للطاولات — بدون session_seq أو tokens (spec §6.1).
abstract final class RestaurantQrService {
  RestaurantQrService._();

  /// المضيف الكانوني للمنيو العام — HTTPS على naboo.fun (مشفّر).
  static const defaultPublicHost = 'https://naboo.fun';

  static String tableUrl({
    required String tenantSlug,
    required String tableSlug,
    String host = defaultPublicHost,
  }) {
    final t = tenantSlug.trim();
    final s = tableSlug.trim();
    return '$host/m/$t/t/$s';
  }

  static String publicMenuUrl({
    required String tenantSlug,
    String host = defaultPublicHost,
  }) {
    return '$host/m/${tenantSlug.trim()}';
  }

  static Widget qrWidget({
    required String data,
    double size = 180,
    Color color = Colors.black,
  }) {
    return BarcodeWidget(
      barcode: Barcode.qrCode(),
      data: data,
      width: size,
      height: size,
      drawText: false,
      color: color,
    );
  }
}
