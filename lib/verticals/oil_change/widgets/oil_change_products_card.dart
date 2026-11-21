import 'package:flutter/material.dart';

import '../models/oil_change_product_line.dart';
import '../../../theme/sale_brand.dart';
import 'oil_change_form_theme.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/barcode_input_launcher.dart';
import 'oil_change_royal_card.dart';

/// بطاقة منتجات إضافية لبطاقة غيار الزيت — مسح باركود + قائمة الأصناف.
class OilChangeProductsCard extends StatelessWidget {
  const OilChangeProductsCard({
    super.key,
    required this.lines,
    required this.busy,
    required this.onScanBarcode,
    this.onAddProduct,
    required this.onQuantityChanged,
    required this.onRemoveLine,
    this.bare = false,
  });

  final List<OilChangeProductLine> lines;
  final bool busy;
  final VoidCallback onScanBarcode;
  /// شاشات عريضة (≥700dp): فتح نافذة البحث اليدوي.
  final VoidCallback? onAddProduct;
  final void Function(int index, int quantity) onQuantityChanged;
  final void Function(int index) onRemoveLine;
  /// داخل قسم اختياري قابل للطي — بدون إطار البطاقة الخارجي.
  final bool bare;

  static const Color _gold = SaleBrandColors.gold;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = ScreenLayout.of(context);
    final showScan = layout.showSaleBarcodeShortcut ||
        BarcodeInputLauncher.useCamera(context);
    final showAddProduct =
        onAddProduct != null && !layout.showSaleBarcodeShortcut;

    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'أسطر إضافية من المخزون — امسح الباركود أو استخدم قارئ الحاسوب.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: OilChangeFormTheme.secondaryText(context),
                ),
                textAlign: TextAlign.start,
              ),
            ),
            if (showAddProduct) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'إضافة منتج من المخزون',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _gold.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: busy ? null : onAddProduct,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.playlist_add_rounded,
                          color: _gold,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (showScan) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'مسح باركود لإضافة صنف',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _gold.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: busy ? null : onScanBarcode,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.qr_code_scanner_rounded,
                          color: _gold,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(12),
              border: BorderDirectional(
                end: BorderSide(
                  color: _gold.withValues(alpha: 0.45),
                  width: 2,
                ),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 40,
                  color: _gold.withValues(alpha: 0.85),
                ),
                const SizedBox(height: 10),
                Text(
                  showAddProduct
                      ? 'لا توجد أصناف بعد.\nاضغط «إضافة منتج» أو مرّر الباركود من قارئ الحاسوب.'
                      : showScan
                          ? 'لا توجد أصناف بعد.\nامسح الباركود أعلاه لإضافة منتج من المخزون.'
                          : 'لا توجد أصناف بعد.\nوجّه المؤشر هنا ومرّر الباركود من قارئ الحاسوب.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: OilChangeFormTheme.secondaryText(context),
                  ),
                ),
              ],
            ),
          )
        else
          ...lines.asMap().entries.map((entry) {
            final i = entry.key;
            final line = entry.value;
            return Container(
              margin: EdgeInsets.only(bottom: i < lines.length - 1 ? 8 : 0),
              padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.productName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: OilChangeFormTheme.emphasisText(context),
                          ),
                          textAlign: TextAlign.start,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${line.quantity} × ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(line.priceFils))}',
                          style: TextStyle(
                            fontSize: 12,
                            color: OilChangeFormTheme.secondaryText(context),
                          ),
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    IraqiCurrencyFormat.formatIqd(
                      IqdMoney.fromFils(line.totalFils),
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: OilChangeFormTheme.accentText(context),
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  const SizedBox(width: 4),
                  Column(
                    children: [
                      IconButton(
                        tooltip: 'زيادة الكمية',
                        visualDensity: VisualDensity.compact,
                        onPressed: busy
                            ? null
                            : () => onQuantityChanged(i, line.quantity + 1),
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                      ),
                      IconButton(
                        tooltip: 'تقليل الكمية',
                        visualDensity: VisualDensity.compact,
                        onPressed: busy || line.quantity <= 1
                            ? null
                            : () => onQuantityChanged(i, line.quantity - 1),
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        visualDensity: VisualDensity.compact,
                        onPressed: busy ? null : () => onRemoveLine(i),
                        icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );

    if (bare) return inner;

    return OilChangeRoyalCard.section(
      context: context,
      title: 'المنتجات',
      icon: Icons.inventory_2_outlined,
      children: inner.children,
    );
  }
}
