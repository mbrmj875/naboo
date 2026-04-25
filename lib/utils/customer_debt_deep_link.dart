/// رابط يُطبَع في QR وصل تسديد دين؛ عند المسح يفتح شاشة ديون العميل.
abstract class CustomerDebtDeepLink {
  static const String scheme = 'basrainvoice';
  static const String host = 'customer-debt';

  static String uriForCustomerId(int id) => '$scheme://$host/$id';

  static int? parseCustomerId(Uri uri) {
    if (uri.scheme != scheme || uri.host != host) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty) return int.tryParse(segs.first);
    final p = uri.path.replaceFirst(RegExp(r'^/+'), '');
    if (p.isEmpty) return null;
    return int.tryParse(p);
  }
}
