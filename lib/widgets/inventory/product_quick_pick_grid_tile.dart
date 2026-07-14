import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../theme/sale_brand.dart';
import '../../utils/iraqi_currency_format.dart';

/// ألوان نصوص بطاقة المنتج في الشبكة — واضحة في الوضع الداكن والفاتح (بدون كحلي على خلفية داكنة).
class ProductQuickPickColors {
  ProductQuickPickColors._({
    required this.textPrimary,
    required this.textSecondary,
    required this.price,
    required this.border,
    required this.cardFill,
    required this.iconMuted,
  });

  final Color textPrimary;
  final Color textSecondary;
  final Color price;
  final Color border;
  final Color cardFill;
  final Color iconMuted;

  factory ProductQuickPickColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return ProductQuickPickColors._(
        textPrimary: Colors.white,
        textSecondary: Colors.white.withValues(alpha: 0.72),
        price: AppColors.accentGold,
        border: AppColors.accentGold.withValues(alpha: 0.22),
        cardFill: Colors.white.withValues(alpha: 0.04),
        iconMuted: Colors.white.withValues(alpha: 0.45),
      );
    }
    return ProductQuickPickColors._(
      textPrimary: const Color(0xFF0F172A),
      textSecondary: const Color(0xFF64748B),
      price: AppColors.accentGold,
      border: AppColors.borderLight,
      cardFill: Colors.white,
      iconMuted: const Color(0xFF94A3B8),
    );
  }
}

String productQuickPickStockLine(Map<String, dynamic> p) {
  if (((p['isService'] as num?)?.toInt() ?? 0) == 1) {
    return 'خدمة';
  }
  final track = ((p['trackInventory'] as num?)?.toInt() ?? 1) != 0;
  if (!track) return 'غير متتبّع';
  final q = p['qty'];
  if (q == null) return '—';
  final n = (q as num).toDouble();
  if (n.abs() < 1e-9) return '0';
  if ((n % 1).abs() < 1e-6) {
    return IraqiCurrencyFormat.formatInt(n);
  }
  return IraqiCurrencyFormat.formatDecimal2(n);
}

/// صورة المنتج في بطاقة الشبكة (ملف محلي أو رابط).
class ProductQuickPickThumb extends StatelessWidget {
  const ProductQuickPickThumb({
    super.key,
    required this.product,
    required this.colors,
  });

  final Map<String, dynamic> product;
  final ProductQuickPickColors colors;

  static const BorderRadius _topRadius = BorderRadius.vertical(
    top: Radius.circular(12),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final path = (product['imagePath'] as String?)?.trim();
    final urlRaw = (product['imageUrl'] as String?)?.trim();

    Widget placeholder() {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF1F5F9),
          borderRadius: _topRadius,
          border: Border.all(
            color: colors.border.withValues(alpha: 0.65),
          ),
        ),
        child: Center(
          child: Icon(
            Icons.inventory_2_outlined,
            size: 34,
            color: colors.iconMuted,
          ),
        ),
      );
    }

    if (!kIsWeb &&
        path != null &&
        path.isNotEmpty &&
        File(path).existsSync()) {
      return ClipRRect(
        borderRadius: _topRadius,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => placeholder(),
        ),
      );
    }

    final net = urlRaw != null &&
            urlRaw.isNotEmpty &&
            (urlRaw.startsWith('http://') || urlRaw.startsWith('https://'))
        ? urlRaw
        : null;
    if (net != null) {
      return ClipRRect(
        borderRadius: _topRadius,
        child: Image.network(
          net,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return ColoredBox(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : const Color(0xFFF1F5F9),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.iconMuted,
                  ),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => placeholder(),
        ),
      );
    }

    return placeholder();
  }
}

/// بطاقة مربعة لاختيار منتج — نفس بنية شاشة إدارة المنتجات (صورة + نص).
class ProductQuickPickGridTile extends StatefulWidget {
  const ProductQuickPickGridTile({
    super.key,
    required this.product,
    required this.onTap,
    this.showAddBadge = true,
  });

  final Map<String, dynamic> product;
  final VoidCallback onTap;
  final bool showAddBadge;

  @override
  State<ProductQuickPickGridTile> createState() => _ProductQuickPickGridTileState();
}

class _ProductQuickPickGridTileState extends State<ProductQuickPickGridTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = ProductQuickPickColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.product;

    final track = ((p['trackInventory'] as num?)?.toInt() ?? 1) != 0;
    final isService = ((p['isService'] as num?)?.toInt() ?? 0) == 1;
    final rawQty = (p['qty'] as num?)?.toDouble() ?? 0;
    final outOfStock = track && rawQty <= 0;
    final stock = productQuickPickStockLine(p);

    final sellN = (p['sell'] as num?)?.toDouble() ??
        (p['sellPrice'] as num?)?.toDouble() ??
        0;
    final name = (p['name'] as String?)?.trim().isNotEmpty == true
        ? '${p['name']}'.trim()
        : 'منتج';
    final priceLabel = IraqiCurrencyFormat.formatIqd(sellN);

    final code = (p['productCode'] as String?)?.trim() ?? '';
    final barcode = (p['barcode'] as String?)?.trim() ?? '';
    final meta = [if (code.isNotEmpty) code, if (barcode.isNotEmpty) barcode]
        .join(' · ');

    final stockColor = !track
        ? colors.textSecondary
        : rawQty <= 0
            ? const Color(0xFFEF4444)
            : (rawQty < 5
                ? const Color(0xFFF59E0B)
                : colors.textSecondary);

    final cardFill = isDark
        ? Colors.white.withValues(alpha: outOfStock ? 0.02 : 0.04)
        : (outOfStock
            ? Colors.white.withValues(alpha: 0.55)
            : Colors.white);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          hoverColor: isDark
              ? Colors.white10
              : Colors.black.withValues(alpha: 0.04),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: _hover
                  ? (isDark
                      ? cardFill.withValues(alpha: 0.08)
                      : const Color(0xFFF8FAFF))
                  : cardFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hover
                    ? AppColors.accentGold
                    : colors.border,
              ),
              boxShadow: isDark
                  ? (_hover
                      ? [
                          BoxShadow(
                            color: SaleBrandColors.gold.withValues(alpha: 0.25),
                            blurRadius: 14,
                          ),
                        ]
                      : null)
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _hover ? 0.08 : 0.04,
                        ),
                        blurRadius: _hover ? 10 : 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ProductQuickPickThumb(
                        product: p,
                        colors: colors,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 6,
                          end: 6,
                          top: 6,
                          bottom: 6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                                height: 1.05,
                              ),
                            ),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                            const SizedBox(height: 3),
                            Text(
                              priceLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: colors.price,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              isService ? 'خدمة فنية' : 'المتوفر: $stock',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: isService
                                    ? colors.textSecondary
                                    : stockColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.showAddBadge)
                  PositionedDirectional(
                    top: 6,
                    end: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark
                            ? SaleBrandColors.navy.withValues(alpha: 0.85)
                            : Colors.white.withValues(alpha: 0.95),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.accentGold.withValues(alpha: 0.65),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: AppColors.accentGold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

int productQuickPickGridCrossAxisCount(double width) {
  if (width < 380) return 2;
  if (width < 560) return 3;
  if (width < 720) return 4;
  return 5;
}
