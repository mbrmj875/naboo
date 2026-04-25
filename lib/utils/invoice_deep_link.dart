/// رابط مخصّص يُطبَع في QR إيصالات «تقسيط / دين»؛ عند فتحه يعرض التطبيق تفاصيل الفاتورة.
abstract class InvoiceDeepLink {
  static const String scheme = 'basrainvoice';
  static const String host = 'invoice';

  static String uriForInvoiceId(int id) => '$scheme://$host/$id';

  static int? parseInvoiceId(Uri uri) {
    if (uri.scheme != scheme || uri.host != host) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty) return int.tryParse(segs.first);
    final p = uri.path.replaceFirst(RegExp(r'^/+'), '');
    if (p.isEmpty) return null;
    return int.tryParse(p);
  }
}
