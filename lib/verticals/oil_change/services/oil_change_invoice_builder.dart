import '../../../models/invoice.dart';
import '../models/oil_change_filter_kind.dart';
import '../models/oil_change_service_item.dart';
import '../../../services/product_repository.dart';
import '../../../services/service_orders_repository.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../utils/oil_change_filter_format.dart';
import '../utils/oil_change_log_format.dart';
import 'oil_change_services_repository.dart';
import 'oil_change_settings.dart';

/// بناء بنود فاتورة بيع من بطاقة غيار زيت (بدون خصم مخزون مكرر للزيت/الهيدروليك المُصرف مسبقاً).
class OilChangeInvoiceBuilder {
  OilChangeInvoiceBuilder._();

  /// إجمالي البطاقة المتفق عليه (مصدر الحقيقة للفاتورة).
  static int orderTotalFils(Map<String, dynamic> order) {
    final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
    if (agreedF != null && agreedF > 0) return agreedF;
    final estF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    return estF > 0 ? estF : 0;
  }

  static bool _oilCustomerProvided(Map<String, dynamic> order) =>
      ((order['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0;

  static Future<List<InvoiceItem>> buildItems(Map<String, dynamic> order) async {
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
    if ((sumF - targetF).abs() <= 500) return lines;

    // إزالة سطر زيت المحل إن كان «زيت العميل» — شائع سبب مضاعفة الإجمالي.
    if (_oilCustomerProvided(order)) {
      lines = lines.where((i) => !_looksLikeOilMaterialLine(i)).toList();
      sumF = itemsTotalFils(lines);
      if ((sumF - targetF).abs() <= 500) return lines;
    }

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
    final bits = <String>['غيار زيت'];
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
    final liters = (order['${prefix}LitersUsed'] as num?)?.toDouble() ?? 0;
    if (liters <= 1e-9) return const [];
    if (((order['${prefix}CustomerProvided'] as num?)?.toInt() ?? 0) != 0) {
      return const [];
    }

    final pid = (order['${prefix}ProductId'] as num?)?.toInt();
    if (pid == null || pid <= 0) return const [];

    final row = await ProductRepository().getProductById(pid);
    if (row == null) return const [];
    final name = (row['name'] ?? '').toString().trim();
    final sell = (row['sellPrice'] as num?)?.toDouble() ?? 0;
    final fallbackLabel =
        prefix == 'powerHydraulic' ? 'هيدروليك الباور' : 'هيدروليك الكير';

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
    for (final kind in OilChangeFilterKind.all) {
      final name = (order[kind.nameColumnKey] ?? '').toString().trim();
      final priceFils = (order[kind.priceColumnKey] as num?)?.toInt() ?? 0;
      if (priceFils <= 0) continue;
      final line = oilFilterLineLabel(
        kindLabel: kind.label,
        name: name,
        priceFils: priceFils,
      );
      out.add(
        _filsLine(
          name: line ??
              '${kind.label}: ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(priceFils))}',
          fils: priceFils,
        ),
      );
    }
    return out;
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
    final baseF = await OilChangeSettings.getBaseOilChangePriceFils();

    final lines = <({String name, int fils})>[];
    if (baseF > 0) {
      lines.add((name: 'تبديل الزيت', fils: baseF));
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
    ]);
    final targetF = orderTotalFils(order);
    final laborF = targetF > materialsF ? targetF - materialsF : targetF;
    if (laborF > 0) {
      return [_filsLine(name: 'غيار زيت — خدمات', fils: laborF)];
    }
    return const [];
  }
}
