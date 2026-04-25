import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../providers/parked_sales_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import 'add_invoice_screen.dart';

final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'ar');

/// تلخيص سريع من حمولة JSON دون إعادة بناء الفاتورة كاملة.
class _ParkedSummary {
  final String title;
  final String customer;
  final int lineCount;
  final double totalApprox;

  _ParkedSummary({
    required this.title,
    required this.customer,
    required this.lineCount,
    required this.totalApprox,
  });

  static _ParkedSummary fromRow(Map<String, dynamic> row) {
    final title = (row['title'] as String?)?.trim() ?? 'بدون عنوان';
    var customer = '';
    var lineCount = 0;
    var total = 0.0;
    try {
      final m = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      customer = (m['customer'] as String?)?.trim() ?? '';
      final lines = m['lines'] as List<dynamic>? ?? [];
      lineCount = lines.length;
      final sub = lines.fold<double>(0, (s, e) {
        final x = e as Map<String, dynamic>;
        final q = (x['quantity'] as num?)?.toInt() ?? 0;
        final p = (x['unitPrice'] as num?)?.toDouble() ?? 0;
        return s + q * p;
      });
      final discPct = double.tryParse(m['discountPercent']?.toString() ?? '0') ?? 0;
      final tax = double.tryParse(m['tax']?.toString() ?? '0') ?? 0;
      final discVal = sub * (discPct.clamp(0, 100) / 100);
      total = sub - discVal + tax;
    } catch (_) {}
    return _ParkedSummary(
      title: title,
      customer: customer,
      lineCount: lineCount,
      totalApprox: total,
    );
  }
}

class ParkedSalesScreen extends StatefulWidget {
  const ParkedSalesScreen({super.key});

  @override
  State<ParkedSalesScreen> createState() => _ParkedSalesScreenState();
}

class _ParkedSalesScreenState extends State<ParkedSalesScreen> {
  final _db = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ParkedSalesProvider>().refresh();
    });
  }

  Future<void> _delete(int id, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
          title: const Text('حذف الفاتورة المعلّقة؟'),
          content: Text('سيتم حذف «$label» نهائياً من الجهاز.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _db.deleteParkedSale(id);
    CloudSyncService.instance.scheduleSyncSoon();
    if (!mounted) return;
    await context.read<ParkedSalesProvider>().refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم الحذف')),
    );
  }

  void _resume(int id) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AddInvoiceScreen(resumeParkedSaleId: id),
      ),
    ).then((_) {
      if (mounted) context.read<ParkedSalesProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text('فواتير معلّقة مؤقتاً'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => context.read<ParkedSalesProvider>().refresh(),
            ),
          ],
        ),
        body: Consumer<ParkedSalesProvider>(
          builder: (_, prov, __) {
            if (prov.rows.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'لا توجد فواتير معلّقة',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'من شاشة البيع اضغط «تعليق الفاتورة» لحفظ العمل الحالي وخدمة عميل آخر.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).hintColor, height: 1.4),
                      ),
                    ],
                  ),
                ),
              );
            }
            return RefreshIndicator(
              color: AppColors.accent,
              onRefresh: () => prov.refresh(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: prov.rows.length,
                itemBuilder: (_, i) {
                  final row = prov.rows[i];
                  final id = row['id'] as int;
                  final sum = _ParkedSummary.fromRow(row);
                  final updated = DateTime.tryParse(row['updatedAt'] as String? ?? '') ?? DateTime.now();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppShape.none,
                      side: BorderSide(
                        color: isDark ? AppColors.borderDark : AppColors.borderLight,
                      ),
                    ),
                    color: isDark ? AppColors.cardDark : AppColors.cardLight,
                    child: InkWell(
                      onTap: () => _resume(id),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.12),
                              ),
                              child: Icon(Icons.pause_circle_filled_rounded, color: AppColors.accent, size: 28),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    sum.title,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  if (sum.customer.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(sum.customer, style: TextStyle(color: Theme.of(context).hintColor)),
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${sum.lineCount} صنف · ≈ ${sum.totalApprox.toStringAsFixed(0)} د.ع',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    'آخر تحديث: ${_dateFmt.format(updated)}',
                                    style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                IconButton(
                                  tooltip: 'متابعة البيع',
                                  icon: const Icon(Icons.play_arrow_rounded, color: AppColors.primary),
                                  onPressed: () => _resume(id),
                                ),
                                IconButton(
                                  tooltip: 'حذف',
                                  icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade600),
                                  onPressed: () => _delete(id, sum.title),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
