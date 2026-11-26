import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/database_helper.dart';
import '../../services/product_repository.dart';
import '../../services/stock/stock_metrics.dart';
import '../../services/tenant_context_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/design_tokens.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../utils/stock_qty_format.dart';
import '../../verticals/oil_change/widgets/oil_change_form_theme.dart';

/// «تحليلات المخزون» (ع-13، المرحلة 6): كل الأرقام من [StockMetrics]، فتتفق
/// مع الإشعارات وتقرير المنتجات.
class StockAnalyticsScreen extends StatefulWidget {
  const StockAnalyticsScreen({super.key});

  @override
  State<StockAnalyticsScreen> createState() => _StockAnalyticsScreenState();
}

class _Row {
  const _Row(this.cells, {this.color, this.sortKey = 0, this.id, this.value});
  final List<String> cells;
  final Color? color;
  final double sortKey;
  final int? id;
  final double? value;
}

class _StockAnalyticsScreenState extends State<StockAnalyticsScreen> {
  static const _stagnantDaysKey = 'inv.analytics.stagnant_days';

  final _db = DatabaseHelper();
  final _tenant = TenantContextService.instance;

  bool _loading = true;
  int _stagnantDays = 60;

  double _shopValue = 0;
  double _storeValue = 0;
  int _products = 0;
  int _low = 0;
  int _out = 0;

