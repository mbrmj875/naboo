import 'package:flutter/material.dart';

import '../../utils/iraqi_currency_format.dart';
import '../server_notifications_repository.dart';

/// تفاصيل الملخص اليومي داخل التطبيق (المرحلة 4). الربح هنا فقط، لا على شاشة القفل.
Future<void> showDailySummarySheet(
  BuildContext context,
  int notificationId,
) async {
  final n = await ServerNotificationsRepository.fetchOne(notificationId);
  if (!context.mounted) return;
  if (n == null || n.details == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر تحميل تفاصيل الملخص. تحقق من الاتصال.'),
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: _DailySummaryBody(n),
    ),
  );
}

class _DailySummaryBody extends StatelessWidget {
  const _DailySummaryBody(this.n);
  final ServerNotification n;

  static String _iqd(dynamic fils) =>
      '${IraqiCurrencyFormat.formatInt((((fils as num?) ?? 0) / 1000).round())} د.ع';

  @override
  Widget build(BuildContext context) {
    final d = n.details!;
    final t = (d['tomorrow'] as Map?) ?? const {};
    final theme = Theme.of(context);
    Widget section(String title, List<String> lines) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final l in lines)
            Text(l, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        ],
      ),
    );
    final count = (d['invoiceCount'] as num?)?.toInt() ?? 0;
    final yCount = (d['yesterdayCount'] as num?)?.toInt() ?? 0;
    final tomorrowLines = <String>[
      if (((t['installmentsDue'] as num?) ?? 0) > 0)
        'أقساط تستحق غدا: ${t['installmentsDue']}',
      if (((t['lowStock'] as num?) ?? 0) > 0) 'أصناف ناقصة: ${t['lowStock']}',
      if (((t['expiringSoon'] as num?) ?? 0) > 0)
        'أصناف تنتهي صلاحيتها خلال أسبوع: ${t['expiringSoon']}',
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ملخص يوم ${d['ymd'] ?? ''}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            section('المبيعات', [
              '${_iqd(d['salesFils'])} في $count فاتورة',
              'أمس: ${_iqd(d['yesterdaySalesFils'])} في $yCount فاتورة',
            ]),
            section('صافي الربح', [_iqd(d['profitFils'])]),
            section('الدين والمرتجعات', [
              'بيع بالدين أو التقسيط: ${_iqd(d['debtFils'])}',
              'المرتجعات: ${_iqd(d['returnsFils'])} (${d['returnsCount'] ?? 0})',
            ]),
            section(
              'ما يحتاج انتباها غدا',
              tomorrowLines.isEmpty ? ['لا شيء يحتاج انتباها.'] : tomorrowLines,
            ),
          ],
        ),
      ),
    );
  }
}
