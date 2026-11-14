import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';

/// أحجام ورق شائعة في أنظمة البيع بالتجزئة.
enum PrintPaperFormat {
  /// حراري ضيق (~58 مم)
  thermal58,

  /// حراري قياسي (~80 مم)
  thermal80,

  /// A4 للفواتير أو الإيصالات التفصيلية
  a4,
}

/// إعدادات طباعة الإيصالات والمستندات — تُخزَّن في [print_settings] كـ JSON.
class PrintSettingsData {
  const PrintSettingsData({
    required this.paperFormat,
    required this.thermalEscPosEnabled,
    required this.thermalLanHost,
    required this.thermalLanPort,
    required this.thermalLanTimeoutMs,
    required this.receiptShowBarcode,
    required this.receiptShowQr,
    required this.receiptShowBuyerAddressQr,
    required this.storeTitleLine,
    required this.storeAddress,
    required this.storePhones,
    required this.footerExtra,
    this.storeLatitude,
    this.storeLongitude,
    this.storeLogoBase64 = '',
  });

  factory PrintSettingsData.defaults() => const PrintSettingsData(
        paperFormat: PrintPaperFormat.thermal80,
        thermalEscPosEnabled: false,
        thermalLanHost: '',
        thermalLanPort: 9100,
        thermalLanTimeoutMs: 4000,
        receiptShowBarcode: true,
        receiptShowQr: true,
        receiptShowBuyerAddressQr: false,
        storeTitleLine: '',
        storeAddress: '',
        storePhones: [],
        footerExtra: '',
      );

  final PrintPaperFormat paperFormat;
  final bool thermalEscPosEnabled;
  final String thermalLanHost;
  final int thermalLanPort;
  final int thermalLanTimeoutMs;
  final bool receiptShowBarcode;
  final bool receiptShowQr;

  /// QR ثانٍ يوجّه إلى عنوان المشتري على خرائط Google عند وجود نص في حقل العنوان.
  final bool receiptShowBuyerAddressQr;

  /// سطر يظهر أعلى «إيصال بيع» (اسم المتجر أو الشعار النصي).
  final String storeTitleLine;

  /// عنوان المتجر — يُطبع تحت الاسم في الإيصال.
  final String storeAddress;

  /// أرقام هاتف المتجر — تُطبع في الإيصال (واحد أو أكثر).
  final List<String> storePhones;

  /// أسطر إضافية أسفل الإيصال (شروط، شكر، ملاحظات).
  final String footerExtra;

  /// خط عرض موقع المتجر المحدَّد عبر GPS أو الخريطة — `null` يعني غير محدَّد.
  final double? storeLatitude;

  /// خط طول موقع المتجر المحدَّد عبر GPS أو الخريطة — `null` يعني غير محدَّد.
  final double? storeLongitude;

  /// شعار المتجر مُرمَّزاً base64 (PNG أو JPEG) — فارغ يعني بلا شعار.
  final String storeLogoBase64;

  bool get hasStoreLogo => storeLogoBase64.trim().isNotEmpty;

