import 'dart:isolate';

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
  final generatedAtIso = raw['generatedAtIso'] as String? ?? '';
  final rows = ((raw['rows'] as List?) ?? const [])
      .map((e) => (e as List).map((c) => c.toString()).toList())
      .toList();

  final regular = pw.Font.ttf(ByteData.sublistView(regularBytes));
  final bold = pw.Font.ttf(ByteData.sublistView(boldBytes));
  final generatedAt = DateTime.tryParse(generatedAtIso) ?? DateTime.now();
  // بدون locale: يعمل داخل Isolate بدون initializeDateFormatting.
  final dateLabel = DateFormat('d/M/y HH:mm').format(generatedAt);

  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 36),
      build: (ctx) {
        final header = <pw.Widget>[];
        if (logo != null && logo.isNotEmpty) {
          try {
            header.add(
              pw.Center(child: pw.Image(pw.MemoryImage(logo), height: 56)),
            );
            header.add(pw.SizedBox(height: 8));
          } catch (_) {
            /* شعار تالف لا يمنع الملف */
          }
        }
        if (shop.trim().isNotEmpty) {
          header.add(
            pw.Center(
              child: pw.Text(
                shop.trim(),
                style: pw.TextStyle(font: bold, fontSize: 18),
              ),
            ),
          );
          header.add(pw.SizedBox(height: 4));
        }
        if (address.trim().isNotEmpty) {
          header.add(
            pw.Center(
              child: pw.Text(
                address.trim(),
                style: pw.TextStyle(font: regular, fontSize: 10),
              ),
            ),
          );
        }
        for (final phone in phones) {
          if (phone.trim().isEmpty) continue;
          header.add(
            pw.Center(
              child: pw.Text(
                phone.trim(),
                style: pw.TextStyle(font: regular, fontSize: 10),
              ),
            ),
          );
        }
        header.add(pw.SizedBox(height: 10));
        header.add(
          pw.Center(
            child: pw.Text(
              'بطاقة غيار الزيت',
              style: pw.TextStyle(font: bold, fontSize: 14),
            ),
          ),
        );
        header.add(
          pw.Center(
            child: pw.Text(
              dateLabel,
              style: pw.TextStyle(font: regular, fontSize: 10),
            ),
          ),
        );
        header.add(pw.SizedBox(height: 16));
        header.add(
          pw.TableHelper.fromTextArray(
            headers: const ['البيان', 'التفاصيل'],
            data: rows,
            headerStyle: pw.TextStyle(font: bold, fontSize: 11),
            cellStyle: pw.TextStyle(font: regular, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignment: pw.Alignment.centerRight,
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
          ),
        );
        return header;
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
        cardPayload: templateParams,
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
