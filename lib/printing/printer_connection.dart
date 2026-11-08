import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/print_settings_data.dart';
import 'receipt_renderer.dart';

/// كيف يصل هذا الجهاز إلى طابعته.
enum PrinterType {
  none('لا توجد طابعة'),
  bluetooth('طابعة بلوتوث'),
  lan('طابعة شبكة (Wi-Fi / كابل)'),
  system('طابعة النظام / PDF');

  const PrinterType(this.label);
  final String label;
}

/// إعداد الطابعة على هذا الجهاز فقط (لا يُزامَن): كل جهاز كاشير له طابعته.
class PrinterConnection {
  const PrinterConnection({
    this.type = PrinterType.none,
    this.paper = ReceiptPaper.mm58,
    this.btAddress = '',
    this.btName = '',
    this.lanHost = '',
    this.lanPort = 9100,
  });

  static const _key = 'naboo.printer_connection.v1';

  final PrinterType type;
  final ReceiptPaper paper;
  final String btAddress;
  final String btName;
  final String lanHost;
  final int lanPort;

  /// طابعة حرارية (ESC/POS): أبيض وأسود ولفافة 58/80 مم فقط.
  bool get isThermal =>
      type == PrinterType.bluetooth || type == PrinterType.lan;

  /// الحرارية لا تطبع A4، فإن اختير مقاس كبير مع طابعة حرارية نرجع لـ 80 مم.
  ReceiptPaper get effectivePaper =>
      isThermal && !paper.isRoll ? ReceiptPaper.mm80 : paper;

  bool get isConfigured => switch (type) {
    PrinterType.none => false,
    PrinterType.bluetooth => btAddress.isNotEmpty,
    PrinterType.lan => lanHost.trim().isNotEmpty,
    PrinterType.system => true,
  };

  /// وصف قصير للحالة.
  String get summary => switch (type) {
    PrinterType.none => 'لم تُربط طابعة بعد',
    PrinterType.bluetooth =>
      btAddress.isEmpty ? 'بلوتوث — اختر الطابعة' : 'بلوتوث: ${btName.isEmpty ? btAddress : btName} · ${effectivePaper.label}',
    PrinterType.lan =>
      lanHost.isEmpty ? 'شبكة — أدخل العنوان' : 'شبكة: $lanHost:$lanPort · ${effectivePaper.label}',
    PrinterType.system => 'طابعة النظام · ${paper.label}',
  };

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'paper': paper.name,
    'btAddress': btAddress,
    'btName': btName,
    'lanHost': lanHost,
    'lanPort': lanPort,
  };

  factory PrinterConnection.fromJson(Map<String, dynamic> m) =>
      PrinterConnection(
        type: PrinterType.values.firstWhere(
          (e) => e.name == m['type'],
          orElse: () => PrinterType.none,
        ),
        paper: ReceiptPaper.values.firstWhere(
          (e) => e.name == m['paper'],
          orElse: () => ReceiptPaper.mm58,
        ),
        btAddress: (m['btAddress'] ?? '').toString(),
        btName: (m['btName'] ?? '').toString(),
        lanHost: (m['lanHost'] ?? '').toString().trim(),
        lanPort: (m['lanPort'] as num?)?.toInt() ?? 9100,
      );

  PrinterConnection copyWith({
    PrinterType? type,
    ReceiptPaper? paper,
    String? btAddress,
    String? btName,
    String? lanHost,
    int? lanPort,
  }) => PrinterConnection(
    type: type ?? this.type,
    paper: paper ?? this.paper,
    btAddress: btAddress ?? this.btAddress,
    btName: btName ?? this.btName,
    lanHost: lanHost ?? this.lanHost,
    lanPort: lanPort ?? this.lanPort,
  );

  /// يقرأ إعداد الجهاز. أول مرة: يرث طابعة الشبكة من الإعدادات القديمة إن وُجدت.
  static Future<PrinterConnection> load({PrintSettingsData? legacy}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        return PrinterConnection.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
    } catch (_) {}
    final l = legacy;
    if (l != null) {
      final paper = ReceiptPaper.fromSettings(l.paperFormat);
      if (l.thermalEscPosEnabled && l.thermalLanHost.trim().isNotEmpty) {
        return PrinterConnection(
          type: PrinterType.lan,
          paper: paper,
          lanHost: l.thermalLanHost.trim(),
          lanPort: l.thermalLanPort,
        );
      }
      return PrinterConnection(paper: paper);
    }
    return const PrinterConnection();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson()));
  }
}
