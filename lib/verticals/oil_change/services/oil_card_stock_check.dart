import '../../../services/database_helper.dart';
import '../../../services/tenant_context_service.dart';

/// كمية يحتاجها قسم من البطاقة من صنف مخزون واحد.
class OilStockNeed {
  const OilStockNeed({
    required this.label,
    required this.productId,
    required this.qty,
    this.credit = 0,
    this.unit = 'قطعة',
  });

  /// اسم القسم للعرض: «الزيت»، «فلتر المحرك»، «منتج: ...».
  final String label;
  final int productId;
  final double qty;

  /// ما صُرف سابقاً من نفس الصنف لهذه البطاقة ويعود عند إعادة الصرف (تعديل).
  final double credit;
  final String unit;
}

/// نقص في صنف واحد (بعد جمع كل الأقسام التي تأخذ منه).
class OilStockShortage {
  const OilStockShortage({
    required this.labels,
    required this.productName,
    required this.available,
    required this.needed,
    required this.unit,
  });

  final List<String> labels;
  final String productName;
  final double available;
  final double needed;
  final String unit;

  static String _n(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

  String get text =>
      '${labels.join('، ')} — $productName: متوفر ${_n(available)} $unit، '
      'المطلوب ${_n(needed)} $unit';

  Map<String, Object?> toJson() => {
        'labels': labels,
        'product': productName,
        'available': available,
        'needed': needed,
        'unit': unit,
      };
}

/// فحص رصيد موحّد لكل أقسام البطاقة قبل البيع.
///
/// الأقسام التي تأخذ من نفس الصنف تُجمع، فلا يمر فلتران من صنف بقي منه قطعة.
class OilCardStockCheck {
  OilCardStockCheck._();

  static Future<List<OilStockShortage>> shortages(
    List<OilStockNeed> needs,
  ) async {
    final byProduct = <int, List<OilStockNeed>>{};
    for (final n in needs) {
      if (n.productId <= 0 || n.qty <= 1e-9) continue;
      byProduct.putIfAbsent(n.productId, () => []).add(n);
    }
    if (byProduct.isEmpty) return const [];

    final t = TenantContextService.instance;
    if (!t.loaded) await t.load();
    final tid = t.requireActiveTenantId();
    final db = await DatabaseHelper().database;
    final ids = byProduct.keys.toList();
    final rows = await db.query(
      'products',
      columns: ['id', 'name', 'qty', 'trackInventory'],
      where: 'tenantId = ? AND id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: [tid, ...ids],
    );
    final rowById = {for (final r in rows) (r['id'] as num).toInt(): r};

    final out = <OilStockShortage>[];
    for (final entry in byProduct.entries) {
      final row = rowById[entry.key];
      if (row != null && ((row['trackInventory'] as num?)?.toInt() ?? 1) == 0) {
        continue;
      }
      final available = (row?['qty'] as num?)?.toDouble() ?? 0;
      var needed = 0.0;
      var credit = 0.0;
      for (final n in entry.value) {
        needed += n.qty;
        credit += n.credit;
      }
      if (available + credit + 1e-9 >= needed) continue;
      out.add(
        OilStockShortage(
          labels: [for (final n in entry.value) n.label],
          productName: (row?['name'] ?? 'صنف محذوف').toString(),
          available: available + credit,
          needed: needed,
          unit: entry.value.first.unit,
        ),
      );
    }
    return out;
  }
}
