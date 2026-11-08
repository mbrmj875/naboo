import '../models/invoice.dart';
import '../printing/receipt_builders.dart';
import '../printing/receipt_model.dart';
import '../services/database_helper.dart';
import '../utils/invoice_deep_link.dart';

/// إيصال ممسوح بعد التحقق منه في قاعدة هذا المحل.
class ScannedReceipt {
  const ScannedReceipt({
    required this.invoice,
    required this.kind,
    required this.legacy,
    this.order,
  });

  final Invoice invoice;
  final ReceiptKind kind;

  /// بطاقة الزيت/الغسيل المرتبطة بالفاتورة إن وُجدت.
  final Map<String, dynamic>? order;

  /// رمز قديم بلا معرّف عالمي: الفاتورة وُجدت برقمها المحلي فقط.
  final bool legacy;

  int get invoiceId => invoice.id!;
}

/// نتيجة البحث: إيصال، أو رسالة توضح للموظف لماذا لم يُفتح شيء.
class ScannedReceiptResult {
  const ScannedReceiptResult.found(ScannedReceipt this.receipt) : error = null;
  const ScannedReceiptResult.error(String this.error) : receipt = null;

  final ScannedReceipt? receipt;
  final String? error;
}

/// يحوّل رمز QR الإيصال إلى فاتورة هذا المحل ونوع عملها.
abstract final class ScannedReceiptLookup {
  /// للاختبارات: استبدال الوصول للقاعدة.
  static Future<int?> Function(String globalId) idForGlobalId = (g) =>
      DatabaseHelper().getInvoiceIdByGlobalId(g);
  static Future<Invoice?> Function(int id) loadInvoice = (id) =>
      DatabaseHelper().getInvoiceById(id);
  static Future<Map<String, dynamic>?> Function(int invoiceId) loadOrder =
      ReceiptBuilders.linkedOrder;

  static Future<ScannedReceiptResult> resolve(InvoiceLinkRef ref) async {
    int? id;
    if (ref.isLegacy) {
      id = ref.localId;
    } else {
      id = await idForGlobalId(ref.globalId!);
      if (id == null) {
        // المعرّف العالمي لا يُخمَّن: غيابه يعني محلاً آخر أو فاتورة لم تصل
        // بعد لهذا الجهاز (المزامنة).
        return const ScannedReceiptResult.error(
          'هذا الإيصال غير موجود في محلك. إن كان من جهاز آخر في المحل، '
          'انتظر المزامنة ثم امسحه مرة ثانية.',
        );
      }
    }
    final invoice = await loadInvoice(id);
    if (invoice == null || invoice.id == null) {
      return ScannedReceiptResult.error('لا توجد فاتورة برقم ${ref.localId}.');
    }
    final order = await loadOrder(invoice.id!);
    return ScannedReceiptResult.found(
      ScannedReceipt(
        invoice: invoice,
        order: order,
        kind: ReceiptBuilders.kindOf(invoice, order: order),
        legacy: ref.isLegacy,
      ),
    );
  }
}
