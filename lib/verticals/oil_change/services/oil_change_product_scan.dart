import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/oil_change_product_line.dart';
import '../../../providers/product_provider.dart';
import '../../../screens/inventory/add_product_screen.dart';
import '../../../utils/iqd_money.dart';

/// إضافة منتج بالباركود لبطاقة غيار الزيت (مثل شاشة البيع — مبسّط).
class OilChangeProductScan {
  OilChangeProductScan._();

  /// رسالة ثابتة عند باركود غير مسجّل (وضع المسح السريع بدون حوار).
  static const String unknownBarcodeMessage = 'الباركود غير مسجّل';

  static int _sellFilsFromProduct(Map<String, dynamic> product) {
    final sell = (product['sellPrice'] as num?)?.toDouble() ??
        (product['sell'] as num?)?.toDouble() ??
        0;
    return IqdMoney.toFils(sell);
  }

  /// إضافة من صف منتج (بحث يدوي أو اختيار من النافذة).
  static String? addFromProductMap({
    required List<OilChangeProductLine> lines,
    required Map<String, dynamic> product,
  }) {
    final pid = (product['id'] as num?)?.toInt();
    if (pid == null || pid <= 0) return 'منتج غير صالح';
    final name = (product['name'] ?? '').toString().trim();
    final display = name.isEmpty ? 'منتج' : name;
    final priceFils = _sellFilsFromProduct(product);
    mergeOrAddLine(
      lines: lines,
      productId: pid,
      productName: display,
      priceFils: priceFils,
    );
    return 'تمت إضافة: $display';
  }

  static void mergeOrAddLine({
    required List<OilChangeProductLine> lines,
    required int productId,
    required String productName,
    required int priceFils,
  }) {
    final idx = lines.indexWhere(
      (l) => l.productId == productId && l.priceFils == priceFils,
    );
    if (idx >= 0) {
      lines[idx].quantity += 1;
      return;
    }
    lines.add(
      OilChangeProductLine(
        productId: productId,
        productName: productName,
        priceFils: priceFils,
      ),
    );
  }

  static Future<String?> handleBarcode(
    BuildContext context, {
    required List<OilChangeProductLine> lines,
    required String barcode,
    bool suppressAddProductDialog = false,
  }) async {
    final code = barcode.trim();
    if (code.isEmpty) return null;

    final resolved = await context
        .read<ProductProvider>()
        .resolveProductByAnyBarcode(code);
    if (!context.mounted) return null;

    final product = resolved?['product'] as Map<String, dynamic>?;
    if (product != null) {
      return addFromProductMap(lines: lines, product: product);
    }

    if (suppressAddProductDialog) {
      return unknownBarcodeMessage;
    }

    final goToAdd = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('المنتج غير موجود'),
            content: const Text(
              'هذا الباركود غير موجود في المنتجات. هل تريد فتح شاشة إضافة منتج جديد؟',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('إضافة منتج'),
              ),
            ],
          ),
        ) ??
        false;

    if (!goToAdd || !context.mounted) return null;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AddProductScreen(
          initialBarcode: code,
          autoFillFromScan: true,
        ),
      ),
    );
    if (!context.mounted) return null;

    final afterAdd =
        await context.read<ProductProvider>().findProductByBarcode(code);
    if (afterAdd == null || !context.mounted) return null;

    final pid = (afterAdd['id'] as num?)?.toInt();
    if (pid == null || pid <= 0) return null;
    final name = (afterAdd['name'] ?? '').toString().trim();
    final display = name.isEmpty ? 'منتج جديد' : name;
    mergeOrAddLine(
      lines: lines,
      productId: pid,
      productName: display,
      priceFils: _sellFilsFromProduct(afterAdd),
    );
    return 'تمت إضافة: $display';
  }
}
