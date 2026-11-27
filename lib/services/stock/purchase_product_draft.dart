import '../../models/new_product_extra_unit.dart';
import 'dart:convert';

import '../../models/oil_grade_pack_input.dart';
import '../../models/product_variant_kind.dart';
import '../../utils/iqd_money.dart';
import '../product_repository.dart';
import '../tenant_context_service.dart';
import 'purchase_list_repository.dart';

/// صنف جديد كتبه صاحب المحل في شاشة «إضافة منتج» من قائمة المشتريات.
///
/// لا يُنشأ المنتج حين يضغط «حفظ»: الشاشة ترجع هذه المسودة فتُحفظ مع سطر
/// القائمة، ويُنشأ المنتج منها عند «حفظ واستلام». إن حُذفت المسودة لا يبقى
/// للصنف أثر. [form] نصوص الشاشة كما كُتبت، لإعادة فتحها بما فيها.
class PurchaseProductDraft {
  PurchaseProductDraft({
    required this.kind,
    required this.form,
    this.create = const {},
    this.qty = 0,
    this.unitCost = 0,
    this.isOil = true,
    this.familyName = '',
    this.categoryName,
    this.brandName,
    this.lowStockThreshold = 0,
    this.grades = const [],
  });

  static const String kindProduct = 'product';
  static const String kindFluid = 'fluid';

  /// [kindProduct] صنف عادي، أو [kindFluid] عائلة زيت/هيدروليك جديدة.
  final String kind;

  /// نصوص حقول الشاشة وخياراتها، لإعادة فتحها كما تُركت.
  final Map<String, dynamic> form;

  /// وسائط إنشاء الصنف العادي (كما يمررها «إضافة منتج»)، بلا كمية.
  final Map<String, dynamic> create;

  /// الكمية المشتراة وسعر شراء الوحدة (للصنف العادي).
  final double qty;
  final double unitCost;

  // ── عائلة زيت/هيدروليك ──
  final bool isOil;
  final String familyName;
  final String? categoryName;
  final String? brandName;
  final double lowStockThreshold;

  /// لزوجة لكل عنصر: viscosity, qty, buy, sell, minSell, barcode, packs.
  final List<Map<String, dynamic>> grades;

