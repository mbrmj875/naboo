import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// طابعة بلوتوث مقترنة.
class BtPrinter {
  const BtPrinter(this.name, this.address);
  final String name;
  final String address;
}

/// طابعات البلوتوث الحرارية (Classic SPP) عبر `print_bluetooth_thermal`.
abstract final class BluetoothTransport {
  /// أندرويد هو المسار الرئيسي؛ ويندوز وiOS حسب دعم الطابعة.
  static bool get supported =>
      Platform.isAndroid || Platform.isIOS || Platform.isWindows;

  /// بايتات الدفعة الواحدة: الطابعات الرخيصة لها ذاكرة صغيرة.
  static const _chunk = 2048;

  /// `null` إن كان كل شيء جاهزاً، وإلا رسالة تشرح ما ينقص.
  static Future<String?> checkReady() async {
    if (!supported) return 'البلوتوث غير مدعوم على هذا الجهاز.';
    if (Platform.isAndroid && !await _requestAndroidPermission()) {
      return 'الطباعة بالبلوتوث تحتاج إذن «الأجهزة القريبة». فعّله من إعدادات التطبيق في الهاتف ثم أعد المحاولة.';
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      return 'شغّل البلوتوث في الهاتف أولاً.';
    }
    return null;
  }

  static const _permission = MethodChannel('naboo/bt_permission');

  /// يطلب «الأجهزة القريبة» (أندرويد 12+) وينتظر رد المستخدم. بدونه تعلق
  /// استدعاءات حزمة الطباعة إلى الأبد، فلا نستدعيها قبل الموافقة.
  static Future<bool> _requestAndroidPermission() async {
    try {
      return await _permission.invokeMethod<bool>('request') ?? false;
    } on MissingPluginException {
      return PrintBluetoothThermal.isPermissionBluetoothGranted;
    }
  }

  /// الأجهزة المقترنة من إعدادات البلوتوث في الهاتف.
  static Future<List<BtPrinter>> paired() async {
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return [for (final d in list) BtPrinter(d.name, d.macAdress)];
  }

  static Future<void> send(String address, Uint8List bytes) async {
    final problem = await checkReady();
    if (problem != null) throw StateError(problem);
    var connected = await PrintBluetoothThermal.connectionStatus.timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    if (!connected) {
      connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: address,
      ).timeout(const Duration(seconds: 15), onTimeout: () => false);
    }
    if (!connected) {
      throw StateError(
        'تعذر الاتصال بالطابعة. تأكد أنها مشغّلة وقريبة وغير متصلة بجهاز آخر.',
      );
    }
    for (var i = 0; i < bytes.length; i += _chunk) {
      final end = i + _chunk < bytes.length ? i + _chunk : bytes.length;
      final ok = await PrintBluetoothThermal.writeBytes(
        Uint8List.sublistView(bytes, i, end),
      ).timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (!ok) {
        await PrintBluetoothThermal.disconnect;
        throw StateError('انقطع الاتصال بالطابعة أثناء الطباعة.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 12));
    }
  }
}
