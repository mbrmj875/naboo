import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../verticals/oil_change/models/oil_change_service_item.dart';
import '../navigation/content_navigation.dart';
import '../providers/sale_draft_provider.dart';
import '../models/invoice.dart';
import '../verticals/oil_change/services/oil_change_invoice_builder.dart';
import '../verticals/oil_change/services/oil_change_services_repository.dart';
import '../verticals/oil_change/services/oil_change_settings.dart';
import '../services/product_repository.dart';
import '../utils/iqd_money.dart';
import '../verticals/oil_change/utils/oil_change_log_format.dart';
import '../utils/stock_quantity_kind.dart';
import '../screens/invoices/add_invoice_screen.dart';

/// تحويل تذكرة صيانة / بطاقة غيار زيت إلى مسودة بيع وفتح شاشة الفاتورة.
class ServiceOrderInvoiceBridge {
  ServiceOrderInvoiceBridge._();

  static String _serviceLineName(Map<String, dynamic> order) {
    final serviceName = (order['serviceNameSnapshot'] ?? '').toString().trim();
    if (serviceName.isNotEmpty) return serviceName;

    final oil = (order['oilType'] ?? '').toString().trim();
    final base = oil.isNotEmpty ? 'غيار زيت' : 'خدمة فنية';

    final device = (order['deviceName'] ?? '').toString().trim();
    final serial = (order['deviceSerial'] ?? '').toString().trim();
    final devDetails = [
      if (device.isNotEmpty) device,
      if (serial.isNotEmpty) 'س: $serial',
    ].join(' - ');
    if (devDetails.isEmpty) return base;
    return '$base ($devDetails)';
  }

  /// يملأ [SaleDraftProvider] ويفتح [AddInvoiceScreen] إن لم تكن شاشة البيع مفتوحة.
  static Future<bool> openInvoiceFromOrder(
    BuildContext context, {
    required Map<String, dynamic> order,
    required int orderId,
    List<Map<String, dynamic>> items = const [],
  }) async {
    if (!context.mounted) return false;

    final draft = context.read<SaleDraftProvider>();

    final custName = (order['customerNameSnapshot'] ?? '').toString().trim();
    final custId = (order['customerId'] as num?)?.toInt();
    final estF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
    final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
    final advF = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;
    final serviceId = (order['serviceId'] as num?)?.toInt();

    draft.enqueueSaleMeta({
      'customerName': custName,
      'linkedCustomerId': custId,
      'linkedServiceOrderId': orderId,
    });

    final isOilChange =
        (order['orderKind'] ?? '').toString() == 'oil_change';

    if (isOilChange) {
      final invoiceItems = await OilChangeInvoiceBuilder.buildItems(order);
      for (final it in invoiceItems) {
        _enqueueDraftFromInvoiceItem(draft, it, serviceId: serviceId);
      }
    } else {
      await _enqueueOilMaterialLine(draft, order);
      await _enqueueHydraulicMaterialLine(draft, order, prefix: 'hydraulic');
      await _enqueueHydraulicMaterialLine(draft, order, prefix: 'powerHydraulic');
      final servicePriceF = agreedF ?? estF;
      final laborFils = (servicePriceF - advF).clamp(0, servicePriceF);
      _enqueueSingleServiceLine(
        draft,
        name: _serviceLineName(order),
        fils: laborFils,
        serviceId: serviceId,
      );
    }

    for (final it in items) {
      final pid = (it['productId'] as num?)?.toInt();
      if (pid == null || pid <= 0) continue;
      final name = (it['productName'] ?? '').toString().trim();
      final q = (it['quantity'] as num?)?.toInt() ?? 1;
      final pF = (it['priceFils'] as num?)?.toInt() ?? 0;
      draft.enqueueProductLine({
        'name': name.isEmpty ? 'قطعة غيار' : name,
        'sell': IqdMoney.fromFils(pF),
        'minSell': IqdMoney.fromFils(pF),
        'productId': pid,
        'trackInventory': 1,
        'allowNegativeStock': 0,
        'qty': null,
        'stockBaseKind': 0,
        'isService': 0,
        'addQuantity': q,
      });
    }

    if (!draft.isSaleScreenOpen) {
      if (!context.mounted) return false;
      await Navigator.of(context).push(
        contentMaterialRoute(
          routeId: AppContentRoutes.addInvoice,
          breadcrumbTitle: 'بيع جديد',
          builder: (_) => const AddInvoiceScreen(),
        ),
      );
    }
    return true;
  }

  static void _enqueueDraftFromInvoiceItem(
    SaleDraftProvider draft,
    InvoiceItem item, {
    int? serviceId,
  }) {
    final isService = item.productId == null &&
        item.enteredQtyResolved <= 1.0 + 1e-9 &&
        item.baseQtyResolved <= 1.0 + 1e-9;
    draft.enqueueProductLine({
      'name': item.productName,
      'sell': item.price,
      'minSell': item.price,
      'productId': item.productId ?? serviceId,
      'trackInventory': 0,
      'allowNegativeStock': 0,
      'qty': null,
      'stockBaseKind': 0,
      'isService': isService ? 1 : 0,
      'addQuantity': item.enteredQtyResolved,
    });
  }

