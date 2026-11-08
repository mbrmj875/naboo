/// مرجع فاتورة مقروء من رمز QR.
class InvoiceLinkRef {
  const InvoiceLinkRef(this.localId, this.globalId);

  /// الرقم المحلي كما طُبع (للعرض فقط: يختلف بين الأجهزة).
  final int localId;

  /// المعرّف العالمي (UUID) — المرجع الموثوق. فارغ في الرموز القديمة.
  final String? globalId;

  /// رمز قديم بلا معرّف عالمي: لا يُوثق به في العمليات الحساسة.
  bool get isLegacy => globalId == null || globalId!.isEmpty;
}

/// رابط مخصّص يُطبَع في QR الإيصالات؛ عند مسحه يفتح التطبيق الفاتورة.
///
/// الصيغة الحالية: `basrainvoice://invoice/<id>?g=<global_id>`.
/// المعرّف العالمي عشوائي وموحّد على كل أجهزة المحل، فلا يُخمَّن ولا يختلط
/// برقم محلي لفاتورة أخرى على جهاز ثانٍ. الصيغة القديمة (بلا `g`) تبقى مقروءة.
abstract class InvoiceDeepLink {
  static const String scheme = 'basrainvoice';
  static const String host = 'invoice';

  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static String uriForInvoiceId(int id, {String? globalId}) {
    final g = globalId?.trim() ?? '';
    return g.isEmpty ? '$scheme://$host/$id' : '$scheme://$host/$id?g=$g';
  }

  static InvoiceLinkRef? parse(Uri uri) {
    if (uri.scheme != scheme || uri.host != host) return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    int? id;
    if (segs.isNotEmpty) id = int.tryParse(segs.first);
    if (id == null) {
      final p = uri.path.replaceFirst(RegExp(r'^/+'), '');
      if (p.isNotEmpty) id = int.tryParse(p);
    }
    if (id == null || id <= 0) return null;
    final g = uri.queryParameters['g']?.trim();
    // معرّف بصيغة غير صحيحة = رمز معطوب أو مُعدَّل: لا نسقطه للرقم المحلي.
    if (g != null && g.isNotEmpty && !_uuid.hasMatch(g)) return null;
    return InvoiceLinkRef(
      id,
      (g == null || g.isEmpty) ? null : g.toLowerCase(),
    );
  }

  static int? parseInvoiceId(Uri uri) => parse(uri)?.localId;
}
