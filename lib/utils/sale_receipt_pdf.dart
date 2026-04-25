import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing;

import '../models/installment.dart';
import '../models/invoice.dart';
import '../models/print_settings_data.dart';
import '../services/database_helper.dart';
import '../services/print_settings_repository.dart';
import 'theme.dart';
import 'customer_debt_deep_link.dart';
import 'invoice_deep_link.dart';

/// Tajawal: عربي + لاتيني (أسماء منتجات، بريد، أرقام) — يقلّل مربعات الاستبدال.
const _kTajawalRegular = 'assets/fonts/Tajawal-Regular.ttf';
const _kTajawalBold = 'assets/fonts/Tajawal-Bold.ttf';
const _kNotoNaskhRegular = 'assets/fonts/NotoNaskhArabic-Regular.ttf';
const _kNotoNaskhBold = 'assets/fonts/NotoNaskhArabic-Bold.ttf';

String _receiptSafe(String? raw) {
  if (raw == null) return '';
  var s = raw.replaceAll('\uFFFD', '').trim();
  s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  return s;
}

String _opIdText(Invoice invoice) {
  final id = invoice.id;
  if (id == null) return '-';
  return id.toString();
}

String _customerLineValue(Invoice invoice) {
  final v = _receiptSafe(invoice.customerName);
  return v;
}

bool _omitReceiptPaymentLine(Invoice invoice, PrintSettingsData s) {
  return invoice.type == InvoiceType.delivery && s.receiptShowBuyerAddressQr;
}

/// نص عربي مرتب يُمسَح من QR (وليس JSON) ليكون مفهوماً في أي قارئ.
String buildReceiptQrPlainText({
  required Invoice invoice,
  required double subtotalBeforeDiscount,
  int maxUtf8Bytes = 950,
  PrintSettingsData? printSettings,
}) {
  final df = DateFormat('yyyy/MM/dd HH:mm');
  final ps = printSettings;
  final omitPay = ps != null && _omitReceiptPaymentLine(invoice, ps);
  String compose(List<String> itemLines) {
    final customerVal = _customerLineValue(invoice);
    final staff = _receiptSafe(invoice.createdByUserName);
    final buf = StringBuffer()
      ..writeln('إيصال بيع')
      ..writeln('----------------')
      ..writeln('رقم العملية: ${_opIdText(invoice)}')
      ..writeln('التاريخ: ${df.format(invoice.date)}');
    if (customerVal.isEmpty) {
      buf.writeln('العميل:');
    } else {
      buf.writeln('العميل: $customerVal');
    }
    if (omitPay) {
      buf.writeln('إيصال توصيل — تفاصيل الموقع عبر الرمز أسفل الإيصال');
    } else {
      buf.writeln('طريقة الدفع: ${salePaymentLabel(invoice.type)}');
    }
    if (staff.isNotEmpty) {
      buf.writeln('الموظف: $staff');
    }
    buf
      ..writeln('----------------')
      ..writeln('الأصناف:');
    for (final line in itemLines) {
      buf.writeln(line);
    }
    buf
      ..writeln('----------------')
      ..writeln(
          'قبل الخصم: ${subtotalBeforeDiscount.toStringAsFixed(0)} دينار عراقي')
      ..writeln('الخصم: ${invoice.discount.toStringAsFixed(0)} د.ع')
      ..writeln('الضريبة: ${invoice.tax.toStringAsFixed(0)} د.ع');
    if (invoice.loyaltyDiscount > 0) {
      buf.writeln(
        'خصم ولاء: ${invoice.loyaltyDiscount.toStringAsFixed(0)} د.ع',
      );
    }
    buf
      ..writeln('الإجمالي: ${invoice.total.toStringAsFixed(0)} د.ع')
      ..writeln('رمز الشريط: INV-${invoice.id ?? 0}');
    return buf.toString().trimRight();
  }

  final fullItemLines = invoice.items
      .map(
        (e) =>
            '• ${_receiptSafe(e.productName)}  |  العدد: ${e.quantity}  |  ${e.total.toStringAsFixed(0)} د.ع',
      )
      .toList();

  var text = compose(fullItemLines);
  if (utf8.encode(text).length <= maxUtf8Bytes) return text;

  for (var keep = fullItemLines.length - 1; keep >= 0; keep--) {
    final shortened = <String>[
      ...fullItemLines.take(keep),
      if (keep < fullItemLines.length)
        '… و${fullItemLines.length - keep} صنفاً آخر (التفاصيل في النظام)',
    ];
    text = compose(shortened);
    if (utf8.encode(text).length <= maxUtf8Bytes) return text;
  }

  final cv = _customerLineValue(invoice);
  final custQr = cv.isEmpty ? 'العميل:' : 'العميل: $cv';
  final payLine = omitPay
      ? 'إيصال توصيل — رمز الموقع أسفل الإيصال'
      : 'الدفع: ${salePaymentLabel(invoice.type)}';
  return '''
إيصال بيع
رقم العملية: ${_opIdText(invoice)}
التاريخ: ${df.format(invoice.date)}
$custQr
الإجمالي: ${invoice.total.toStringAsFixed(0)} د.ع
$payLine
رمز الشريط: INV-${invoice.id ?? 0}'''
      .trim();
}

/// رابط Google Maps من عنوان أو وصف نصي (حمولة QR للهاتف).
String googleMapsSearchUrlFromAddress(String? rawAddress) {
  final t = _receiptSafe(rawAddress);
  if (t.isEmpty) return '';
  return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent(t)}';
}

