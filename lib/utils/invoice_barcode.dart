import 'customer_debt_deep_link.dart';

/// يستخرج رقم فاتورة البيع من باركود الإيصال المطبوع أو من QR المختصر.
/// يدعم: `INV-12`، `inv-12`، `naboo-inv:12` (مع أو بدون مسافات).
int? tryParseInvoiceIdFromBarcode(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final inv = RegExp(r'^INV-(\d+)\s*$', caseSensitive: false).firstMatch(s);
  if (inv != null) return int.tryParse(inv.group(1)!);
  final naboo =
      RegExp(r'^naboo-inv:(\d+)\s*$', caseSensitive: false).firstMatch(s);
  if (naboo != null) return int.tryParse(naboo.group(1)!);
  return null;
}

bool looksLikeInvoiceReceiptBarcode(String raw) =>
    tryParseInvoiceIdFromBarcode(raw) != null;

/// معرّف عميل من QR ديون (`basrainvoice://customer-debt/…`).
int? tryParseCustomerDebtIdFromScannedText(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final u = Uri.tryParse(t);
  if (u != null) {
    final id = CustomerDebtDeepLink.parseCustomerId(u);
    if (id != null && id > 0) return id;
  }
  return null;
}