  static void _enqueueSingleServiceLine(
    SaleDraftProvider draft, {
    required String name,
    required int fils,
    required int? serviceId,
  }) {
    final sell = IqdMoney.fromFils(fils);
    draft.enqueueProductLine({
      'name': name,
      'sell': sell,
      'minSell': sell,
      'productId': serviceId,
      'trackInventory': 0,
      'allowNegativeStock': 0,
      'qty': 0,
      'stockBaseKind': 0,
      'isService': 1,
      'addQuantity': 1,
    });
  }

  /// أسطر منفصلة: تبديل أساسي + كل خدمة إضافية. يُرجع false إن لم يُضف أي سطر.
  static Future<bool> _enqueueOilChangeServiceLines(
    SaleDraftProvider draft, {
    required Map<String, dynamic> order,
    required int? serviceId,
    required int advanceFils,
  }) async {
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

    if (lines.isEmpty) return false;

    var advanceLeft = advanceFils < 0 ? 0 : advanceFils;
    for (final line in lines) {
      var netF = line.fils;
      if (advanceLeft > 0 && netF > 0) {
        final deduct = advanceLeft < netF ? advanceLeft : netF;
        netF -= deduct;
        advanceLeft -= deduct;
      }
      _enqueueSingleServiceLine(
        draft,
        name: line.name,
        fils: netF,
        serviceId: serviceId,
      );
    }
    return true;
  }

  /// سطر مادة الزيت (المخزون مُصرف مسبقاً على البطاقة).
  static Future<int> _enqueueOilMaterialLine(
    SaleDraftProvider draft,
    Map<String, dynamic> order,
  ) async {
    final liters = (order['oilLitersUsed'] as num?)?.toDouble() ?? 0;
    if (liters <= 1e-9) return 0;

    final catalogFils = (order['oilSellPerLiterFils'] as num?)?.toInt() ?? 0;

    if (catalogFils > 0) {
      final oilType = (order['oilType'] ?? '').toString().trim();
      final vis = (order['oilViscosity'] ?? '').toString().trim();
      final label = [
        if (oilType.isNotEmpty) oilType,
        if (vis.isNotEmpty) vis,
      ].join(' · ');
      final sellD = IqdMoney.fromFils(catalogFils);
      final lineFils = IqdMoney.toFils(sellD * liters);
      draft.enqueueProductLine({
        'name': label.isEmpty
            ? 'زيت (${liters.toStringAsFixed(1)} لتر)'
            : '$label (${liters.toStringAsFixed(1)} لتر)',
        'sell': sellD,
        'minSell': sellD,
        'productId': null,
        'trackInventory': 0,
        'allowNegativeStock': 0,
        'qty': null,
        'stockBaseKind': StockBaseKind.volumeLiter,
        'isService': 0,
        'addQuantity': liters,
      });
      return lineFils;
    }

    if (((order['oilCustomerProvided'] as num?)?.toInt() ?? 0) != 0) {
      return 0;
    }

    final pid = (order['oilProductId'] as num?)?.toInt();
    if (pid == null || pid <= 0) return 0;

    final row = await ProductRepository().getProductById(pid);
    if (row == null) return 0;
    final name = (row['name'] ?? '').toString().trim();
    final sell = (row['sellPrice'] as num?)?.toDouble() ?? 0;
    final minSell = (row['minSellPrice'] as num?)?.toDouble() ?? sell;
    final lineFils = IqdMoney.toFils(sell * liters);

    draft.enqueueProductLine({
      'name': name.isEmpty ? 'زيت' : '$name (${liters.toStringAsFixed(1)} لتر)',
      'sell': sell,
      'minSell': minSell,
      'productId': pid,
      'trackInventory': 0,
      'allowNegativeStock': 0,
      'qty': null,
      'stockBaseKind': StockBaseKind.volumeLiter,
      'isService': 0,
      'addQuantity': liters,
    });
    return lineFils;
  }

  static Future<int> _enqueueHydraulicMaterialLine(
    SaleDraftProvider draft,
    Map<String, dynamic> order, {
    required String prefix,
  }) async {
    final liters = (order['${prefix}LitersUsed'] as num?)?.toDouble() ?? 0;
    if (liters <= 1e-9) return 0;
    if (((order['${prefix}CustomerProvided'] as num?)?.toInt() ?? 0) != 0) {
      return 0;
    }

    final pid = (order['${prefix}ProductId'] as num?)?.toInt();
    if (pid == null || pid <= 0) return 0;

    final row = await ProductRepository().getProductById(pid);
    if (row == null) return 0;
    final name = (row['name'] ?? '').toString().trim();
    final sell = (row['sellPrice'] as num?)?.toDouble() ?? 0;
    final minSell = (row['minSellPrice'] as num?)?.toDouble() ?? sell;
    final lineFils = IqdMoney.toFils(sell * liters);
    final fallbackLabel =
        prefix == 'powerHydraulic' ? 'هيدروليك الباور' : 'هيدروليك الكير';

    draft.enqueueProductLine({
      'name': name.isEmpty
          ? fallbackLabel
          : '$name (${liters.toStringAsFixed(1)} لتر)',
      'sell': sell,
      'minSell': minSell,
      'productId': pid,
      'trackInventory': 0,
      'allowNegativeStock': 0,
      'qty': null,
      'stockBaseKind': StockBaseKind.volumeLiter,
      'isService': 0,
      'addQuantity': liters,
    });
    return lineFils;
  }
}
