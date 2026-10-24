import 'dart:isolate';

import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/print_settings_data.dart';
import '../../../utils/app_logger.dart';
import '../utils/oil_change_log_format.dart';

class _OilCardPdfInput {
  const _OilCardPdfInput({
    required this.regularFont,
    required this.boldFont,
    required this.shop,
    required this.address,
    required this.phones,
    required this.mapsUrl,
    required this.generatedAtIso,
    required this.rows,
    this.logo,
  });

  final Uint8List regularFont;
  final Uint8List boldFont;
  final Uint8List? logo;
  final String shop;
  final String address;
  final List<String> phones;
  final String mapsUrl;
  final String generatedAtIso;
  final List<List<String>> rows;
}

Map<String, Object?> _pdfJobMap(_OilCardPdfInput input) {
  return {
    'regularFont': input.regularFont,
    'boldFont': input.boldFont,
    'logo': input.logo,
    'shop': input.shop,
    'address': input.address,
    'phones': input.phones,
    'mapsUrl': input.mapsUrl,
    'generatedAtIso': input.generatedAtIso,
    'rows': input.rows,
  };
}

Future<Uint8List> _renderOilChangeCardPdf(Map<String, Object?> raw) async {
  final regularBytes = raw['regularFont'] as Uint8List;
  final boldBytes = raw['boldFont'] as Uint8List;
  final logo = raw['logo'] as Uint8List?;
  final shop = raw['shop'] as String? ?? '';
  final address = raw['address'] as String? ?? '';
  final phones = (raw['phones'] as List?)?.map((e) => e.toString()).toList() ??
      const <String>[];
  final mapsUrl = (raw['mapsUrl'] as String? ?? '').trim();
  final generatedAtIso = raw['generatedAtIso'] as String? ?? '';
  final rows = ((raw['rows'] as List?) ?? const [])
      .map((e) => (e as List).map((c) => c.toString()).toList())
      .toList();

  final regular = pw.Font.ttf(ByteData.sublistView(regularBytes));
  final bold = pw.Font.ttf(ByteData.sublistView(boldBytes));
  final generatedAt = DateTime.tryParse(generatedAtIso) ?? DateTime.now();
  // بدون locale: يعمل داخل Isolate بدون initializeDateFormatting.
  final dateLabel = DateFormat('d/M/y HH:mm').format(generatedAt);
  final storePhones = phones.map((p) => p.trim()).where((p) => p.isNotEmpty);
  final pageWidth = 86 * PdfPageFormat.mm;
  var pageHeight = 28.0;
  if (logo != null && logo.isNotEmpty) pageHeight += 62;
  if (shop.trim().isNotEmpty) pageHeight += 26;
  pageHeight += 18 + 16 + 14;
  pageHeight += 26 + rows.length * 22;
  pageHeight += storePhones.length * 16;
  if (address.trim().isNotEmpty) pageHeight += 18;
  if (mapsUrl.isNotEmpty) pageHeight += 132;
  pageHeight += 24;

  const navy = PdfColor.fromInt(0xFF0B1F4A);
  const gold = PdfColor.fromInt(0xFFC9A227);
  const muted = PdfColor.fromInt(0xFF5C6B7A);

  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(pageWidth, pageHeight.clamp(320, 1400)),
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.fromLTRB(14, 16, 14, 16),
      build: (ctx) {
        final children = <pw.Widget>[];
        if (logo != null && logo.isNotEmpty) {
          try {
            children.add(
              pw.Center(child: pw.Image(pw.MemoryImage(logo), height: 52)),
            );
            children.add(pw.SizedBox(height: 8));
          } catch (_) {
            /* شعار تالف لا يمنع الملف */
          }
        }
        if (shop.trim().isNotEmpty) {
          children.add(
            pw.Center(
              child: pw.Text(
                shop.trim(),
                style: pw.TextStyle(font: bold, fontSize: 16, color: navy),
              ),
            ),
          );
          children.add(pw.SizedBox(height: 6));
        }
        children.add(
          pw.Center(
            child: pw.Container(width: 72, height: 1.2, color: gold),
          ),
        );
        children.add(pw.SizedBox(height: 8));
        children.add(
          pw.Center(
            child: pw.Text(
              'بطاقة غيار الزيت',
              style: pw.TextStyle(font: bold, fontSize: 12, color: navy),
            ),
          ),
        );
        children.add(
          pw.Center(
            child: pw.Text(
              'تاريخ الفاتورة: $dateLabel',
              style: pw.TextStyle(font: regular, fontSize: 9, color: muted),
            ),
          ),
        );
        children.add(pw.SizedBox(height: 10));
        if (rows.isNotEmpty) {
          pw.Widget cell(String text, pw.Font font, {bool header = false}) {
            return pw.Container(
              color: header ? const PdfColor.fromInt(0xFFEEF2F6) : null,
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                text,
                style: pw.TextStyle(font: font, fontSize: 9, color: navy),
              ),
            );
          }

          children.add(
            pw.Table(
              border: pw.TableBorder.all(
                color: const PdfColor.fromInt(0xFFD5DBE3),
                width: 0.6,
              ),
              columnWidths: const {
                0: pw.FlexColumnWidth(42),
                1: pw.FlexColumnWidth(58),
              },
              children: [
                pw.TableRow(
                  children: [
                    cell('البيان', bold, header: true),
                    cell('التفاصيل', bold, header: true),
                  ],
                ),
                for (var i = 0; i < rows.length; i++)
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: i.isOdd
                          ? const PdfColor.fromInt(0xFFF7F8FA)
                          : PdfColors.white,
                    ),
                    children: [
                      cell(rows[i][0], bold),
                      cell(rows[i][1], regular),
                    ],
                  ),
              ],
            ),
          );
          children.add(pw.SizedBox(height: 10));
        }
        for (final phone in storePhones) {
          children.add(
            pw.Center(
              child: pw.Text(
                'رقم التواصل: $phone',
                style: pw.TextStyle(font: regular, fontSize: 10, color: navy),
              ),
            ),
          );
        }
        if (address.trim().isNotEmpty) {
          children.add(
            pw.Center(
              child: pw.Text(
                'الموقع: ${address.trim()}',
                style: pw.TextStyle(font: regular, fontSize: 10, color: navy),
              ),
            ),
          );
        }
        if (mapsUrl.isNotEmpty) {
          children.add(pw.SizedBox(height: 6));
          children.add(
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: bc.Barcode.qrCode(),
                data: mapsUrl,
                width: 100,
                height: 100,
              ),
            ),
          );
          children.add(
            pw.Center(
              child: pw.Text(
                'امسح لفتح الموقع',
                style: pw.TextStyle(font: regular, fontSize: 8, color: muted),
              ),
            ),
          );
        }
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: children,
        );
      },
    ),
  );
  return pdf.save();
}

