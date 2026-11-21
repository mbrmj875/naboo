import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';
import '../../../utils/iqd_money.dart';
import '../models/oil_change_filter_catalog_entry.dart';
import '../models/oil_change_filter_kind.dart';

/// فلاتر بطاقة الغيار من أصناف المخزون، حسب حقل «الصنف» في المنتج.
///
/// - الصنف باسم الفئة يظهر في خانتها: «فلتر المحرك» في خانة المحرك.
/// - الصنف العام «فلتر» يظهر في كل الخانات.
/// - المطابقة متسامحة: «فلتر محرك» = «فلتر المحرك»، الهمزات والتاء المربوطة
///   والمسافات لا تفرق.
class OilFilterStockCatalog {
  OilFilterStockCatalog._();

  static const genericCategory = 'فلتر';

  /// يحوّل النص إلى كلمات موحّدة: بلا «ال» في أول الكلمة، وبلا تشكيل،
  /// والهمزات ألف، والتاء المربوطة هاء، والألف المقصورة ياء.
  static List<String> normalizedWords(String raw) {
    var t = raw.trim().toLowerCase();
    t = t.replaceAll(RegExp('[ً-ٰٟـ]'), '');
    t = t
        .replaceAll(RegExp('[أإآٱ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي');
    final words = <String>[];
    for (var w in t.split(RegExp(r'[\s\-_/،,.]+'))) {
      if (w.isEmpty) continue;
      if (w.length > 3 && w.startsWith('ال')) w = w.substring(2);
      words.add(w);
    }
    return words;
  }

  static String normalizedKey(String raw) => normalizedWords(raw).join(' ');

  static bool isGenericCategory(String category) =>
      normalizedKey(category) == normalizedKey(genericCategory);

  /// هل يظهر منتج صنفه [category] في خانة الفئة [kind]؟
  static bool categoryMatchesKind(String category, OilChangeFilterKind kind) {
    final c = normalizedKey(category);
    if (c.isEmpty) return false;
    if (c == normalizedKey(genericCategory)) return true;
    return c == normalizedKey(kind.label);
  }

  /// منتجات المخزون التي صنفها فلتر، كمدخلات لكل فئة تطابقها.
  ///
  /// [id] في كل مدخل = معرّف المنتج، فهو فريد داخل الفئة الواحدة.
  static Future<List<OilChangeFilterCatalogEntry>> load(
    List<OilChangeFilterKind> kinds,
  ) async {
    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    final tid = t.requireActiveTenantId();
    final db = await DatabaseHelper().database;
    final rows = await db.rawQuery(
      '''
      SELECT p.id, p.name, p.sellPrice, p.qty, c.name AS categoryName
      FROM products p
      JOIN categories c ON c.id = p.categoryId
      WHERE p.tenantId = ?
        AND p.isActive = 1
        AND IFNULL(p.isService, 0) = 0
        AND IFNULL(p.variantKind, 0) NOT IN (2, 3)
        AND c.name LIKE '%فلتر%'
      ORDER BY p.name COLLATE NOCASE
      ''',
      [tid],
    );
    final out = <OilChangeFilterCatalogEntry>[];
    for (final r in rows) {
      final category = (r['categoryName'] ?? '').toString();
      final id = (r['id'] as num).toInt();
      final sell = (r['sellPrice'] as num?)?.toDouble() ?? 0;
      for (final kind in kinds) {
        if (!categoryMatchesKind(category, kind)) continue;
        out.add(
          OilChangeFilterCatalogEntry(
            id: id,
            kind: kind,
            name: (r['name'] ?? '').toString().trim(),
            priceFils: IqdMoney.toFils(sell),
            productId: id,
            availableQty: (r['qty'] as num?)?.toDouble(),
          ),
        );
      }
    }
    return out;
  }

  /// أسماء الفئات كاقتراحات لحقل «الصنف» في إضافة منتج.
  static List<String> categorySuggestions(List<OilChangeFilterKind> kinds) => [
        for (final k in kinds) k.label,
        genericCategory,
      ];
}
