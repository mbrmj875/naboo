import 'dart:convert';

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
    );
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
    );
  }
}