/// يولّد PDF بطاقة الغيار ويرفعه للتخزين — الإرسال عبر Cloud API بعد الصمت.
class OilChangeWhatsappCardPdfService {
  OilChangeWhatsappCardPdfService._();

  static final OilChangeWhatsappCardPdfService instance =
      OilChangeWhatsappCardPdfService._();

  static const bucket = 'whatsapp-oil-card-pdfs';

  Future<void> prepareAfterOfficialCard({
    required String customerPhone,
    required Map<String, dynamic> order,
    required PrintSettingsData printSettings,
    required Map<String, String> templateParams,
    int? orderId,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (orderId == null || orderId <= 0) return;

    try {
      final bytes = await _buildPdf(
        order: order,
        printSettings: printSettings,
      );
      if (bytes.isEmpty) return;

      final objectPath = '${user.id}/$orderId.pdf';
      await Supabase.instance.client.storage.from(bucket).uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: true,
            ),
          );

      await _upsertJobRow(
        tenantUserId: user.id,
        orderRef: '$orderId',
        customerPhone: customerPhone,
        objectPath: objectPath,
        cardPayload: _cardPayloadWithStore(templateParams, printSettings),
      );
    } catch (e, st) {
      AppLogger.error('oil_change_wa_pdf', 'prepare after card', e, st);
    }
  }

  Future<Uint8List> _buildPdf({
    required Map<String, dynamic> order,
    required PrintSettingsData printSettings,
  }) async {
    final regular =
        await rootBundle.load('assets/fonts/Tajawal-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/Tajawal-Bold.ttf');
    final input = _OilCardPdfInput(
      regularFont: regular.buffer.asUint8List(),
      boldFont: bold.buffer.asUint8List(),
      logo: printSettings.storeLogoBytes,
      shop: printSettings.storeTitleLine.trim(),
      address: printSettings.storeAddress.trim(),
      phones: printSettings.storePhones,
      mapsUrl: printSettings.storeMapsUrl ?? '',
      generatedAtIso: DateTime.now().toIso8601String(),
      rows: _cardRows(order),
    );
    return Isolate.run(() => _renderOilChangeCardPdf(_pdfJobMap(input)));
  }

  List<List<String>> _cardRows(Map<String, dynamic> order) {
    String cell(String? raw) {
      final t = (raw ?? '').trim();
      if (t.isEmpty || t == '-') return '—';
      return t;
    }

    void add(List<List<String>> out, String label, String? value) {
      final v = cell(value);
      if (v == '—') return;
      out.add([label, v]);
    }

    final car = [
      (order['deviceName'] ?? '').toString().trim(),
      (order['carModel'] ?? '').toString().trim(),
    ].where((e) => e.isNotEmpty).join(' · ');

    final out = <List<String>>[];
    add(out, 'الزبون', (order['customerNameSnapshot'] ?? '').toString());
    add(out, 'الهاتف', oilFormatPhone(order));
    add(out, 'السيارة', car);
    add(out, 'اللوحة', oilFormatPlate(order));
    add(out, 'الزيت', (order['oilType'] ?? '').toString());
    add(out, 'اللزوجة', (order['oilViscosity'] ?? '').toString());
    add(out, 'الكمية', oilFormatLitersOrSize(order));
    add(out, 'مصدر الزيت', oilFormatOilSource(order));
    add(out, 'هيدروليك القير', (order['hydraulicType'] ?? '').toString());
    add(out, 'هيدروليك الباور', (order['powerHydraulicType'] ?? '').toString());
    add(out, 'الفلاتر', oilFormatFilterType(order));
    add(
      out,
      'الخدمات',
      oilFormatServicesShort(
        parseOilRequestedServices(order['requestedServices']?.toString()),
      ),
    );
    add(out, 'الفني', oilFormatTechnician(order));
    add(out, 'العداد', oilFormatOdo(order['odometerCurrent']?.toString()));
    add(out, 'الغيار القادم', oilFormatOdo(order['odometerNext']?.toString()));
    add(out, 'الإجمالي', oilFormatPrice(order));
    return out;
  }

  Map<String, String> _cardPayloadWithStore(
    Map<String, String> templateParams,
    PrintSettingsData printSettings,
  ) {
    final out = Map<String, String>.from(templateParams);
    final name = printSettings.storeTitleLine.trim();
    final address = printSettings.storeAddress.trim();
    final phones = printSettings.storePhones
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .join(' · ');
    final maps = (printSettings.storeMapsUrl ?? '').trim();
    if (name.isNotEmpty) out['store_name'] = name;
    if (address.isNotEmpty) out['store_address'] = address;
    if (phones.isNotEmpty) out['store_phone'] = phones;
    if (maps.isNotEmpty) out['store_maps'] = maps;
    return out;
  }

  Future<void> _upsertJobRow({
    required String tenantUserId,
    required String orderRef,
    required String customerPhone,
    required String objectPath,
    required Map<String, String> cardPayload,
  }) async {
    final digits = customerPhone.replaceAll(RegExp(r'\D'), '');
    final client = Supabase.instance.client;
    final existing = await client
        .from('whatsapp_oil_card_pdf_jobs')
        .select('id, status')
        .eq('tenant_user_id', tenantUserId)
        .eq('order_ref', orderRef)
        .maybeSingle();

    if (existing == null) {
      await client.from('whatsapp_oil_card_pdf_jobs').insert({
        'tenant_user_id': tenantUserId,
        'order_ref': orderRef,
        'to_phone': digits,
        'pdf_storage_path': objectPath,
        'card_payload': cardPayload,
        'status': 'awaiting_inbound',
      });
      return;
    }

    await client.from('whatsapp_oil_card_pdf_jobs').update({
      'pdf_storage_path': objectPath,
      'card_payload': cardPayload,
      if (digits.length >= 10) 'to_phone': digits,
    }).eq('id', existing['id']);
  }
}
