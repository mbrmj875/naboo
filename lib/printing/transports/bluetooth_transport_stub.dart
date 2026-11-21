import 'dart:typed_data';

/// طابعة بلوتوث مقترنة.
class BtPrinter {
  const BtPrinter(this.name, this.address);
  final String name;
  final String address;
}

/// المتصفح لا يصل لطابعات البلوتوث.
abstract final class BluetoothTransport {
  static bool get supported => false;

  static Future<String?> checkReady() async =>
      'البلوتوث غير متاح على هذه المنصة.';

  static Future<List<BtPrinter>> paired() async => const [];

  static Future<void> send(String address, Uint8List bytes) async =>
      throw UnsupportedError('البلوتوث غير متاح على هذه المنصة.');
}
