import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing;

import '../../../models/print_settings_data.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../models/oil_change_filter_kind.dart';
import 'oil_change_auto_whatsapp_message.dart';
import 'oil_change_filter_format.dart';

const _kTajawalRegular = 'assets/fonts/Tajawal-Regular.ttf';
const _kTajawalBold = 'assets/fonts/Tajawal-Bold.ttf';

/// PDF لبطاقة غيار الزيت: شعار + اسم في الأعلى، وجداول الخدمة، والعنوان في الأسفل.
abstract final class OilChangeServicePdf {
  OilChangeServicePdf._();

  static Future<Uint8List> build({
    required Map<String, dynamic> order,
    required PrintSettingsData printSettings,
  }) async {
    final fonts = await _loadFonts();
    final logo = printSettings.storeLogoBytes;
    final title = printSettings.whatsappStoreTitle;
    final address = printSettings.storeAddress.trim();
    final serviceDate = oilChangeServiceDateDisplay(order);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        footer: (ctx) {
          if (address.isEmpty) return pw.SizedBox();
          return pw.Column(
            children: [
              pw.Divider(thickness: 0.6),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  address,
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  textAlign: pw.TextAlign.center,
                  textDirection: pw.TextDirection.rtl,
                ),
              ),
            ],
          );
        },
        build: (ctx) => [
          if (logo != null && logo.isNotEmpty) ...[
            pw.Center(
              child: pw.Image(
                pw.MemoryImage(logo),
                height: 72,
                fit: pw.BoxFit.contain,
              ),
            ),
            pw.SizedBox(height: 10),
          ],
          pw.Center(
            child: pw.Text(
              title,
              style: pw.TextStyle(font: fonts.bold, fontSize: 18),
              textAlign: pw.TextAlign.center,
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              'بطاقة غيار زيت',
              style: pw.TextStyle(font: fonts.regular, fontSize: 12),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              'تاريخ الخدمة: $serviceDate',
              style: pw.TextStyle(font: fonts.bold, fontSize: 11),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          pw.SizedBox(height: 18),
          ..._section(
            fonts: fonts,
            heading: 'بيانات العميل والمركبة',
            rows: [
              _row('تاريخ الخدمة', serviceDate),
              _row('العميل', _s(order['customerNameSnapshot'])),
              _row('الهاتف', _s(order['customerPhone'])),
              _row('السيارة', _s(order['deviceName'])),
              _row('الموديل', _s(order['carModel'])),
              _row('حجم المحرك', _s(order['engineSize'])),
              _row('رقم اللوحة', _s(order['deviceSerial'])),
              _row('القراءة الحالية', _km(order['odometerCurrent'])),
              _row('القراءة اللاحقة', _km(order['odometerNext'])),
            ],
          ),
          pw.SizedBox(height: 14),
          ..._section(
            fonts: fonts,
            heading: 'الزيت',
            rows: [
              _row('النوع', _s(order['oilType'])),
              _row('الدرجة', _s(order['oilViscosity'])),
              _row('الحجم', _s(order['oilSize'])),
            ],
          ),
          pw.SizedBox(height: 14),
          ..._section(
            fonts: fonts,
            heading: 'الفلاتر',
            rows: [
              for (final kind in OilChangeFilterKind.all)
                _row(kind.label, _s(order[kind.nameColumnKey])),
            ],
          ),
          pw.SizedBox(height: 14),
          ..._section(
            fonts: fonts,
            heading: 'هيدروليك',
            rows: [
              _row(
                'هيدروليك القير',
                _hydraulic(
                  type: _s(order['hydraulicType']),
                  grade: _s(order['hydraulicGrade']),
                  size: _s(order['hydraulicSize']),
                  customer: order['hydraulicCustomerProvided'] == 1,
                ),
              ),
              _row(
                'هيدروليك الباور',
                _hydraulic(
                  type: _s(order['powerHydraulicType']),
                  grade: _s(order['powerHydraulicGrade']),
                  size: _s(order['powerHydraulicSize']),
                  customer: order['powerHydraulicCustomerProvided'] == 1,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          ..._section(
            fonts: fonts,
            heading: 'الخدمات',
            rows: [
              for (final s in _services(order)) _row('خدمة', s),
            ],
          ),
          pw.SizedBox(height: 14),
          ..._section(
            fonts: fonts,
            heading: 'السعر والدفع',
            rows: _moneyRows(order),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static Future<void> share({
    required Map<String, dynamic> order,
    required PrintSettingsData printSettings,
  }) async {
    final bytes = await build(order: order, printSettings: printSettings);
    await printing.Printing.sharePdf(
      bytes: bytes,
      filename: oilChangeServicePdfFilename(order),
    );
  }

  static List<pw.Widget> _section({
    required ({pw.Font regular, pw.Font bold}) fonts,
    required String heading,
    required List<({String label, String value})> rows,
  }) {
    final filled = rows.where((r) => r.value.trim().isNotEmpty).toList();
    if (filled.isEmpty) return const [];
    return [
      pw.Text(
        heading,
        style: pw.TextStyle(font: fonts.bold, fontSize: 13),
        textDirection: pw.TextDirection.rtl,
      ),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
        headerCount: 0,
        cellAlignment: pw.Alignment.centerRight,
        cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 10),
        cellAlignments: {
          0: pw.Alignment.centerRight,
          1: pw.Alignment.centerRight,
        },
        data: [
          for (final r in filled) [r.value, r.label],
        ],
      ),
    ];
  }

  static ({String label, String value}) _row(String label, String value) =>
      (label: label, value: value);

  static String _s(Object? raw) => (raw ?? '').toString().trim();

  static String _km(Object? raw) {
    final v = _s(raw);
    if (v.isEmpty) return '';
    return '$v كم';
  }

  static String _hydraulic({
    required String type,
    required String grade,
    required String size,
    required bool customer,
  }) {
    if (customer) return 'من العميل';
    final parts = <String>[
      if (type.isNotEmpty) type,
      if (grade.isNotEmpty) grade,
      if (size.isNotEmpty) size,
    ];
    return parts.join(' — ');
  }

  static List<String> _services(Map<String, dynamic> order) {
    final raw = _s(order['requestedServices']);
    if (raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static List<({String label, String value})> _moneyRows(
    Map<String, dynamic> order,
  ) {
    final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
    final estF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    final totalF = agreedF ?? estF;
    final paidF = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;
    final remainderF = totalF > 0 ? (totalF - paidF).clamp(0, totalF) : 0;
    final listPriceF = estF > 0 ? estF : totalF;
    final discountF =
        (listPriceF > totalF && totalF > 0) ? (listPriceF - totalF) : 0;

    String? money(int fils) {
      if (fils <= 500) return null;
      return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
    }

    final out = <({String label, String value})>[];
    final list = money(listPriceF);
    final disc = money(discountF);
    final total = money(totalF);
    final paid = money(paidF);
    final rem = money(remainderF);

    if (list != null && disc != null && total != null) {
      out.add(_row('السعر قبل الخصم', list));
      out.add(_row('الخصم', disc));
      out.add(_row('السعر بعد الخصم', total));
    } else if (total != null) {
      out.add(_row('الإجمالي', total));
    }
    if (paid != null) {
      out.add(_row('المدفوع', paid));
    }
    if (rem != null) {
      out.add(_row('المتبقي', rem));
    }
    return out;
  }

  static Future<({pw.Font regular, pw.Font bold})> _loadFonts() async {
    try {
      final r = await rootBundle.load(_kTajawalRegular);
      final b = await rootBundle.load(_kTajawalBold);
      return (regular: pw.Font.ttf(r), bold: pw.Font.ttf(b));
    } catch (_) {
      try {
        final pair = await Future.wait([
          printing.PdfGoogleFonts.notoNaskhArabicRegular(),
          printing.PdfGoogleFonts.notoNaskhArabicBold(),
        ]);
        return (regular: pair[0], bold: pair[1]);
      } catch (_) {
        return (
          regular: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        );
      }
    }
  }
}