  List<_Row> _lowRows = const [];
  List<_Row> _expiryRows = const [];
  List<_Row> _moverRows = const [];
  List<_Row> _stagnantRows = const [];
  List<_Row> _orderRows = const [];
  List<_Row> _thresholdRows = const [];
  List<({String name, double value, int count})> _categories = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _q(num v) => StockQtyFormat.format(v);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await SharedPreferences.getInstance();
      _stagnantDays = p.getInt(_stagnantDaysKey) ?? 60;
    } catch (_) {}
    final db = await _db.database;
    final tid = _tenant.activeTenantId;

    final v = await StockMetrics.value(db, tid);
    final c = await StockMetrics.counts(db, tid);

    final lowRows = await db.rawQuery(
      '''
      SELECT id, name, qty, IFNULL(store_qty, 0) AS store_qty,
             lowStockThreshold, ${StockMetrics.total} AS total
      FROM products
      WHERE tenantId = ? AND ${StockMetrics.trackedWhere}
        AND ${StockMetrics.outOrLowWhere}
      ORDER BY total ASC, name COLLATE NOCASE
      LIMIT 200
      ''',
      [tid],
    );

    final exp60 = DateTime.now()
        .add(const Duration(days: 60))
        .toIso8601String()
        .substring(0, 10);
    final expRows = await db.rawQuery(
      '''
      SELECT name, ${StockMetrics.total} AS total, expiryDate FROM products
      WHERE tenantId = ? AND ${StockMetrics.trackedWhere}
        AND IFNULL(expiryDate, '') <> '' AND expiryDate <= ?
        AND ${StockMetrics.total} > 0
      ORDER BY expiryDate ASC
      LIMIT 100
      ''',
      [tid, exp60],
    );

    final movers = await StockMetrics.topMovers(
      db,
      tid,
      since: DateTime.now().subtract(const Duration(days: 30)),
    );

    // الراكد: لم يخرج منه شيء منذ [_stagnantDays] يوماً (من آخر خروج).
    final lastExit = await StockMetrics.lastExitByProduct(db, tid);
    final usage = await StockMetrics.usage(db, tid);
    final all = await db.rawQuery(
      '''
      SELECT id, name, qty, IFNULL(store_qty, 0) AS store_qty, buyPrice,
             lowStockThreshold, createdAt
      FROM products
      WHERE tenantId = ? AND ${StockMetrics.trackedWhere}
      ''',
      [tid],
    );
    final now = DateTime.now();
    final stagnant = <_Row>[];
    final order = <_Row>[];
    final thresholds = <_Row>[];
    for (final r in all) {
      final id = (r['id'] as num).toInt();
      final name = (r['name'] ?? '').toString();
      final shop = (r['qty'] as num?)?.toDouble() ?? 0;
      final store = (r['store_qty'] as num?)?.toDouble() ?? 0;
      final total = shop + store;
      final used = usage[id] ?? 0;
      final created =
          DateTime.tryParse((r['createdAt'] ?? '').toString()) ?? now;
      final last = lastExit[id];
      final idle = now.difference(last ?? created).inDays;
      if (total > 0 && idle >= _stagnantDays) {
        final value = total * ((r['buyPrice'] as num?)?.toDouble() ?? 0);
        stagnant.add(
          _Row([
            name,
            _q(total),
            last == null ? 'لم يخرج' : '$idle يوم',
            IraqiCurrencyFormat.formatInt(value),
          ], sortKey: value),
        );
      }
      final sug = StockMetrics.suggestedOrder(
        used30: used,
        shop: shop,
        store: store,
      );
      if (sug > 0) {
        order.add(_Row([name, _q(used), _q(total), _q(sug)], sortKey: sug));
      }
      final current = (r['lowStockThreshold'] as num?)?.toDouble() ?? 0;
      final suggested = StockMetrics.suggestedThreshold(used);
      if (suggested > 0 && (suggested - current).abs() >= 1) {
        thresholds.add(
          _Row(
            [name, _q(used), _q(current), _q(suggested)],
            sortKey: used,
            id: id,
            value: suggested,
          ),
        );
      }
    }
    int byKey(_Row a, _Row b) => b.sortKey.compareTo(a.sortKey);
    stagnant.sort(byKey);
    order.sort(byKey);
    thresholds.sort(byKey);

    final cat = await db.rawQuery(
      '''
      SELECT IFNULL(c.name, 'بدون فئة') AS catName,
             IFNULL(SUM((MAX(IFNULL(p.qty, 0), 0) + MAX(IFNULL(p.store_qty, 0), 0))
                        * IFNULL(p.buyPrice, 0)), 0) AS catValue,
             COUNT(p.id) AS catCount
      FROM products p
      LEFT JOIN categories c ON c.id = p.categoryId
      WHERE p.tenantId = ? AND p.isActive = 1
        AND IFNULL(p.trackInventory, 1) = 1 AND IFNULL(p.isService, 0) = 0
      GROUP BY p.categoryId
      ORDER BY catValue DESC
      LIMIT 10
      ''',
      [tid],
    );

    if (!mounted) return;
    setState(() {
      _shopValue = v.shop;
      _storeValue = v.store;
      _products = v.products;
      _low = c.low;
      _out = c.out;
      _lowRows = [
        for (final r in lowRows)
          _Row(
            [
              (r['name'] ?? '').toString(),
              _q((r['qty'] as num?) ?? 0),
              _q((r['store_qty'] as num?) ?? 0),
              _q((r['lowStockThreshold'] as num?) ?? 0),
            ],
            color: ((r['total'] as num?) ?? 0) <= 0
                ? AppSemanticColors.danger
                : AppSemanticColors.warning,
          ),
      ];
      _expiryRows = [
        for (final r in expRows)
          _Row([
            (r['name'] ?? '').toString(),
            _q((r['total'] as num?) ?? 0),
            _formatDate(r['expiryDate']?.toString()),
          ]),
      ];
      _moverRows = [
        for (final m in movers) _Row([m.name, _q(m.out)]),
      ];
      _stagnantRows = stagnant.take(50).toList();
      _orderRows = order.take(50).toList();
      _thresholdRows = thresholds.take(50).toList();
      _categories = [
        for (final r in cat)
          (
            name: (r['catName'] ?? '—').toString(),
            value: (r['catValue'] as num?)?.toDouble() ?? 0,
            count: (r['catCount'] as num?)?.toInt() ?? 0,
          ),
      ];
      _loading = false;
    });
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  /// قبول الحد المقترح بضغطة (ق-13).
  Future<void> _acceptThreshold(_Row r) async {
    if (r.id == null || r.value == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اعتماد الحد المقترح'),
        content: Text('حد «${r.cells.first}» الأدنى يصير ${_q(r.value!)}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ProductRepository().updateLowStockThreshold(r.id!, r.value!);
    await _load();
  }

  Future<void> _editStagnantDays() async {
    final ctrl = TextEditingController(text: '$_stagnantDays');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الراكد بعد كم يوم بلا خروج؟'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: OilChangeFormTheme.field(
            context: ctx,
            labelText: 'عدد الأيام',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (v == null || v < 1) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_stagnantDaysKey, v);
    } catch (_) {}
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _shopValue + _storeValue;
    String compact(double v) =>
        IraqiCurrencyFormat.formatCompactWarehouseValue(v);
    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: OilChangeFormTheme.appBar(
            context: context,
            title: 'تحليلات المخزون',
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_outlined),
                onPressed: _load,
                tooltip: 'تحديث',
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.xl * 2,
                    ),
                    children: [
                      _Kpis(
                        items: [
                          ('قيمة المخزون', compact(total), null),
                          (
                            'المحل / المخزن',
                            '${compact(_shopValue)} / ${compact(_storeValue)}',
                            null,
                          ),
                          ('أصناف متتبَّعة', '$_products', null),
                          ('ناقص', '$_low', AppSemanticColors.warning),
                          ('نفد', '$_out', AppSemanticColors.danger),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'القيمة = الرصيد الموجب × متوسط الكلفة. الناقص والنافد '
                        'بالمحل والمخزن معاً، كما في الإشعارات.',
                        style: TextStyle(
                          fontSize: 12,
                          color: OilChangeFormTheme.secondaryText(context),
                        ),
                      ),
                      _Section(
                        title: 'ناقص ونافد',
                        badge: '${_low + _out}',
                        headers: const ['الصنف', 'المحل', 'المخزن', 'الحد'],
                        rows: _lowRows,
                      ),
                      _Section(
                        title: 'الأكثر خروجاً — آخر 30 يوم',
                        subtitle: 'البيع والبطاقات والبيع المباشر',
                        headers: const ['الصنف', 'الخارج'],
                        rows: _moverRows,
                      ),
                      _Section(
                        title: 'اقتراح الطلب (14 يوم)',
                        subtitle: 'من استهلاك 30 يوماً، بعد طرح المحل والمخزن',
                        headers: const [
                          'الصنف',
                          'استهلاك 30',
                          'الرصيد',
                          'اطلب',
                        ],
                        rows: _orderRows,
                      ),
                      _Section(
                        title: 'حد أدنى مقترح',
                        subtitle:
                            'يكفي عشرة أيام من استهلاك آخر 30 يوماً. '
                            'اضغط السطر لاعتماده.',
                        headers: const [
                          'الصنف',
                          'استهلاك 30',
                          'الحالي',
                          'المقترح',
                        ],
                        rows: _thresholdRows,
                        onTap: _acceptThreshold,
                      ),
                      _Section(
                        title: 'الراكد',
                        subtitle: 'لم يخرج منه شيء منذ $_stagnantDays يوماً',
                        headers: const [
                          'الصنف',
                          'الرصيد',
                          'آخر خروج',
                          'القيمة',
                        ],
                        rows: _stagnantRows,
                        action: TextButton(
                          onPressed: _editStagnantDays,
                          child: const Text('تغيير المدة'),
                        ),
                      ),
                      _Section(
                        title: 'قريبة الانتهاء (60 يوم)',
                        headers: const ['الصنف', 'الرصيد', 'الانتهاء'],
                        rows: _expiryRows,
                      ),
                      if (_categories.isNotEmpty)
                        _CategoryBars(categories: _categories, total: total),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.items});
  final List<(String, String, Color?)> items;

  @override
  Widget build(BuildContext context) {
    final gold = OilChangeFormTheme.goldOf(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (label, value, color) in items)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 150),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: OilChangeFormTheme.fieldContainerDecoration(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: color ?? OilChangeFormTheme.emphasisText(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.headers,
    required this.rows,
    this.subtitle,
    this.badge,
    this.action,
    this.onTap,
  });

  final ValueChanged<_Row>? onTap;
  final String title;
  final String? subtitle;
  final String? badge;
  final List<String> headers;
  final List<_Row> rows;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final gold = OilChangeFormTheme.goldOf(context);
    final head = TextStyle(
      color: gold,
      fontWeight: FontWeight.w800,
      fontSize: 12,
    );
    final text = OilChangeFormTheme.emphasisText(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: OilChangeFormTheme.isDark(context)
                        ? gold
                        : OilChangeFormTheme.navyOf(context),
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(badge!, style: head),
              ],
              const Spacer(),
              if (action != null) action!,
            ],
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: OilChangeFormTheme.secondaryText(context),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color:
                  Theme.of(context).cardTheme.color ??
                  Theme.of(context).cardColor,
              borderRadius: OilChangeFormTheme.radiusOf(context),
              border: Border.all(color: gold.withValues(alpha: 0.35)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      for (var i = 0; i < headers.length; i++)
                        Expanded(
                          flex: i == 0 ? 3 : 2,
                          child: Text(headers[i], style: head),
                        ),
                    ],
                  ),
                ),
                Container(height: 1, color: gold.withValues(alpha: 0.5)),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'لا شيء',
                      style: TextStyle(
                        color: OilChangeFormTheme.secondaryText(context),
                      ),
                    ),
                  ),
                for (var r = 0; r < rows.length; r++) ...[
                  if (r > 0)
                    Divider(height: 1, color: gold.withValues(alpha: 0.12)),
                  InkWell(
                    onTap: onTap == null ? null : () => onTap!(rows[r]),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          for (var i = 0; i < rows[r].cells.length; i++)
                            Expanded(
                              flex: i == 0 ? 3 : 2,
                              child: Text(
                                rows[r].cells[i],
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: i == 0
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: i == 0
                                      ? text
                                      : (rows[r].color ?? text),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.categories, required this.total});
  final List<({String name, double value, int count})> categories;
  final double total;

  @override
  Widget build(BuildContext context) {
    final gold = OilChangeFormTheme.goldOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: OilChangeFormTheme.fieldContainerDecoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'قيمة المخزون حسب الفئة',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: OilChangeFormTheme.isDark(context)
                    ? gold
                    : OilChangeFormTheme.navyOf(context),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final c in categories) ...[
              Row(
                children: [
                  Expanded(child: Text(c.name)),
                  Text(
                    '${c.count} صنف  ',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: OilChangeFormTheme.secondaryText(context),
                    ),
                  ),
                  Text(
                    IraqiCurrencyFormat.formatInt(c.value),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ClipRRect(
                borderRadius: OilChangeFormTheme.radiusOf(context),
                child: LinearProgressIndicator(
                  value: total > 0 ? (c.value / total).clamp(0.0, 1.0) : 0,
                  minHeight: 5,
                  color: gold,
                  backgroundColor: gold.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
