import '../../../models/invoice.dart';
import '../models/oil_change_filter_kind.dart';
import '../models/oil_change_service_item.dart';
import '../../../services/product_repository.dart';
import '../../../services/service_orders_repository.dart';
import '../../../utils/invoice_validation.dart';
import '../../../utils/iqd_money.dart';
import '../utils/oil_change_filter_format.dart';
import '../utils/oil_card_labor.dart';
import '../utils/oil_change_log_format.dart';
import 'oil_change_services_repository.dart';
import 'oil_change_settings.dart';
import '../utils/oil_order_has_oil.dart';

/// بناء بنود فاتورة بيع من بطاقة غيار زيت (بدون خصم مخزون مكرر للزيت/الهيدروليك المُصرف مسبقاً).
class OilChangeInvoiceBuilder {
  OilChangeInvoiceBuilder._();

  /// يطابق [kInvoiceBalanceTolerance] (0.01 د.ع ≈ 10 فلس) حتى لا تُقبل بنود
  /// ثم يرفضها [validateInvoiceBalance] بعد الصرف.
  static final int _lineMatchTolFils = IqdMoney.toFils(kInvoiceBalanceTolerance);

  /// إجمالي البطاقة المتفق عليه (مصدر الحقيقة للفاتورة).
  static int orderTotalFils(Map<String, dynamic> order) {
    final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
    if (agreedF != null && agreedF > 0) return agreedF;
    final estF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    return estF > 0 ? estF : 0;
  }