String salePaymentLabel(InvoiceType t) {
  switch (t) {
    case InvoiceType.cash:
      return 'نقدي';
    case InvoiceType.credit:
      return 'دين';
    case InvoiceType.installment:
      return 'تقسيط';
    case InvoiceType.delivery:
      return 'توصيل';
    case InvoiceType.debtCollection:
      return 'تحصيل دين';
    case InvoiceType.installmentCollection:
      return 'تسديد قسط';
    case InvoiceType.supplierPayment:
      return 'دفع مورد';
  }
}

List<pw.Widget> _receiptCreditSummaryWidgets(
  Invoice inv,
  pw.Font font,
  pw.Font fontBold,
) {
  if (inv.type != InvoiceType.credit) return [];
  final paid = inv.advancePayment;
  final rem = (inv.total - inv.advancePayment).clamp(0.0, 1e18);
  return [
    pw.SizedBox(height: 10),
    pw.Divider(thickness: 0.7, color: PdfColors.grey600),
    pw.SizedBox(height: 6),
    pw.Text(
      'ملخص البيع بالدين',
      style: pw.TextStyle(font: fontBold, fontSize: 12),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.SizedBox(height: 4),
    pw.Text(
      'الإجمالي على الفاتورة: ${inv.total.toStringAsFixed(0)} د.ع',
      style: pw.TextStyle(font: font, fontSize: 11),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.Text(
      'الواصل (المدفوع الآن): ${paid.toStringAsFixed(0)} د.ع',
      style: pw.TextStyle(font: font, fontSize: 11),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.Text(
      'المتبقي على الحساب: ${rem.toStringAsFixed(0)} د.ع',
      style: pw.TextStyle(font: fontBold, fontSize: 12),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
  ];
}

List<pw.Widget> _receiptInstallmentFinanceWidgets(
  Invoice inv,
  pw.Font font,
  pw.Font fontBold,
) {
  if (inv.type != InvoiceType.installment) return [];
  final rawFinanced = inv.total - inv.advancePayment;
  final financed = inv.installmentFinancedAmount > 1e-6
      ? inv.installmentFinancedAmount
      : (rawFinanced < 0 ? 0.0 : rawFinanced);
  final pct = inv.installmentInterestPct;
  final months = inv.installmentPlannedMonths;
  final interestAmt = inv.installmentInterestAmount;
  final totalWith = inv.installmentTotalWithInterest;
  final monthly = inv.installmentSuggestedMonthly;
  return [
    pw.SizedBox(height: 10),
    pw.Divider(thickness: 0.7, color: PdfColors.grey600),
    pw.SizedBox(height: 6),
    pw.Text(
      'ملخص التقسيط (سعر البيع والفائدة)',
      style: pw.TextStyle(font: fontBold, fontSize: 12),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.SizedBox(height: 4),
    pw.Text(
      'إجمالي الفاتورة (سعر البيع): ${inv.total.toStringAsFixed(0)} د.ع',
      style: pw.TextStyle(font: font, fontSize: 11),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.Text(
      'المقدّم / الدفعة الأولى: ${inv.advancePayment.toStringAsFixed(0)} د.ع',
      style: pw.TextStyle(font: font, fontSize: 11),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.Text(
      'المبلغ بعد المقدّم (أساس الفائدة): ${financed.toStringAsFixed(0)} د.ع',
      style: pw.TextStyle(font: font, fontSize: 11),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.Text(
      'نسبة الفائدة: ${pct % 1 == 0 ? pct.toInt().toString() : pct.toStringAsFixed(2)}٪',
      style: pw.TextStyle(font: font, fontSize: 11),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.Text(
      'قيمة الفائدة: ${interestAmt.toStringAsFixed(0)} د.ع',
      style: pw.TextStyle(font: font, fontSize: 11),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.Text(
      'الإجمالي مع الفائدة: ${totalWith > 1e-6 ? totalWith.toStringAsFixed(0) : (financed + interestAmt).toStringAsFixed(0)} د.ع',
      style: pw.TextStyle(font: fontBold, fontSize: 11),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.Text(
      'عدد الأشهر المخططة: ${months > 0 ? months.toString() : '—'}',
      style: pw.TextStyle(font: font, fontSize: 11),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
    pw.Text(
      'القسط الشهري المقترح: ${monthly > 1e-6 ? '${monthly.toStringAsFixed(0)} د.ع' : '—'}',
      style: pw.TextStyle(font: fontBold, fontSize: 12),
      textAlign: pw.TextAlign.right,
      textDirection: pw.TextDirection.rtl,
    ),
  ];
}

Future<({pw.Font regular, pw.Font bold})> _loadReceiptFonts() async {
  Future<({pw.Font regular, pw.Font bold})?> tryPair(String reg, String bld) async {
    try {
      final r = await rootBundle.load(reg);
      final b = await rootBundle.load(bld);
      return (regular: pw.Font.ttf(r), bold: pw.Font.ttf(b));
    } catch (_) {
      return null;
    }
  }

  final t = await tryPair(_kTajawalRegular, _kTajawalBold);
  if (t != null) return t;

  final n = await tryPair(_kNotoNaskhRegular, _kNotoNaskhBold);
  if (n != null) return n;

  try {
    final pair = await Future.wait([
      printing.PdfGoogleFonts.notoNaskhArabicRegular(),
      printing.PdfGoogleFonts.notoNaskhArabicBold(),
    ]).timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw TimeoutException('pdf fonts'),
    );
    return (regular: pair[0], bold: pair[1]);
  } catch (_) {
    return (
      regular: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );
  }
}

/// طباعة إيصال بيع: باركود رقمي + QR يحمل نصاً عربياً مرتباً.
class SaleReceiptPdf {
  /// يبني ملف PDF كبايتات (للمعاينة داخل التطبيق أو المشاركة).
  static Future<Uint8List> buildPdfBytes({
    required Invoice invoice,
    required double subtotalBeforeDiscount,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    PrintSettingsData? settings,
  }) async {
    final s = settings ?? PrintSettingsData.defaults();
    final fonts = await _loadReceiptFonts();
    final font = fonts.regular;
    final fontBold = fonts.bold;

    final omitPayPdf = _omitReceiptPaymentLine(invoice, s);
    final String mainQrPayload;
    if ((invoice.type == InvoiceType.installment ||
            invoice.type == InvoiceType.credit ||
            invoice.type == InvoiceType.debtCollection ||
            invoice.type == InvoiceType.installmentCollection ||
            invoice.type == InvoiceType.supplierPayment) &&
        invoice.id != null &&
        invoice.id! > 0) {
      mainQrPayload = InvoiceDeepLink.uriForInvoiceId(invoice.id!);
    } else {
      mainQrPayload = buildReceiptQrPlainText(
        invoice: invoice,
        subtotalBeforeDiscount: subtotalBeforeDiscount,
        printSettings: s,
      );
    }
    final String mainQrCaption = switch (invoice.type) {
      InvoiceType.installment || InvoiceType.credit =>
        'امسح لفتح تفاصيل الفاتورة والأصناف في التطبيق (يتطلب تسجيل الدخول)',
      InvoiceType.debtCollection ||
      InvoiceType.installmentCollection ||
      InvoiceType.supplierPayment =>
        'امسح لفتح تفاصيل السند في التطبيق (يتطلب تسجيل الدخول)',
      _ => 'امسح الرمز لمشاهدة ملخص الإيصال كنص مرتب',
    };

    InstallmentPlan? saleInstallmentPlan;
    if (invoice.type == InvoiceType.installment && invoice.id != null) {
      try {
        saleInstallmentPlan = await DatabaseHelper()
            .getInstallmentPlanByInvoiceId(invoice.id!);
      } catch (_) {}
    }

    final pdf = pw.Document();
    final df = DateFormat('dd/MM/yyyy HH:mm', 'en_US');

    final customerVal = _customerLineValue(invoice);
    final opId = _opIdText(invoice);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) {
          final buyerAddressQrWidgets = <pw.Widget>[];
          if (s.receiptShowBuyerAddressQr) {
            final locUrl =
                googleMapsSearchUrlFromAddress(invoice.deliveryAddress);
            if (locUrl.isNotEmpty) {
              final addrLine = _receiptSafe(invoice.deliveryAddress);
              buyerAddressQrWidgets.addAll([
                pw.SizedBox(height: 14),
                pw.Center(
                  child: pw.Text(
                    'QR عنوان المشتري',
                    style: pw.TextStyle(font: fontBold, fontSize: 10),
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: bc.Barcode.qrCode(),
                    data: locUrl,
                    width: 108,
                    height: 108,
                    drawText: false,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'امسح لفتح الموقع على الخرائط',
                    style: pw.TextStyle(font: font, fontSize: 9),
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                if (addrLine.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    addrLine.length > 200
                        ? '${addrLine.substring(0, 200)}…'
                        : addrLine,
                    style: pw.TextStyle(font: font, fontSize: 8),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                    maxLines: 5,
                    overflow: pw.TextOverflow.clip,
                  ),
                ],
              ]);
            }
          }

          return pw.Padding(
            padding: const pw.EdgeInsets.all(28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (_receiptSafe(s.storeTitleLine).isNotEmpty) ...[
                  pw.Center(
                    child: pw.Text(
                      _receiptSafe(s.storeTitleLine),
                      style: pw.TextStyle(font: fontBold, fontSize: 14),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                ],
                pw.Center(
                  child: pw.Text(
                    'إيصال بيع',
                    style: pw.TextStyle(font: fontBold, fontSize: 18),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey700, width: 1),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Text(
                        'رقم العملية',
                        style: pw.TextStyle(font: font, fontSize: 11),
                        textAlign: pw.TextAlign.right,
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Center(
                        child: pw.Text(
                          opId,
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 22,
                          ),
                          textDirection: pw.TextDirection.ltr,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'التاريخ والوقت: ${df.format(invoice.date)}',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                if (customerVal.isEmpty)
                  pw.Text(
                    'العميل:',
                    style: pw.TextStyle(font: font, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  )
                else
                  pw.Text(
                    'العميل: $customerVal',
                    style: pw.TextStyle(font: font, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                if (!omitPayPdf)
                  pw.Text(
                    'طريقة الدفع: ${salePaymentLabel(invoice.type)}',
                    style: pw.TextStyle(font: font, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  )
                else
                  pw.Text(
                    'إيصال توصيل — تفاصيل الموقع عبر الرمز في أسفل الصفحة.',
                    style: pw.TextStyle(font: font, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                if (_receiptSafe(invoice.deliveryAddress).isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'العنوان: ${_receiptSafe(invoice.deliveryAddress)}',
                    style: pw.TextStyle(font: font, fontSize: 10),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                    maxLines: 6,
                    overflow: pw.TextOverflow.clip,
                  ),
                ],
                if (_receiptSafe(invoice.createdByUserName).isNotEmpty)
                  pw.Text(
                    'الموظف: ${_receiptSafe(invoice.createdByUserName)}',
                    style: pw.TextStyle(font: font, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 0.7, color: PdfColors.grey600),
                pw.SizedBox(height: 6),
                pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey400,
                    width: 0.6,
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3.2),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1.1),
                    3: const pw.FlexColumnWidth(1.2),
                  },
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        _cell('الصنف', fontBold, 10, true),
                        _cell('الكمية', fontBold, 10, true),
                        _cell('السعر', fontBold, 10, true),
                        _cell('المجموع', fontBold, 10, true),
                      ],
                    ),
                    ...invoice.items.map(
                      (e) => pw.TableRow(
                        children: [
                          _cell(
                            _receiptSafe(e.productName).isEmpty
                                ? '-'
                                : _receiptSafe(e.productName),
                            font,
                            9.5,
                            true,
                          ),
                          _cell('${e.quantity}', font, 9.5, false),
                          _cell(e.price.toStringAsFixed(0), font, 9.5, false),
                          _cell(
                            '${e.total.toStringAsFixed(0)} د.ع',
                            font,
                            9.5,
                            false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(thickness: 0.7, color: PdfColors.grey600),
                pw.SizedBox(height: 6),
                pw.Text(
                  'المجموع قبل الخصم: ${subtotalBeforeDiscount.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'خصم ${invoice.discountPercent.toStringAsFixed(2)}٪: ${invoice.discount.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'الضريبة: ${invoice.tax.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                if (invoice.loyaltyDiscount > 0) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'خصم ولاء: ${invoice.loyaltyDiscount.toStringAsFixed(0)} د.ع',
                    style: pw.TextStyle(font: font, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
                pw.SizedBox(height: 4),
                pw.Text(
                  'الإجمالي النهائي: ${invoice.total.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: fontBold, fontSize: 13),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                ..._receiptInstallmentFinanceWidgets(invoice, font, fontBold),
                ...SaleReceiptPdf._receiptInstallmentScheduleTableWidgets(
                  invoice,
                  saleInstallmentPlan,
                  font,
                  fontBold,
                ),
                ..._receiptCreditSummaryWidgets(invoice, font, fontBold),
                if (_receiptSafe(s.footerExtra).isNotEmpty) ...[
                  pw.SizedBox(height: 10),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey500),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    _receiptSafe(s.footerExtra),
                    style: pw.TextStyle(font: font, fontSize: 9),
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
                pw.SizedBox(height: 16),
                if (s.receiptShowBarcode) ...[
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: bc.Barcode.code128(),
                      data: 'INV-${invoice.id ?? 0}',
                      width: 200,
                      height: 44,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text(
                      'INV-${invoice.id ?? 0}',
                      style: pw.TextStyle(font: font, fontSize: 11),
                      textDirection: pw.TextDirection.ltr,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                ],
                if (s.receiptShowQr) ...[
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: bc.Barcode.qrCode(),
                      data: mainQrPayload,
                      width: 120,
                      height: 120,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text(
                      mainQrCaption,
                      style: pw.TextStyle(font: font, fontSize: 9),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ],
                ...buyerAddressQrWidgets,
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _cell(
    String text,
    pw.Font font,
    double size,
    bool rtl,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(font: font, fontSize: size),
        textAlign: rtl ? pw.TextAlign.right : pw.TextAlign.center,
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        maxLines: 4,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  static List<Installment> _orderedInstallmentsForPlan(InstallmentPlan plan) {
    final list = List<Installment>.from(plan.installments);
    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  static String _installmentDayFmt(DateTime d) =>
      DateFormat('dd/MM/yyyy', 'en').format(d);

  static List<pw.Widget> _receiptInstallmentScheduleTableWidgets(
    Invoice inv,
    InstallmentPlan? plan,
    pw.Font font,
    pw.Font fontBold,
  ) {
    if (inv.type != InvoiceType.installment ||
        plan == null ||
        plan.installments.isEmpty) {
      return [];
    }
    final ord = _orderedInstallmentsForPlan(plan);
    final rows = <pw.Widget>[
      pw.SizedBox(height: 10),
      pw.Divider(thickness: 0.5, color: PdfColors.grey500),
      pw.SizedBox(height: 6),
      pw.Text(
        'جدول الأقساط (حسب تاريخ الاستحقاق)',
        style: pw.TextStyle(font: fontBold, fontSize: 12),
        textAlign: pw.TextAlign.right,
        textDirection: pw.TextDirection.rtl,
      ),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: {
          0: const pw.FlexColumnWidth(0.55),
          1: const pw.FlexColumnWidth(1.15),
          2: const pw.FlexColumnWidth(0.95),
          3: const pw.FlexColumnWidth(0.75),
          4: const pw.FlexColumnWidth(1.1),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              _cell('#', fontBold, 9, true),
              _cell('الاستحقاق', fontBold, 9, true),
              _cell('المبلغ', fontBold, 9, true),
              _cell('الحالة', fontBold, 9, true),
              _cell('تاريخ التسديد', fontBold, 9, true),
            ],
          ),
          ...ord.asMap().entries.map((e) {
            final n = e.key + 1;
            final i = e.value;
            final st = i.paid ? 'مسدد' : 'مستحق';
            final pd = i.paid && i.paidDate != null
                ? _installmentDayFmt(i.paidDate!)
                : '—';
            return pw.TableRow(
              children: [
                _cell('$n', font, 9, false),
                _cell(_installmentDayFmt(i.dueDate), font, 9, false),
                _cell('${i.amount.toStringAsFixed(0)} د.ع', font, 9, false),
                _cell(st, font, 9, true),
                _cell(pd, font, 9, false),
              ],
            );
          }),
        ],
      ),
    ];
    final unpaidHints = <pw.Widget>[];
    for (var k = 0; k < ord.length; k++) {
      final i = ord[k];
      if (!i.paid) {
        unpaidHints.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 3),
            child: pw.Text(
              'القسط رقم ${k + 1} (${i.amount.toStringAsFixed(0)} د.ع) مستحق في ${_installmentDayFmt(i.dueDate)}',
              style: pw.TextStyle(font: font, fontSize: 10),
              textAlign: pw.TextAlign.right,
              textDirection: pw.TextDirection.rtl,
            ),
          ),
        );
      }
    }
    if (unpaidHints.isNotEmpty) {
      rows.addAll([
        pw.SizedBox(height: 8),
        pw.Text(
          'الأقساط المتبقية (تذكير بالمواعيد)',
          style: pw.TextStyle(font: fontBold, fontSize: 11),
          textAlign: pw.TextAlign.right,
          textDirection: pw.TextDirection.rtl,
        ),
        ...unpaidHints,
      ]);
    }
    return rows;
  }

  /// إيصال بعد تسديد قسط: يعرض كل الأقساط المسددة (مع تمييز عملية اليوم) والمتبقية ومواعيدها.
  static Future<Uint8List> buildInstallmentPaymentReceiptBytes({
    required InstallmentPlan plan,
    required int justPaidInstallmentId,
    Invoice? invoice,
    int? receiptInvoiceId,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    PrintSettingsData? settings,
  }) async {
    final s = settings ?? PrintSettingsData.defaults();
    final fonts = await _loadReceiptFonts();
    final font = fonts.regular;
    final fontBold = fonts.bold;
    final df = DateFormat('dd/MM/yyyy HH:mm', 'en_US');
    final now = DateTime.now();
    final ord = _orderedInstallmentsForPlan(plan);
    final paidChrono = ord.where((i) => i.paid).toList()
      ..sort((a, b) {
        final ad = a.paidDate ?? a.dueDate;
        final bd = b.paidDate ?? b.dueDate;
        return ad.compareTo(bd);
      });

    final invId = invoice?.id ?? plan.invoiceId;
    final qrPayload = invId > 0
        ? InvoiceDeepLink.uriForInvoiceId(invId)
        : 'خطة تقسيط #${plan.id ?? 0}';

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) {
          final paidLines = <pw.Widget>[];
          for (final p in paidChrono) {
            final idx = ord.indexOf(p) + 1;
            final isToday = p.id == justPaidInstallmentId;
            final paidWhen = p.paidDate != null
                ? _installmentDayFmt(p.paidDate!)
                : '—';
            paidLines.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  'القسط $idx — ${p.amount.toStringAsFixed(0)} د.ع — استحق ${_installmentDayFmt(p.dueDate)} — سُدد $paidWhen${isToday ? '  (عملية اليوم)' : ''}',
                  style: pw.TextStyle(
                    font: isToday ? fontBold : font,
                    fontSize: isToday ? 10.5 : 10,
                  ),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
              ),
            );
          }

          final unpaidBlock = <pw.Widget>[];
          for (var k = 0; k < ord.length; k++) {
            final ins = ord[k];
            if (!ins.paid) {
              unpaidBlock.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 3),
                  child: pw.Text(
                    'القسط رقم ${k + 1} (${ins.amount.toStringAsFixed(0)} د.ع) مستحق في ${_installmentDayFmt(ins.dueDate)}',
                    style: pw.TextStyle(font: font, fontSize: 10),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
              );
            }
          }

          return pw.Padding(
            padding: const pw.EdgeInsets.all(28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (_receiptSafe(s.storeTitleLine).isNotEmpty) ...[
                  pw.Center(
                    child: pw.Text(
                      _receiptSafe(s.storeTitleLine),
                      style: pw.TextStyle(font: fontBold, fontSize: 14),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                ],
                pw.Center(
                  child: pw.Text(
                    'إيصال تسديد قسط',
                    style: pw.TextStyle(font: fontBold, fontSize: 18),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'التاريخ والوقت: ${df.format(now)}',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'خطة التقسيط: #${plan.id ?? '—'}',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                if (invId > 0)
                  pw.Text(
                    'الفاتورة الأصلية: #$invId',
                    style: pw.TextStyle(font: fontBold, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                if (receiptInvoiceId != null && receiptInvoiceId > 0)
                  pw.Text(
                    'سند القبض (قائمة الفواتير): #$receiptInvoiceId',
                    style: pw.TextStyle(font: fontBold, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                pw.Text(
                  'العميل: ${_receiptSafe(plan.customerName.isEmpty ? 'عميل' : plan.customerName)}',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 8),
                pw.Divider(color: PdfColors.grey600),
                pw.SizedBox(height: 6),
                pw.Text(
                  'الأقساط المسددة (بالترتيب الزمني للتسديد)',
                  style: pw.TextStyle(font: fontBold, fontSize: 12),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                if (paidLines.isEmpty)
                  pw.Text(
                    '— لا توجد أقساط مسددة بعد —',
                    style: pw.TextStyle(font: font, fontSize: 10),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  )
                else
                  ...paidLines,
                if (unpaidBlock.isNotEmpty) ...[
                  pw.SizedBox(height: 12),
                  pw.Divider(color: PdfColors.grey500),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'الأقساط المتبقية ومواعيد الاستحقاق',
                    style: pw.TextStyle(font: fontBold, fontSize: 12),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                  ...unpaidBlock,
                ] else ...[
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'اكتمل سداد جميع الأقساط لهذه الخطة.',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 11,
                      color: PdfColors.green800,
                    ),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
                pw.SizedBox(height: 16),
                if (s.receiptShowQr) ...[
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: bc.Barcode.qrCode(),
                      data: qrPayload,
                      width: 110,
                      height: 110,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text(
                      invId > 0
                          ? 'امسح لفتح تفاصيل الفاتورة والأصناف في التطبيق'
                          : 'مرجع الخطة',
                      style: pw.TextStyle(font: font, fontSize: 9),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  static Future<void> presentInstallmentPaymentReceipt(
    BuildContext context, {
    required InstallmentPlan plan,
    required int justPaidInstallmentId,
    Invoice? invoice,
    int? receiptInvoiceId,
    PrintSettingsData? printSettings,
  }) async {
    if (!context.mounted) return;
    final settings =
        printSettings ?? await PrintSettingsRepository.instance.load();
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) {
          return Directionality(
            textDirection: ui.TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('إيصال تسديد قسط'),
              ),
              body: printing.PdfPreview(
                maxPageWidth: 720,
                initialPageFormat: settings.pdfPageFormat,
                canChangePageFormat: true,
                canChangeOrientation: false,
                allowPrinting: true,
                allowSharing: true,
                canDebug: false,
                pdfFileName:
                    'installment-receipt-${plan.id ?? justPaidInstallmentId}.pdf',
                build: (() {
                  final cache = <String, Future<Uint8List>>{};
                  return (format) {
                    final key =
                        '${plan.id ?? justPaidInstallmentId}|$justPaidInstallmentId|${receiptInvoiceId ?? 0}|${format.width}x${format.height}|${format.marginLeft},${format.marginTop},${format.marginRight},${format.marginBottom}|${settings.hashCode}';
                    return cache.putIfAbsent(
                      key,
                      () => buildInstallmentPaymentReceiptBytes(
                        plan: plan,
                        justPaidInstallmentId: justPaidInstallmentId,
                        invoice: invoice,
                        receiptInvoiceId: receiptInvoiceId,
                        pageFormat: format,
                        settings: settings,
                      ),
                    );
                  };
                })(),
              ),
            ),
          );
        },
      ),
    );
  }

  /// إيصال بعد تسديد دفعة على ديون «آجل» (واجهة ديون العملاء).
  static Future<Uint8List> buildCustomerDebtPaymentReceiptBytes({
    required String customerDisplayName,
    int? customerId,
    required double amountApplied,
    required double debtBefore,
    required double debtAfter,
    required int paymentRowId,
    int? receiptInvoiceId,
    String? recordedByUserName,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    PrintSettingsData? settings,
  }) async {
    final s = settings ?? PrintSettingsData.defaults();
    final fonts = await _loadReceiptFonts();
    final font = fonts.regular;
    final fontBold = fonts.bold;
    final df = DateFormat('dd/MM/yyyy HH:mm', 'en_US');
    final now = DateTime.now();

    final qrPayload = customerId != null && customerId > 0
        ? CustomerDebtDeepLink.uriForCustomerId(customerId)
        : (receiptInvoiceId != null && receiptInvoiceId > 0
            ? InvoiceDeepLink.uriForInvoiceId(receiptInvoiceId)
            : 'تسديد دين آجل — ${_receiptSafe(customerDisplayName)}');

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (_receiptSafe(s.storeTitleLine).isNotEmpty) ...[
                  pw.Center(
                    child: pw.Text(
                      _receiptSafe(s.storeTitleLine),
                      style: pw.TextStyle(font: fontBold, fontSize: 14),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                ],
                pw.Center(
                  child: pw.Text(
                    'إيصال تسديد دين آجل',
                    style: pw.TextStyle(font: fontBold, fontSize: 18),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'التاريخ والوقت: ${df.format(now)}',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'العميل: ${_receiptSafe(customerDisplayName.isEmpty ? 'عميل' : customerDisplayName)}',
                  style: pw.TextStyle(font: fontBold, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                if (customerId != null && customerId > 0)
                  pw.Text(
                    'مسجّل في العملاء: #$customerId',
                    style: pw.TextStyle(font: font, fontSize: 10),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                if (_receiptSafe(recordedByUserName).isNotEmpty)
                  pw.Text(
                    'سجّل العملية: ${_receiptSafe(recordedByUserName)}',
                    style: pw.TextStyle(font: font, fontSize: 10),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                pw.SizedBox(height: 8),
                pw.Divider(color: PdfColors.grey600),
                pw.SizedBox(height: 6),
                pw.Text(
                  'المبلغ المُسدَّد في هذه العملية: ${amountApplied.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: fontBold, fontSize: 12),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'إجمالي الدين قبل التسديد: ${debtBefore.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'المتبقي بعد التسديد: ${debtAfter.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'تُوزَّع الدفعات تلقائياً على فواتير الآجل من الأقدم إلى الأحدث.',
                  style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'سجل الدفعة: #$paymentRowId',
                  style: pw.TextStyle(font: font, fontSize: 10),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                if (receiptInvoiceId != null && receiptInvoiceId > 0)
                  pw.Text(
                    'سند القبض (قائمة الفواتير): #$receiptInvoiceId',
                    style: pw.TextStyle(font: fontBold, fontSize: 11),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                if (debtAfter < 1e-6) ...[
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'اكتمل سداد دين الآجل لهذا العميل.',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 11,
                      color: PdfColors.green800,
                    ),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
                pw.SizedBox(height: 16),
                if (s.receiptShowQr) ...[
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: bc.Barcode.qrCode(),
                      data: qrPayload,
                      width: 110,
                      height: 110,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text(
                      customerId != null && customerId > 0
                          ? 'امسح لفتح شاشة ديون هذا العميل'
                          : (receiptInvoiceId != null && receiptInvoiceId > 0
                              ? 'امسح لفتح تفاصيل سند التحصيل في التطبيق'
                              : 'مرجع العملية'),
                      style: pw.TextStyle(font: font, fontSize: 9),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  static Future<void> presentCustomerDebtPaymentReceipt(
    BuildContext context, {
    required String customerDisplayName,
    int? customerId,
    required double amountApplied,
    required double debtBefore,
    required double debtAfter,
    required int paymentRowId,
    int? receiptInvoiceId,
    String? recordedByUserName,
    PrintSettingsData? printSettings,
  }) async {
    if (!context.mounted) return;
    final settings =
        printSettings ?? await PrintSettingsRepository.instance.load();
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) {
          return Directionality(
            textDirection: ui.TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('إيصال تسديد دين'),
              ),
              body: printing.PdfPreview(
                maxPageWidth: 720,
                initialPageFormat: settings.pdfPageFormat,
                canChangePageFormat: true,
                canChangeOrientation: false,
                allowPrinting: true,
                allowSharing: true,
                canDebug: false,
                pdfFileName:
                    'debt-receipt-$paymentRowId${receiptInvoiceId != null ? '-$receiptInvoiceId' : ''}.pdf',
                build: (() {
                  final cache = <String, Future<Uint8List>>{};
                  return (format) {
                    final key =
                        '$paymentRowId|${receiptInvoiceId ?? 0}|${customerId ?? 0}|${format.width}x${format.height}|${format.marginLeft},${format.marginTop},${format.marginRight},${format.marginBottom}|${settings.hashCode}';
                    return cache.putIfAbsent(
                      key,
                      () => buildCustomerDebtPaymentReceiptBytes(
                        customerDisplayName: customerDisplayName,
                        customerId: customerId,
                        amountApplied: amountApplied,
                        debtBefore: debtBefore,
                        debtAfter: debtAfter,
                        paymentRowId: paymentRowId,
                        receiptInvoiceId: receiptInvoiceId,
                        recordedByUserName: recordedByUserName,
                        pageFormat: format,
                        settings: settings,
                      ),
                    );
                  };
                })(),
              ),
            ),
          );
        },
      ),
    );
  }

  /// معاينة الإيصال مع طباعة ومشاركة.
  ///
  /// [fullScreen] عند `true`: صفحة كاملة (كالمعتاد بعد البيع) — يُفضَّل مع [BuildContext]
  /// من [MaterialApp.navigatorKey] بعد إغلاق شاشة البيع.
  ///
  /// [onOpenDetailsFromPdf] — زر اختياري في الشريط (مثلاً من قائمة الفواتير).
  static Future<void> presentReceipt(
    BuildContext context, {
    required Invoice invoice,
    required double subtotalBeforeDiscount,
    PrintSettingsData? printSettings,
    void Function(BuildContext pdfContext)? onOpenDetailsFromPdf,
    bool fullScreen = false,
  }) async {
    if (!context.mounted) return;
    final settings =
        printSettings ?? await PrintSettingsRepository.instance.load();
    if (!context.mounted) return;

    if (fullScreen) {
      final openDetails = onOpenDetailsFromPdf;
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) {
            final w = MediaQuery.sizeOf(ctx).width;
            final maxPage = math.min(w - 16, 920.0).clamp(200.0, w);
            return Directionality(
              textDirection: ui.TextDirection.rtl,
              child: Scaffold(
                appBar: AppBar(
                  leading: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                  title: const Text('إيصال البيع'),
                  actions: [
                    if (openDetails != null)
                      IconButton(
                        icon: const Icon(Icons.receipt_long_outlined),
                        tooltip: 'تفاصيل الفاتورة كاملة',
                        onPressed: () => openDetails(ctx),
                      ),
                  ],
                ),
                body: ColoredBox(
                  color: Theme.of(ctx).colorScheme.surface,
                  child: printing.PdfPreview(
                    padding: const EdgeInsets.all(8),
                    maxPageWidth: maxPage,
                    initialPageFormat: settings.pdfPageFormat,
                    canChangePageFormat: true,
                    canChangeOrientation: false,
                    allowPrinting: true,
                    allowSharing: true,
                    canDebug: false,
                    pdfFileName: 'receipt-${invoice.id ?? "sale"}.pdf',
                    build: (() {
                      final cache = <String, Future<Uint8List>>{};
                      return (format) {
                        final key =
                            '${invoice.id ?? "sale"}|${format.width}x${format.height}|${format.marginLeft},${format.marginTop},${format.marginRight},${format.marginBottom}|${settings.hashCode}';
                        return cache.putIfAbsent(
                          key,
                          () => buildPdfBytes(
                            invoice: invoice,
                            subtotalBeforeDiscount: subtotalBeforeDiscount,
                            pageFormat: format,
                            settings: settings,
                          ),
                        );
                      };
                    })(),
                  ),
                ),
              ),
            );
          },
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        final mq = MediaQuery.of(dialogContext);
        final sz = mq.size;
        final maxW = math.min(620.0, sz.width - 20).clamp(260.0, sz.width);
        final maxH =
            math.min(sz.height * 0.88, 720.0).clamp(280.0, sz.height - 24);
        final openDetails = onOpenDetailsFromPdf;

        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: maxW,
              height: maxH,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: AppTheme.primaryColor,
                    child: SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white),
                            tooltip: 'إغلاق',
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(),
                          ),
                          const Expanded(
                            child: Text(
                              'إيصال البيع',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (openDetails != null)
                            IconButton(
                              icon: const Icon(Icons.receipt_long_outlined,
                                  color: Colors.white),
                              tooltip: 'تفاصيل الفاتورة كاملة',
                              onPressed: () => openDetails(dialogContext),
                            )
                          else
                            const SizedBox(width: 48),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: Theme.of(dialogContext).colorScheme.surface,
                      child: printing.PdfPreview(
                        padding: const EdgeInsets.all(6),
                        maxPageWidth: maxW - 16,
                        initialPageFormat: settings.pdfPageFormat,
                        canChangePageFormat: true,
                        canChangeOrientation: false,
                        allowPrinting: true,
                        allowSharing: true,
                        canDebug: false,
                        pdfFileName: 'receipt-${invoice.id ?? "sale"}.pdf',
                        build: (format) => buildPdfBytes(
                          invoice: invoice,
                          subtotalBeforeDiscount: subtotalBeforeDiscount,
                          pageFormat: format,
                          settings: settings,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<Uint8List> buildSupplierPaymentReceiptBytes({
    required String supplierDisplayName,
    required double amountPaid,
    required double payableBefore,
    required double payableAfter,
    required int payoutRowId,
    required int receiptInvoiceId,
    required bool affectsCash,
    String? note,
    String? recordedByUserName,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    PrintSettingsData? settings,
  }) async {
    final s = settings ?? PrintSettingsData.defaults();
    final fonts = await _loadReceiptFonts();
    final font = fonts.regular;
    final fontBold = fonts.bold;
    final df = DateFormat('dd/MM/yyyy HH:mm', 'en_US');
    final now = DateTime.now();

    final qrPayload = InvoiceDeepLink.uriForInvoiceId(receiptInvoiceId);

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (context) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                if (_receiptSafe(s.storeTitleLine).isNotEmpty) ...[
                  pw.Center(
                    child: pw.Text(
                      _receiptSafe(s.storeTitleLine),
                      style: pw.TextStyle(font: fontBold, fontSize: 14),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                ],
                pw.Center(
                  child: pw.Text(
                    'إيصال دفع مورد',
                    style: pw.TextStyle(font: fontBold, fontSize: 18),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'التاريخ والوقت: ${df.format(now)}',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'المورد: ${_receiptSafe(supplierDisplayName.isEmpty ? 'مورد' : supplierDisplayName)}',
                  style: pw.TextStyle(font: fontBold, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                if (_receiptSafe(recordedByUserName).isNotEmpty)
                  pw.Text(
                    'سجّل العملية: ${_receiptSafe(recordedByUserName)}',
                    style: pw.TextStyle(font: font, fontSize: 10),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                pw.SizedBox(height: 8),
                pw.Divider(color: PdfColors.grey600),
                pw.SizedBox(height: 6),
                pw.Text(
                  'المبلغ المدفوع: ${amountPaid.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: fontBold, fontSize: 12),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'الذمة قبل الدفعة: ${payableBefore.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'الذمة بعد الدفعة: ${payableAfter.toStringAsFixed(0)} د.ع',
                  style: pw.TextStyle(font: font, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  affectsCash
                      ? 'تم خصم المبلغ من الصندوق.'
                      : 'لم يُخصم من الصندوق (دفع خارج النظام أو بنكي).',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 10,
                    color: PdfColors.grey800,
                  ),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                if (_receiptSafe(note).isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'ملاحظة: ${_receiptSafe(note)}',
                    style: pw.TextStyle(font: font, fontSize: 10),
                    textAlign: pw.TextAlign.right,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
                pw.SizedBox(height: 10),
                pw.Text(
                  'سجل الدفعة: #$payoutRowId',
                  style: pw.TextStyle(font: font, fontSize: 10),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'سند القائمة (فواتير): #$receiptInvoiceId',
                  style: pw.TextStyle(font: fontBold, fontSize: 11),
                  textAlign: pw.TextAlign.right,
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 16),
                if (s.receiptShowQr) ...[
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: bc.Barcode.qrCode(),
                      data: qrPayload,
                      width: 110,
                      height: 110,
                      drawText: false,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text(
                      'امسح لفتح تفاصيل السند في التطبيق',
                      style: pw.TextStyle(font: font, fontSize: 9),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  static Future<void> presentSupplierPaymentReceipt(
    BuildContext context, {
    required String supplierDisplayName,
    required double amountPaid,
    required double payableBefore,
    required double payableAfter,
    required int payoutRowId,
    required int receiptInvoiceId,
    required bool affectsCash,
    String? note,
    String? recordedByUserName,
    PrintSettingsData? printSettings,
  }) async {
    if (!context.mounted) return;
    final settings =
        printSettings ?? await PrintSettingsRepository.instance.load();
    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (ctx) {
          return Directionality(
            textDirection: ui.TextDirection.rtl,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('إيصال دفع مورد'),
              ),
              body: printing.PdfPreview(
                maxPageWidth: 720,
                initialPageFormat: settings.pdfPageFormat,
                canChangePageFormat: true,
                canChangeOrientation: false,
                allowPrinting: true,
                allowSharing: true,
                canDebug: false,
                pdfFileName:
                    'supplier-payment-$payoutRowId-$receiptInvoiceId.pdf',
                build: (() {
                  final cache = <String, Future<Uint8List>>{};
                  return (format) {
                    final key =
                        '$payoutRowId|$receiptInvoiceId|${format.width}x${format.height}|${format.marginLeft},${format.marginTop},${format.marginRight},${format.marginBottom}|${settings.hashCode}';
                    return cache.putIfAbsent(
                      key,
                      () => buildSupplierPaymentReceiptBytes(
                        supplierDisplayName: supplierDisplayName,
                        amountPaid: amountPaid,
                        payableBefore: payableBefore,
                        payableAfter: payableAfter,
                        payoutRowId: payoutRowId,
                        receiptInvoiceId: receiptInvoiceId,
                        affectsCash: affectsCash,
                        note: note,
                        recordedByUserName: recordedByUserName,
                        pageFormat: format,
                        settings: settings,
                      ),
                    );
                  };
                })(),
              ),
            ),
          );
        },
      ),
    );
  }
}