  /// بايتات الشعار جاهزة للعرض أو الطباعة — `null` إذا كان النص تالفاً.
  Uint8List? get storeLogoBytes {
    final raw = storeLogoBase64.trim();
    if (raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  bool get hasStoreLocation =>
      storeLatitude != null && storeLongitude != null;

  /// رابط خرائط Google لموقع المتجر — للفتح من التطبيق أو وضعه في QR.
  String? get storeMapsUrl {
    if (!hasStoreLocation) return null;
    return 'https://www.google.com/maps/search/?api=1'
        '&query=$storeLatitude,$storeLongitude';
  }

  /// أسطر تحت اسم المتجر في الإيصال (عنوان + هواتف).
  List<String> get receiptStoreContactLines {
    final out = <String>[];
    final addr = storeAddress.trim();
    if (addr.isNotEmpty) out.add(addr);
    for (final p in storePhones) {
      final t = p.trim();
      if (t.isNotEmpty) out.add(t);
    }
    return out;
  }

  /// تنسيق صفحة PDF للمعاينة والطباعة.
  PdfPageFormat get pdfPageFormat {
    const mm = 72.0 / 25.4;
    switch (paperFormat) {
      case PrintPaperFormat.thermal58:
        return const PdfPageFormat(58 * mm, 320 * mm);
      case PrintPaperFormat.thermal80:
        return const PdfPageFormat(80 * mm, 320 * mm);
      case PrintPaperFormat.a4:
        return PdfPageFormat.a4;
    }
  }

  Map<String, dynamic> toJson() => {
        'paperFormat': paperFormat.name,
        'thermalEscPosEnabled': thermalEscPosEnabled,
        'thermalLanHost': thermalLanHost,
        'thermalLanPort': thermalLanPort,
        'thermalLanTimeoutMs': thermalLanTimeoutMs,
        'receiptShowBarcode': receiptShowBarcode,
        'receiptShowQr': receiptShowQr,
        'receiptShowBuyerAddressQr': receiptShowBuyerAddressQr,
        'storeTitleLine': storeTitleLine,
        'storeAddress': storeAddress,
        'storePhones': storePhones,
        'footerExtra': footerExtra,
        'storeLatitude': storeLatitude,
        'storeLongitude': storeLongitude,
        'storeLogoBase64': storeLogoBase64,
      };

  factory PrintSettingsData.fromJson(Map<String, dynamic> m) {
    final d = PrintSettingsData.defaults();
    PrintPaperFormat fmt = d.paperFormat;
    final f = m['paperFormat'] as String?;
    if (f != null) {
      fmt = PrintPaperFormat.values.firstWhere(
        (e) => e.name == f,
        orElse: () => d.paperFormat,
      );
    }
    return PrintSettingsData(
      paperFormat: fmt,
      thermalEscPosEnabled:
          m['thermalEscPosEnabled'] as bool? ?? d.thermalEscPosEnabled,
      thermalLanHost: (m['thermalLanHost'] as String? ?? d.thermalLanHost).trim(),
      thermalLanPort: _readInt(m['thermalLanPort'], d.thermalLanPort),
      thermalLanTimeoutMs: _readInt(
        m['thermalLanTimeoutMs'],
        d.thermalLanTimeoutMs,
      ),
      receiptShowBarcode:
          m['receiptShowBarcode'] as bool? ?? d.receiptShowBarcode,
      receiptShowQr: m['receiptShowQr'] as bool? ?? d.receiptShowQr,
      receiptShowBuyerAddressQr:
          m['receiptShowBuyerAddressQr'] as bool? ?? d.receiptShowBuyerAddressQr,
      storeTitleLine: m['storeTitleLine'] as String? ?? d.storeTitleLine,
      storeAddress: m['storeAddress'] as String? ?? d.storeAddress,
      storePhones: _phonesFromJson(m['storePhones']),
      footerExtra: m['footerExtra'] as String? ?? d.footerExtra,
      storeLatitude: _readLatitude(m['storeLatitude']),
      storeLongitude: _readLongitude(m['storeLongitude']),
      storeLogoBase64: (m['storeLogoBase64'] as String? ?? '').trim(),
    );
  }

  static double? _readLatitude(Object? raw) =>
      _readCoordinate(raw, limit: 90);

  static double? _readLongitude(Object? raw) =>
      _readCoordinate(raw, limit: 180);

  /// إحداثية صالحة فقط — أي قيمة تالفة أو خارج المدى تُعامَل كغير محدَّدة.
  static double? _readCoordinate(Object? raw, {required double limit}) {
    final double? value;
    if (raw is num) {
      value = raw.toDouble();
    } else if (raw is String) {
      value = double.tryParse(raw.trim());
    } else {
      value = null;
    }
    if (value == null || value.isNaN || value.isInfinite) return null;
    if (value < -limit || value > limit) return null;
    return value;
  }

  static List<String> _phonesFromJson(Object? raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    if (raw is String) {
      final t = raw.trim();
      if (t.isEmpty) return const [];
      try {
        final decoded = jsonDecode(t);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false);
        }
      } catch (_) {}
      return t
          .split(RegExp(r'[,;\n]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static int _readInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) {
      final n = int.tryParse(raw.trim());
      if (n != null) return n;
    }
    return fallback;
  }

  static PrintSettingsData mergeFromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return PrintSettingsData.defaults();
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return PrintSettingsData.fromJson(m);
    } catch (_) {
      return PrintSettingsData.defaults();
    }
  }

  String toJsonString() => jsonEncode(toJson());

  PrintSettingsData copyWith({
    PrintPaperFormat? paperFormat,
    bool? thermalEscPosEnabled,
    String? thermalLanHost,
    int? thermalLanPort,
    int? thermalLanTimeoutMs,
    bool? receiptShowBarcode,
    bool? receiptShowQr,
    bool? receiptShowBuyerAddressQr,
    String? storeTitleLine,
    String? storeAddress,
    List<String>? storePhones,
    String? footerExtra,
    double? storeLatitude,
    double? storeLongitude,
    bool clearStoreLocation = false,
    String? storeLogoBase64,
  }) {
    return PrintSettingsData(
      paperFormat: paperFormat ?? this.paperFormat,
      thermalEscPosEnabled: thermalEscPosEnabled ?? this.thermalEscPosEnabled,
      thermalLanHost: thermalLanHost ?? this.thermalLanHost,
      thermalLanPort: thermalLanPort ?? this.thermalLanPort,
      thermalLanTimeoutMs: thermalLanTimeoutMs ?? this.thermalLanTimeoutMs,
      receiptShowBarcode: receiptShowBarcode ?? this.receiptShowBarcode,
      receiptShowQr: receiptShowQr ?? this.receiptShowQr,
      receiptShowBuyerAddressQr:
          receiptShowBuyerAddressQr ?? this.receiptShowBuyerAddressQr,
      storeTitleLine: storeTitleLine ?? this.storeTitleLine,
      storeAddress: storeAddress ?? this.storeAddress,
      storePhones: storePhones ?? this.storePhones,
      footerExtra: footerExtra ?? this.footerExtra,
      storeLatitude:
          clearStoreLocation ? null : storeLatitude ?? this.storeLatitude,
      storeLongitude:
          clearStoreLocation ? null : storeLongitude ?? this.storeLongitude,
      storeLogoBase64: storeLogoBase64 ?? this.storeLogoBase64,
    );
  }
}
