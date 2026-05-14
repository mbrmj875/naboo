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
    required this.receiptShowBarcode,
    required this.receiptShowQr,
    required this.receiptShowBuyerAddressQr,
    required this.storeTitleLine,
    required this.footerExtra,
  });

  factory PrintSettingsData.defaults() => const PrintSettingsData(
        paperFormat: PrintPaperFormat.thermal80,
        receiptShowBarcode: true,
        receiptShowQr: true,
        receiptShowBuyerAddressQr: false,
        storeTitleLine: '',
        footerExtra: '',
      );

  final PrintPaperFormat paperFormat;
  final bool receiptShowBarcode;
  final bool receiptShowQr;

  /// QR ثانٍ يوجّه إلى عنوان المشتري على خرائط Google عند وجود نص في حقل العنوان.
  final bool receiptShowBuyerAddressQr;

  /// سطر يظهر أعلى «إيصال بيع» (اسم المتجر أو الشعار النصي).
  final String storeTitleLine;

  /// أسطر إضافية أسفل الإيصال (شروط، هاتف، شكر).
  final String footerExtra;

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
        'receiptShowBarcode': receiptShowBarcode,
        'receiptShowQr': receiptShowQr,
        'receiptShowBuyerAddressQr': receiptShowBuyerAddressQr,
        'storeTitleLine': storeTitleLine,
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
      receiptShowBarcode:
          m['receiptShowBarcode'] as bool? ?? d.receiptShowBarcode,
      receiptShowQr: m['receiptShowQr'] as bool? ?? d.receiptShowQr,
      receiptShowBuyerAddressQr:
          m['receiptShowBuyerAddressQr'] as bool? ?? d.receiptShowBuyerAddressQr,
      storeTitleLine: m['storeTitleLine'] as String? ?? d.storeTitleLine,
      footerExtra: m['footerExtra'] as String? ?? d.footerExtra,
    );
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
    bool? receiptShowBarcode,
    bool? receiptShowQr,
    bool? receiptShowBuyerAddressQr,
    String? storeTitleLine,
    String? footerExtra,
  }) {
    return PrintSettingsData(
      paperFormat: paperFormat ?? this.paperFormat,
      receiptShowBarcode: receiptShowBarcode ?? this.receiptShowBarcode,
      receiptShowQr: receiptShowQr ?? this.receiptShowQr,
      receiptShowBuyerAddressQr:
          receiptShowBuyerAddressQr ?? this.receiptShowBuyerAddressQr,
      storeTitleLine: storeTitleLine ?? this.storeTitleLine,
      footerExtra: footerExtra ?? this.footerExtra,
    );
  }
}
