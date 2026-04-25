import 'package:flutter/material.dart';

import '../../services/product_repository.dart';
import '../../theme/app_corner_style.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final int productId;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final ProductRepository _repo = ProductRepository();

  late final Future<_ProductDetailVm?> _future;
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _future.then((vm) {
      if (!mounted || vm == null) return;
      setState(() {
        _pinned = (vm.product['isPinned'] as num?)?.toInt() == 1;
      });
    });
  }

  Future<_ProductDetailVm?> _load() async {
    final base = await _repo.getProductDetailsById(widget.productId);
    if (base == null) return null;
    final batches = await _repo.getRecentProductBatches(widget.productId, limit: 20);
    final wh = await _repo.getWarehouseStockForProduct(widget.productId);
    final sales = await _repo.getRecentProductSales(widget.productId, limit: 20);
    return _ProductDetailVm(
      product: base,
      batches: batches,
      warehouses: wh,
      sales: sales,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ac = context.appCorners;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          title: const Text(
            'تفاصيل المنتج',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              tooltip: _pinned ? 'إلغاء التثبيت من الرئيسية' : 'تثبيت في الرئيسية',
              icon: Icon(
                _pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              onPressed: () async {
                await _repo.setProductPinned(widget.productId, !_pinned);
                if (!mounted) return;
                setState(() => _pinned = !_pinned);
              },
            ),
          ],
        ),
        body: FutureBuilder<_ProductDetailVm?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final vm = snap.data;
            if (vm == null) {
              return const Center(child: Text('تعذر تحميل المنتج'));
            }
            final p = vm.product;

            final name = (p['name']?.toString() ?? '').trim();
            final status = (p['status']?.toString() ?? '').trim();
            final isLow = status == 'low';
            final statusLabel = isLow ? 'مخزون منخفض' : 'في المخزون';
            final statusColor = isLow ? cs.error : const Color(0xFF16A34A);
            final barcode = (p['barcode']?.toString() ?? '').trim();
            final code = (p['productCode']?.toString() ?? '').trim();

            double dnum(Object? v) => (v as num?)?.toDouble() ?? 0.0;
            final qty = dnum(p['qty']);
            final sell = dnum(p['sellPrice']);
            final buy = dnum(p['buyPrice']);
            final minSell = dnum(p['minSellPrice']);

            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: ac.md,
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name.isEmpty ? '—' : name,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.12),
                                    borderRadius: ac.sm,
                                    border: Border.all(
                                      color: statusColor.withValues(alpha: 0.20),
                                    ),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                _MetaChip(
                                  icon: Icons.qr_code_rounded,
                                  label: barcode.isEmpty ? '—' : barcode,
                                ),
                                _MetaChip(
                                  icon: Icons.tag_rounded,
                                  label: code.isEmpty ? '—' : code,
                                ),
                                _MetaChip(
                                  icon: Icons.numbers_rounded,
                                  label: '#${(p['id'] as num).toInt()}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'ملخص',
                  child: Column(
                    children: [
                      _kv('الكمية المتاحة', qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)),
                      _kv('سعر البيع', '${sell.toStringAsFixed(0)} د.ع'),
                      _kv('الحد الأدنى للبيع', '${minSell.toStringAsFixed(0)} د.ع'),
                      _kv('سعر الشراء', '${buy.toStringAsFixed(0)} د.ع'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'مخزون المخازن',
                  subtitle: vm.warehouses.isEmpty ? 'لا توجد بيانات مخازن' : null,
                  child: vm.warehouses.isEmpty
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            for (final w in vm.warehouses)
                              _kv(
                                (w['warehouseName']?.toString() ?? 'مخزن').trim(),
                                ((w['qty'] as num?)?.toDouble() ?? 0)
                                    .toStringAsFixed(0),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'دفعات (Batches) — آخر 20',
                  subtitle: vm.batches.isEmpty ? 'لا توجد دفعات مسجلة' : null,
                  child: vm.batches.isEmpty
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            for (final b in vm.batches)
                              _kv(
                                (b['batchNumber']?.toString() ?? '').trim().isEmpty
                                    ? 'دفعة'
                                    : (b['batchNumber']?.toString() ?? '').trim(),
                                '${((b['qty'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} × '
                                '${((b['unitCost'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'آخر مبيعات/حركات',
                  subtitle: vm.sales.isEmpty ? 'لا توجد حركات بيع مؤخراً' : null,
                  child: vm.sales.isEmpty
                      ? const SizedBox.shrink()
                      : Column(
                          children: [
                            for (final s in vm.sales)
                              _kv(
                                '#${(s['invoiceId'] as num).toInt()} · ${(s['date']?.toString() ?? '').substring(0, 10)}',
                                '${((s['qty'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} × '
                                '${((s['total'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                              ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: TextStyle(
                fontSize: 12.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            v,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: ac.sm,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: ac.md,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ProductDetailVm {
  const _ProductDetailVm({
    required this.product,
    required this.batches,
    required this.warehouses,
    required this.sales,
  });
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> batches;
  final List<Map<String, dynamic>> warehouses;
  final List<Map<String, dynamic>> sales;
}

