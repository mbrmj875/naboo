/// حمولة QR لربط بطاقة الموظف بفتح الوردية (اسم + رمز من جدول المستخدمين).
class StaffQrData {
  const StaffQrData({required this.userId, required this.pin});
  final int userId;
  final String pin;
}

class StaffIdentityQr {
  StaffIdentityQr._();

  static const String scheme = 'basra_shift';
  static const String version = 'v1';

  static String encode({required int userId, required String pin}) {
    final p = pin.trim();
    return '$scheme:$version:$userId:$p';
  }

  static StaffQrData? tryParse(String? raw) {
    if (raw == null) return null;
    // أجهزة HID غالباً تُلحق Enter/CR؛ قد يُرسل الماسح سطراً إضافياً.
    final lines = raw.split(RegExp(r'[\r\n]+'));
    String? s;
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (t.startsWith('$scheme:$version:')) {
        s = t;
        break;
      }
    }
    s ??= raw.trim();
    if (!s.startsWith('$scheme:$version:')) return null;
    final parts = s.split(':');
    if (parts.length < 4) return null;
    final id = int.tryParse(parts[2]);
    if (id == null || id <= 0) return null;
    final pin = parts.sublist(3).join(':').trim();
    if (pin.isEmpty) return null;
    return StaffQrData(userId: id, pin: pin);
  }
}
