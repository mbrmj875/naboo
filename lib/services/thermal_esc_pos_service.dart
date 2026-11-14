import 'dart:convert';
import 'dart:typed_data';

import '../models/invoice.dart';
import '../models/print_settings_data.dart';
import '../utils/app_logger.dart';
import '../utils/sale_receipt_pdf.dart';

/// مولّد بسيط لأوامر ESC/POS لإيصال البيع.
///
/// ملاحظة: هذا المولّد لا يتصل بالطابعة مباشرة؛
/// بل يجهّز payload خام (bytes/base64) لإرساله عبر bridge (Bluetooth/USB/LAN).
class ThermalEscPosService {
  ThermalEscPosService._();
  static final ThermalEscPosService instance = ThermalEscPosService._();

  String buildReceiptText({
    required Invoice invoice,
    required double subtotalBeforeDiscount,
    required PrintSettingsData settings,
  }) {
    final width = settings.paperFormat == PrintPaperFormat.thermal58 ? 32 : 48;
    final out = <String>[];
    final title = settings.storeTitleLine.trim();
    final customer = invoice.customerName.trim();
    final staff = (invoice.createdByUserName ?? '').trim();
    final date = '${invoice.date.year.toString().padLeft(4, '0')}/'
        '${invoice.date.month.toString().padLeft(2, '0')}/'
        '${invoice.date.day.toString().padLeft(2, '0')} '
        '${invoice.date.hour.toString().padLeft(2, '0')}:'
        '${invoice.date.minute.toString().padLeft(2, '0')}';

    if (title.isNotEmpty) {
      out.add(_center(title, width));
      out.add(_line(width));
    }
    for (final line in settings.receiptStoreContactLines) {
      if (line.trim().isNotEmpty) {
        out.add(_center(line.trim(), width));
      }
    }
    if (settings.receiptStoreContactLines.isNotEmpty) {
      out.add(_line(width));
    }
    out.add('إيصال بيع');
    out.add('رقم: ${invoice.id ?? '-'}');
    out.add('التاريخ: $date');
    if (customer.isNotEmpty) out.add('العميل: $customer');
    if (staff.isNotEmpty) out.add('الموظف: $staff');
    out.add(_line(width));

    for (final item in invoice.items) {
      final name = item.productName.trim().isEmpty ? 'صنف' : item.productName.trim();
      final qty = item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 3);
      final total = item.total.toStringAsFixed(0);
      final line = '$name x$qty';
      out.add(_truncate(line, width));
      out.add(_alignAmount(total, width));
    }

    out.add(_line(width));
    out.add('قبل الخصم: ${subtotalBeforeDiscount.toStringAsFixed(0)} د.ع');
    out.add('الخصم: ${invoice.discount.toStringAsFixed(0)} د.ع');
    out.add('الضريبة: ${invoice.tax.toStringAsFixed(0)} د.ع');
    out.add('الإجمالي: ${invoice.total.toStringAsFixed(0)} د.ع');
    out.add('الدفع: ${salePaymentLabel(invoice.type)}');
    final footer = settings.footerExtra.trim();
    if (footer.isNotEmpty) {
      out.add(_line(width));
      for (final l in footer.split('\n')) {
        if (l.trim().isNotEmpty) out.add(_truncate(l.trim(), width));
      }
    }
    return out.join('\n');
  }

  Uint8List buildReceiptBytes({
    required Invoice invoice,
    required double subtotalBeforeDiscount,
    required PrintSettingsData settings,
  }) {
    final text = buildReceiptText(
      invoice: invoice,
      subtotalBeforeDiscount: subtotalBeforeDiscount,
      settings: settings,
    );
    final bytes = BytesBuilder();
    try {
      bytes.add(const [0x1B, 0x40]); // Initialize
      bytes.add(const [0x1B, 0x61, 0x01]); // center
      bytes.add(utf8.encode(settings.storeTitleLine.trim()));
      bytes.addByte(0x0A);
      bytes.add(const [0x1B, 0x61, 0x00]); // left
      bytes.add(utf8.encode(text));
      bytes.addByte(0x0A);
      bytes.addByte(0x0A);
      bytes.add(const [0x1D, 0x56, 0x00]); // full cut
    } catch (e, st) {
      AppLogger.error('EscPos', 'buildReceiptBytes failed', e, st);
      return Uint8List.fromList(utf8.encode(text));
    }
    return bytes.toBytes();
  }

  String buildReceiptBase64({
    required Invoice invoice,
    required double subtotalBeforeDiscount,
    required PrintSettingsData settings,
  }) {
    final raw = buildReceiptBytes(
      invoice: invoice,
      subtotalBeforeDiscount: subtotalBeforeDiscount,
      settings: settings,
    );
    return base64Encode(raw);
  }

  String _line(int width) => ''.padLeft(width, '-');

  String _truncate(String input, int width) {
    final t = input.trim();
    if (t.length <= width) return t;
    return '${t.substring(0, width - 1)}…';
  }

  String _center(String input, int width) {
    final t = _truncate(input, width);
    final pad = ((width - t.runes.length) / 2).floor();
    return ''.padLeft(pad > 0 ? pad : 0) + t;
  }

  String _alignAmount(String amount, int width) {
    final text = '$amount د.ع';
    if (text.runes.length >= width) return text;
    return ''.padLeft(width - text.runes.length) + text;
  }
}