  static bool _oilCustomerProvided(Map<String, dynamic> order) =>
      ((order['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;

  /// اسم سطر التسوية حين يكون إجمالي البطاقة أكبر من مجموع البنود.
  static const adjustmentLineName = 'تسوية إجمالي البطاقة';

  /// خصم الفاتورة اللازم حين يكون مجموع البنود أكبر من إجمالي البطاقة
  /// (المبلغ المتفق عليه أقل). صفر إن لم يلزم.
  static int discountFilsFor(Map<String, dynamic> order, List<InvoiceItem> items) {
    final targetF = orderTotalFils(order);
    if (targetF <= 0) return 0;
    final diff = itemsTotalFils(items) - targetF;
    return diff > _lineMatchTolFils ? diff : 0;
  }

  /// بنود الفاتورة.
  ///
  /// البنود تبقى بأرقام منتجاتها دائماً حتى يُخصم المخزون. إن كان إجمالي
  /// البطاقة أكبر من مجموع البنود يُضاف سطر تسوية بالفرق. إن كان أقل:
  /// - [keepLinesWithDiscount] = true: تبقى البنود ويطبّق المستدعي الفرق خصماً
  ///   على الفاتورة عبر [discountFilsFor].
  /// - false (مسار شاشة البيع التي لا تقبل خصماً ممرَّراً): سطر واحد بإجمالي
  ///   البطاقة كما كان.
  static Future<List<InvoiceItem>> buildItems(
    Map<String, dynamic> order, {
    bool keepLinesWithDiscount = false,
  }) async {
    final targetF = orderTotalFils(order);
    final items = <InvoiceItem>[];
    items.addAll(await _oilMaterialItems(order));
    items.addAll(await _hydraulicItems(order, prefix: 'hydraulic'));
    items.addAll(await _hydraulicItems(order, prefix: 'powerHydraulic'));
    items.addAll(_filterItems(order));
    items.addAll(await _serviceItems(order));
    items.addAll(await _retailProductItems(order));

    var lines = items
        .where(
          (i) => IqdMoney.toFils(i.total) > 0 || IqdMoney.toFils(i.price) > 0,
        )
        .toList();

    if (targetF <= 0) return lines;

    var sumF = itemsTotalFils(lines);
    if ((sumF - targetF).abs() <= _lineMatchTolFils) return lines;

    // إزالة سطر زيت المحل إن كان «زيت العميل» — شائع سبب مضاعفة الإجمالي.
    if (_oilCustomerProvided(order)) {
      lines = lines.where((i) => !_looksLikeOilMaterialLine(i)).toList();
      sumF = itemsTotalFils(lines);
      if ((sumF - targetF).abs() <= _lineMatchTolFils) return lines;
    }

    if (sumF < targetF) {
      // البطاقة أعلى من البنود (أجرة أو إضافة يدوية): سطر تسوية بالفرق،
      // وتبقى بنود المنتجات بأرقامها فيُخصم مخزونها.
      return [
        ...lines,
        _filsLine(name: adjustmentLineName, fils: targetF - sumF),
      ];
    }

    if (keepLinesWithDiscount) return lines;

    // لا تزال البنود لا تطابق البطاقة: سطر واحد بإجمالي البطاقة (يتجنب 9000 بدل 4500).
    return [
      _filsLine(
        name: _consolidatedLineName(order),
        fils: targetF,
      ),
    ];
  }

  static bool _looksLikeOilMaterialLine(InvoiceItem i) {
    final n = i.productName.toLowerCase();
    return n.contains('لتر') ||
        n.contains('زيت') ||
        i.enteredQtyResolved > 1.0 + 1e-9;
  }

  static String _consolidatedLineName(Map<String, dynamic> order) {
    final car = (order['deviceName'] ?? '').toString().trim();
    final plate = (order['deviceSerial'] ?? '').toString().trim();
    final bits = <String>[oilCardWorkLabel(order)];
    if (car.isNotEmpty) bits.add(car);
    if (plate.isNotEmpty) bits.add(plate);
    return bits.join(' — ');
  }

  static int itemsTotalFils(List<InvoiceItem> items) {
    var sum = 0;
    for (final i in items) {
      sum += IqdMoney.toFils(i.total);
    }
    return sum;
  }

  static InvoiceItem _qtyLine({
    required String name,
    required double unitPriceDinar,
    required double enteredQty,
    int? productId,
  }) {
    final entered = enteredQty <= 0 ? 1.0 : enteredQty;
    final total = unitPriceDinar * entered;
    return InvoiceItem(
      productName: name,
      quantity: entered,
      price: unitPriceDinar,
      total: total,
      productId: productId,
      enteredQty: entered,
      baseQty: entered,
    );
  }

  static InvoiceItem _filsLine({
    required String name,
    required int fils,
    int? productId,
  }) {
    final price = IqdMoney.fromFils(fils);
    return InvoiceItem(
      productName: name,
      quantity: 1,
      price: price,
      total: price,
      productId: productId,
      enteredQty: 1,
      baseQty: 1,
    );
  }

  static Future<List<InvoiceItem>> _oilMaterialItems(
    Map<String, dynamic> order,
  ) async {
    if (_oilCustomerProvided(order)) return const [];

    final liters = _oilLitersFromOrder(order);
    if (liters <= 1e-9) return const [];

    final catalogFils = (order['oilSellPerLiterFils'] as num?)?.toInt() ?? 0;
    if (catalogFils > 0) {
      final oilType = (order['oilType'] ?? '').toString().trim();
      final vis = (order['oilViscosity'] ?? '').toString().trim();
      final label = [
        if (oilType.isNotEmpty) oilType,
        if (vis.isNotEmpty) vis,
      ].join(' · ');
      final sellD = IqdMoney.fromFils(catalogFils);
      return [
        _qtyLine(
          name: label.isEmpty
              ? 'زيت (${liters.toStringAsFixed(1)} لتر)'
              : '$label (${liters.toStringAsFixed(1)} لتر)',
          unitPriceDinar: sellD,
          enteredQty: liters,
        ),
      ];
    }

    final pid = (order['oilProductId'] as num?)?.toInt();
    if (pid == null || pid <= 0) return const [];

    final row = await ProductRepository().getProductById(pid);
    if (row == null) return const [];
    final name = (row['name'] ?? '').toString().trim();
    final sell = (row['sellPrice'] as num?)?.toDouble() ?? 0;
    return [
      _qtyLine(
        name: name.isEmpty ? 'زيت' : '$name (${liters.toStringAsFixed(1)} لتر)',
        unitPriceDinar: sell,
        enteredQty: liters,
      ),
    ];
  }

  static Future<List<InvoiceItem>> _hydraulicItems(
    Map<String, dynamic> order, {
    required String prefix,
  }) async {
    final fallbackLabel =
        prefix == 'powerHydraulic' ? 'هيدروليك الباور' : 'هيدروليك الكير';
    if (((order['${prefix}CustomerProvided'] as num?)?.toInt() ?? 0) != 0) {
      // من العميل: لا ثمن صنف، فقط أجرة اليد المحفوظة في البطاقة.
      final labor = (order['${prefix}LaborFils'] as num?)?.toInt() ?? 0;
      if (labor <= 0) return const [];
      return [_filsLine(name: 'أجرة $fallbackLabel (من العميل)', fils: labor)];
    }
    final liters = _hydraulicLitersFromOrder(order, prefix);
    if (liters <= 1e-9) return const [];

    // هيدروليك الكتالوج (بلا ربط مخزون): سعر اللتر محفوظ في البطاقة.
    final catalogFils =
        (order['${prefix}SellPerLiterFils'] as num?)?.toInt() ?? 0;
    final pid = (order['${prefix}ProductId'] as num?)?.toInt();
    if ((pid == null || pid <= 0) && catalogFils > 0) {
      final type = (order['${prefix}Type'] ?? '').toString().trim();
      final grade = (order['${prefix}Grade'] ?? '').toString().trim();
      final label = [
        if (type.isNotEmpty) type,
        if (grade.isNotEmpty) grade,
      ].join(' · ');
      return [
        _qtyLine(
          name:
              '${label.isEmpty ? fallbackLabel : label} (${liters.toStringAsFixed(1)} لتر)',
          unitPriceDinar: IqdMoney.fromFils(catalogFils),
          enteredQty: liters,
        ),
      ];
    }
    if (pid == null || pid <= 0) return const [];

    final row = await ProductRepository().getProductById(pid);
    if (row == null) return const [];
    final name = (row['name'] ?? '').toString().trim();
    final sell = (row['sellPrice'] as num?)?.toDouble() ?? 0;

    return [
      _qtyLine(
        name: name.isEmpty
            ? fallbackLabel
            : '$name (${liters.toStringAsFixed(1)} لتر)',
        unitPriceDinar: sell,
        enteredQty: liters,
      ),
    ];
  }

  static Future<List<InvoiceItem>> _retailProductItems(
    Map<String, dynamic> order,
  ) async {
    final gid = (order['global_id'] ?? '').toString().trim();
    if (gid.isEmpty) return const [];

    final rows =
        await ServiceOrdersRepository.instance.getItemsForOrderGlobalId(gid);
    final out = <InvoiceItem>[];
    for (final row in rows) {
      final name = (row['productName'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      final q = (row['quantity'] as num?)?.toInt() ?? 1;
      final priceF = (row['priceFils'] as num?)?.toInt() ?? 0;
      if (priceF <= 0) continue;
      final pid = (row['productId'] as num?)?.toInt();
      final qty = q <= 0 ? 1 : q;
      final unit = IqdMoney.fromFils(priceF);
      out.add(
        InvoiceItem(
          productName: name,
          quantity: qty.toDouble(),
          price: unit,
          total: unit * qty,
          productId: pid,
          enteredQty: qty.toDouble(),
          baseQty: qty.toDouble(),
        ),
      );
    }
    return out;
  }

  static List<InvoiceItem> _filterItems(Map<String, dynamic> order) {
    final out = <InvoiceItem>[];
    final labelByCode = <String, String>{
      for (final k in OilChangeFilterKind.builtins) k.code: k.label,
    };
    for (final line in oilFilterLinesDataFromRow(order)) {
      final kindLabel = (line.label?.trim().isNotEmpty == true)
          ? line.label!.trim()
          : (labelByCode[line.code] ?? 'فلتر');
      if (line.customerProvided) {
        if (line.laborFils > 0) {
          out.add(
            _filsLine(
              name: 'أجرة تركيب $kindLabel (من العميل)',
              fils: line.laborFils,
            ),
          );
        }
        continue;
      }
      if (line.priceFils <= 0) continue;
      final text = oilFilterLineLabel(
        kindLabel: kindLabel,
        name: line.name,
        priceFils: line.priceFils,
      );
      final name = text ??
          (line.name.isEmpty
              ? '$kindLabel — ${line.priceFils}'
              : '$kindLabel: ${line.name}');
      if (line.qty > 1) {
        out.add(
          _qtyLine(
            name: line.name.isEmpty ? kindLabel : '$kindLabel: ${line.name}',
            unitPriceDinar: IqdMoney.fromFils(line.priceFils) / line.qty,
            enteredQty: line.qty.toDouble(),
          ),
        );
      } else {
        out.add(
          // بلا productId: المخزون صُرف بسند البطاقة، لا بالفاتورة.
          _filsLine(name: name, fils: line.priceFils),
        );
      }
    }
    return out;
  }

  static double _hydraulicLitersFromOrder(
    Map<String, dynamic> order,
    String prefix,
  ) {
    final used = (order['${prefix}LitersUsed'] as num?)?.toDouble() ?? 0;
    if (used > 1e-9) return used;
    return _litersFromSizeText((order['${prefix}Size'] ?? '').toString());
  }

  static double _litersFromSizeText(String raw) {
    final size = raw.trim();
    if (size.isEmpty) return 0;
    final lower = size.toLowerCase();
    final numPart =
        lower.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.');
    final v = double.tryParse(numPart);
    if (v == null || v <= 0) return 0;
    if (lower.contains('ml') && !lower.contains('l')) return v / 1000.0;
    return v;
  }

  static double _oilLitersFromOrder(Map<String, dynamic> order) {
    final fromUsed = (order['oilLitersUsed'] as num?)?.toDouble() ?? 0;
    if (fromUsed > 1e-9) return fromUsed;
    final size = (order['oilSize'] ?? '').toString().trim();
    if (size.isEmpty) return 0;
    final lower = size.toLowerCase();
    final numPart = lower.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.');
    final v = double.tryParse(numPart);
    if (v == null || v <= 0) return 0;
    if (lower.contains('ml') && !lower.contains('l')) return v / 1000.0;
    return v;
  }

  static Future<List<InvoiceItem>> _serviceItems(
    Map<String, dynamic> order,
  ) async {
    final names = parseOilRequestedServices(
      order['requestedServices']?.toString(),
    );
    final catalog = await OilChangeServicesRepository.instance.listActive();
    // البطاقات منذ الإصدار 51 تحفظ أجرة التبديل الفعلية؛ القديمة تأخذها
    // من الإعدادات كما كانت.
    final savedLabor = (order['oilLaborFils'] as num?)?.toInt();
    final baseF = savedLabor ?? await OilChangeSettings.getBaseOilChangePriceFils();

    final lines = <({String name, int fils})>[];
    if (baseF > 0) {
      lines.add((
        name: savedLabor == null
            ? 'تبديل الزيت'
            : oilLaborLineName(customerOil: _oilCustomerProvided(order)),
        fils: baseF,
      ));
    }
    for (final n in names) {
      OilChangeServiceItem? match;
      for (final s in catalog) {
        if (s.name == n) {
          match = s;
          break;
        }
      }
      if (match != null && match.priceFils > 0) {
        lines.add((name: match.name, fils: match.priceFils));
      } else if (n.trim().isNotEmpty) {
        lines.add((name: n, fils: 0));
      }
    }

    final priced = [
      for (final line in lines)
        if (line.fils > 0) line,
    ];
    if (priced.isNotEmpty) {
      return [
        for (final line in priced)
          _filsLine(name: line.name, fils: line.fils),
      ];
    }

    // لا نُكرّر إجمالي البطاقة هنا إن وُجدت مواد/فلاتر — يُعالَج في buildItems.
    final materialsF = itemsTotalFils([
      ...await _oilMaterialItems(order),
      ...await _hydraulicItems(order, prefix: 'hydraulic'),
      ...await _hydraulicItems(order, prefix: 'powerHydraulic'),
      ..._filterItems(order),
      ...await _retailProductItems(order),
    ]);
    final targetF = orderTotalFils(order);
    // الأجرة = المتفق عليه ناقص المواد والمنتجات. إن زادت المواد على المتفق
    // عليه فلا أجرة، والفرق يصير خصماً (أو سطراً واحداً في مسار شاشة البيع).
    final laborF = targetF > materialsF ? targetF - materialsF : 0;
    if (laborF > 0) {
      return [
        _filsLine(name: '${oilCardWorkLabel(order)} — خدمات', fils: laborF),
      ];
    }
    return const [];
  }
}