  bool get isFluid => kind == kindFluid;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'form': form,
        if (!isFluid) ...{
          'create': create,
          'qty': qty,
          'unit_cost': unitCost,
        },
        if (isFluid) ...{
          'is_oil': isOil,
          'family_name': familyName,
          'category_name': categoryName,
          'brand_name': brandName,
          'low_stock': lowStockThreshold,
          'grades': grades,
        },
      };

  static PurchaseProductDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    Map<String, dynamic> map(Object? v) => v is Map
        ? v.map((k, x) => MapEntry(k.toString(), x))
        : <String, dynamic>{};
    double n(Object? v) => (v as num?)?.toDouble() ?? 0;
    return PurchaseProductDraft(
      kind: (m['kind'] ?? kindProduct).toString(),
      form: map(m['form']),
      create: map(m['create']),
      qty: n(m['qty']),
      unitCost: n(m['unit_cost']),
      isOil: m['is_oil'] != false,
      familyName: (m['family_name'] ?? '').toString(),
      categoryName: m['category_name']?.toString(),
      brandName: m['brand_name']?.toString(),
      lowStockThreshold: n(m['low_stock']),
      grades: [
        for (final g in (m['grades'] as List? ?? const []))
          if (g is Map) map(g),
      ],
    );
  }

  /// عبوات اللزوجة كما يحفظها مستودع الزيوت.
  static List<OilGradePackInput> packsOf(Map<String, dynamic> grade) => [
        for (final p in (grade['packs'] as List? ?? const []))
          if (p is Map)
            OilGradePackInput(
              unitName: (p['unit_name'] ?? '').toString(),
              unitSymbol: p['unit_symbol']?.toString(),
              factorToBase: (p['factor'] as num?)?.toDouble() ?? 1,
              barcode: p['barcode']?.toString(),
              sellPrice: (p['sell'] as num?)?.toDouble(),
              minSellPrice: (p['min_sell'] as num?)?.toDouble(),
            ),
      ];

  static Map<String, dynamic> packToJson(OilGradePackInput p) => {
        'unit_name': p.unitName,
        'unit_symbol': p.unitSymbol,
        'factor': p.factorToBase,
        'barcode': p.barcode,
        'sell': p.sellPrice,
        'min_sell': p.minSellPrice,
      };

  static Map<String, dynamic> extraUnitToJson(NewProductExtraUnit u) => {
        'unit_name': u.unitName,
        'unit_symbol': u.unitSymbol,
        'factor': u.factorToBase,
        'barcode': u.barcode,
        'sell': u.sellPrice,
        'min_sell': u.minSellPrice,
      };

  /// أسطر القائمة من المسودة: سطر للصنف، أو سطر لكل لزوجة لها كمية.
  /// كل سطر يحمل المسودة كاملة، فيُعاد فتح الشاشة منه بما كُتب.
  List<PurchaseLine> toLines() {
    final raw = jsonEncode(toJson());
    if (!isFluid) {
      final c = create;
      final bc = c['barcode']?.toString().trim();
      return [
        PurchaseLine(
          name: (c['name'] ?? '').toString().trim(),
          qty: qty,
          unitCost: unitCost,
          sellPrice: (c['sell_price'] as num?)?.toDouble(),
          barcode: bc == null || bc.isEmpty ? null : bc,
          isNew: true,
          stockBaseKind: (c['stock_base_kind'] as num?)?.toInt() ?? 0,
          draft: raw,
        ),
      ];
    }
    final fam = familyName.trim();
    return [
      for (final g in grades)
        if (((g['qty'] as num?)?.toDouble() ?? 0) > 1e-9)
          PurchaseLine(
            name: '$fam — ${(g['viscosity'] ?? '').toString().trim()}',
            qty: (g['qty'] as num).toDouble(),
            unitCost: (g['buy'] as num?)?.toDouble() ?? 0,
            sellPrice: (g['sell'] as num?)?.toDouble(),
            barcode: (g['barcode']?.toString().trim().isEmpty ?? true)
                ? null
                : g['barcode'].toString().trim(),
            isNew: true,
            familyName: fam,
            viscosity: (g['viscosity'] ?? '').toString().trim(),
            familyKind: isOil
                ? ProductVariantKind.oilFamily
                : ProductVariantKind.hydraulicFamily,
            stockBaseKind: 3,
            draft: raw,
          ),
    ];
  }

  /// ينشئ الصنف العادي برصيد صفر وبسعر شراء [unitCost]؛ الكمية تدخل بعدها
  /// بإذن الاستلام فيحسب المحرك المتوسط. يعيد رقم الصنف.
  Future<int> createProduct({required double unitCost}) async {
    final c = create;
    final repo = ProductRepository();
    String? s(String k) {
      final v = c[k]?.toString().trim();
      return v == null || v.isEmpty ? null : v;
    }

    double d(String k) => (c[k] as num?)?.toDouble() ?? 0;
    double? dn(String k) => (c[k] as num?)?.toDouble();

    int? categoryId;
    int? brandId;
    if (s('category_name') case final cat?) {
      categoryId = await repo.getOrCreateCategoryId(cat);
    }
    if (s('brand_name') case final b?) {
      brandId = await repo.getOrCreateBrandId(b);
    }
    final sell = d('sell_price');
    final discountType = s('discount_type') ?? '%';
    final discountValue = d('discount_value');
    final track = c['track_inventory'] != false;
    final extra = [
      for (final u in (c['extra_units'] as List? ?? const []))
        if (u is Map)
          NewProductExtraUnit(
            unitName: (u['unit_name'] ?? '').toString(),
            unitSymbol: u['unit_symbol']?.toString(),
            factorToBase: (u['factor'] as num?)?.toDouble() ?? 1,
            barcode: u['barcode']?.toString(),
            sellPrice: (u['sell'] as num?)?.toDouble(),
            minSellPrice: (u['min_sell'] as num?)?.toDouble(),
          ),
    ];
    return repo.insertProductComplete(
      name: s('name') ?? '',
      barcode: s('barcode'),
      categoryId: categoryId,
      brandId: brandId,
      tenantId: TenantContextService.instance.activeTenantId,
      buyPrice: IqdMoney.normalizeDinar(unitCost),
      sellPrice: IqdMoney.normalizeDinar(sell),
      minSellPrice: IqdMoney.normalizeDinar(dn('min_sell_price') ?? sell),
      qty: 0,
      lowStockThreshold: track ? d('low_stock') : 0,
      description: s('description'),
      imagePath: s('image_path'),
      internalNotes: s('internal_notes'),
      tags: s('tags'),
      supplierName: s('supplier_name'),
      taxPercent: d('tax_percent'),
      discountPercent: discountType == '%' ? discountValue : 0,
      discountAmount: discountType == '%' ? 0 : discountValue,
      trackInventory: track ? 1 : 0,
      allowNegativeStock: 0,
      supplierItemCode: s('supplier_item_code'),
      netWeightGrams: dn('net_weight_grams'),
      manufacturingDate: s('manufacturing_date'),
      expiryDate: s('expiry_date'),
      grade: s('grade'),
      expiryAlertDaysBefore: (c['expiry_alert_days'] as num?)?.toInt(),
      stockBaseKind: (c['stock_base_kind'] as num?)?.toInt() ?? 0,
      extraUnits: extra,
      warehouseId: (c['warehouse_id'] as num?)?.toInt(),
      isService: 0,
    );
  }
}
