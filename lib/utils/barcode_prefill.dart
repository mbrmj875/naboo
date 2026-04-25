import '../services/app_settings_repository.dart';
import 'gs1_barcode_parse.dart';

/// اقتراحات عند فتح شاشة إضافة منتج بعد مسح باركود غير مسجّل.
class BarcodePrefill {
  BarcodePrefill({
    required this.suggestedName,
    this.suggestedQty,
    required this.internalNotes,
    this.suggestedNetWeightGrams,
    this.suggestedManufacturingDateIso,
    this.suggestedExpiryDateIso,
  });

  final String suggestedName;
  /// كمية/وزن أولي للمخزون إذا وُجد وزن في الباركود المدمج.
  final double? suggestedQty;
  final String internalNotes;

  /// وزن صافٍ بالغرام (يُحفظ في المنتج) إن وُجد في GS1 أو الباركود المدمج.
  final double? suggestedNetWeightGrams;
  /// تاريخ إنتاج بصيغة `YYYY-MM-DD`.
  final String? suggestedManufacturingDateIso;
  /// تاريخ انتهاء بصيغة `YYYY-MM-DD`.
  final String? suggestedExpiryDateIso;

  /// لعرض الكمية في حقل المخزون.
  static String formatSuggestedQty(double q) {
    if ((q - q.round()).abs() < 1e-9) return q.round().toString();
    return q
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// يستخرج خانات الوزن [W] من [barcode] حسب [pattern] (X منتج، W وزن، P سعر، N إضافي).
  static String? _weightDigitsFromPattern(String barcode, String pattern) {
    if (barcode.length != pattern.length) return null;
    final p = pattern.toUpperCase();
    final buf = StringBuffer();
    for (var i = 0; i < p.length; i++) {
      if (p[i] == 'W') buf.write(barcode[i]);
    }
    final s = buf.toString().trim();
    if (s.isEmpty) return null;
    return s;
  }

  /// باركود يبدو رسالة GS1 (حقول تطبيق) وليس EAN عادياً فقط — لتقليل تواريخ/أوزان خاطئة.
  static bool _isLikelyGs1ApplicationMessage(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    if (t.contains('(')) return true;
    if (t.contains('\u001d')) return true;
    final digits = t.replaceAll(RegExp(r'\s'), '');
    if (digits.startsWith('01') && digits.length >= 16) return true;
    if (RegExp(r'310[0-9]').hasMatch(digits)) return true;
    return false;
  }

  /// [rawBarcode] النص المقروء من الماسح.
  static BarcodePrefill fromScan(String rawBarcode, BarcodeSettingsData settings) {
    final bc = rawBarcode.trim();

    final gs1 = parseGs1Barcode(bc);
    final trustGs1 = _isLikelyGs1ApplicationMessage(bc);

    String? gtin = trustGs1 ? gs1.gtin14 : null;
    DateTime? mfg = trustGs1 ? gs1.productionDate : null;
    DateTime? exp = trustGs1 ? gs1.expiryDate : null;
    double? netGFromGs1 = trustGs1 && gs1.netWeightKg != null
        ? gs1.netWeightKg! * 1000.0
        : null;

    final buf = StringBuffer();

    if (trustGs1 &&
        (mfg != null ||
            exp != null ||
            netGFromGs1 != null ||
            (gtin != null && gtin.isNotEmpty))) {
      buf.writeln('مستخرج من الباركود (GS1) — راجع العبوة:');
      if (gtin != null && gtin.isNotEmpty) buf.writeln('• GTIN: $gtin');
      if (mfg != null) buf.writeln('• تاريخ إنتاج: ${_fmtDate(mfg)}');
      if (exp != null) buf.writeln('• تاريخ انتهاء: ${_fmtDate(exp)}');
      if (netGFromGs1 != null) {
        buf.writeln(
          '• وزن صافٍ (من الباركود): ${formatSuggestedQty(netGFromGs1)} غ',
        );
      }
    }

    double? qty;
    double? netG = netGFromGs1;

    if (settings.weightEmbedEnabled &&
        bc.length == settings.embedPattern.trim().length) {
      final wDigits = _weightDigitsFromPattern(bc, settings.embedPattern.trim());
      if (wDigits != null) {
        final grams = int.tryParse(wDigits);
        if (grams != null && grams > 0) {
          qty = grams / settings.weightDivisor;
          netG ??= grams.toDouble();
          if (buf.isNotEmpty) buf.writeln();
          buf.writeln(
            'وزن مدمج (حسب إعدادات المخزن): $wDigits → كمية/وزن أولي ${formatSuggestedQty(qty)}',
          );
        }
      }
    }

    // تواريخ: فقط عند استخراج GS1 موثوق — بدون افتراض اليوم أو سنة من الآن.
    final String? mfgIso = mfg != null ? _isoDate(mfg) : null;
    final String? expIso = exp != null ? _isoDate(exp) : null;

    return BarcodePrefill(
      suggestedName: '',
      suggestedQty: qty,
      internalNotes: buf.toString().trim(),
      suggestedNetWeightGrams: netG,
      suggestedManufacturingDateIso: mfgIso,
      suggestedExpiryDateIso: expIso,
    );
  }
}
