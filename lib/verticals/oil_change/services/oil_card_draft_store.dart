import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/tenant_context_service.dart';
import '../models/oil_change_product_line.dart';

/// مسودة بطاقة غيار جديدة واحدة، محلية على هذا الجهاز (لا تُزامَن).
///
/// تُحفظ تلقائياً أثناء الكتابة، وتُعرض عند فتح بطاقة جديدة، وتُمسح عند
/// الحفظ أو التعليق أو «مسح الحقول» أو تجاهلها.
class OilCardDraft {
  const OilCardDraft({
    required this.row,
    required this.productLines,
    required this.savedAt,
  });

  /// صف بنفس أعمدة البطاقة، يُملأ به النموذج كما يُملأ في التعديل.
  final Map<String, dynamic> row;
  final List<OilChangeProductLine> productLines;
  final DateTime savedAt;

  String get summary {
    final bits = <String>[
      for (final k in ['customerNameSnapshot', 'deviceName', 'deviceSerial'])
        if ((row[k] ?? '').toString().trim().isNotEmpty)
          (row[k] ?? '').toString().trim(),
    ];
    return bits.isEmpty ? 'بطاقة بلا اسم' : bits.join(' — ');
  }

  static Map<String, Object?> productLineToJson(OilChangeProductLine l) => {
        'productId': l.productId,
        'productName': l.productName,
        'quantity': l.quantity,
        'priceFils': l.priceFils,
        'unitVariantId': l.unitVariantId,
        'unitLabel': l.unitLabel,
        'unitFactor': l.unitFactor,
        'literPriceFils': l.literPriceFils,
      };

  static OilChangeProductLine? productLineFromJson(Map<String, dynamic> m) {
    final pid = (m['productId'] as num?)?.toInt() ?? 0;
    final q = (m['quantity'] as num?)?.toInt() ?? 1;
    final p = (m['priceFils'] as num?)?.toInt() ?? 0;
    final f = (m['unitFactor'] as num?)?.toDouble() ?? 1;
    if (pid <= 0) return null;
    return OilChangeProductLine(
      productId: pid,
      productName: (m['productName'] ?? '').toString(),
      quantity: q <= 0 ? 1 : q,
      priceFils: p < 0 ? 0 : p,
      unitVariantId: (m['unitVariantId'] as num?)?.toInt(),
      unitLabel: (m['unitLabel'] ?? '').toString(),
      unitFactor: f <= 0 ? 1 : f,
      literPriceFils: (m['literPriceFils'] as num?)?.toInt(),
    );
  }
}

class OilCardDraftStore {
  OilCardDraftStore._();
  static final OilCardDraftStore instance = OilCardDraftStore._();

  static const _prefix = 'oil_card_draft_v1_';

  Future<String> _key() async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    return '$_prefix${t.activeTenantId}';
  }

  /// آخر ما كُتب — لتجنب كتابة نفس المسودة كل مرة.
  String? _lastWritten;

  Future<void> save(
    Map<String, dynamic> row,
    List<OilChangeProductLine> productLines,
  ) async {
    final payload = jsonEncode({
      'row': row,
      'products': [
        for (final l in productLines) OilCardDraft.productLineToJson(l),
      ],
    });
    if (payload == _lastWritten) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      await _key(),
      jsonEncode({
        'savedAt': DateTime.now().toUtc().toIso8601String(),
        'payload': payload,
      }),
    );
    _lastWritten = payload;
  }

  Future<OilCardDraft?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(await _key());
      if (raw == null || raw.isEmpty) return null;
      final outer = jsonDecode(raw) as Map<String, dynamic>;
      final inner =
          jsonDecode(outer['payload'] as String) as Map<String, dynamic>;
      final row = Map<String, dynamic>.from(inner['row'] as Map);
      final products = <OilChangeProductLine>[];
      for (final m in (inner['products'] as List? ?? const [])) {
        if (m is! Map) continue;
        final line =
            OilCardDraft.productLineFromJson(Map<String, dynamic>.from(m));
        if (line != null) products.add(line);
      }
      return OilCardDraft(
        row: row,
        productLines: products,
        savedAt: DateTime.tryParse((outer['savedAt'] ?? '').toString())
                ?.toLocal() ??
            DateTime.now(),
      );
    } catch (_) {
      // مسودة تالفة لا تمنع فتح البطاقة.
      await clear();
      return null;
    }
  }

  Future<void> clear() async {
    _lastWritten = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _key());
  }
}
