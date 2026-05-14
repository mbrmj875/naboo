import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../services/database_helper.dart';
import '../../services/tenant_context_service.dart';

const Color _kAccent = Color(0xFF1E3A5F);

class StockAnalyticsScreen extends StatefulWidget {
  const StockAnalyticsScreen({super.key});

  @override
  State<StockAnalyticsScreen> createState() => _StockAnalyticsScreenState();
}

class _StockAnalyticsScreenState extends State<StockAnalyticsScreen> {
  final _db     = DatabaseHelper();
  final _tenant = TenantContextService.instance;
  final _fmt    = NumberFormat('#,##0.000', 'ar');

  bool _loading = true;

  // إحصاءات رئيسية
  double _inventoryValue  = 0;
  int    _totalProducts   = 0;
  int    _lowStockCount   = 0;
  int    _nearExpiryCount = 0;
  int    _outOfStockCount = 0;

  // قوائم
  List<Map<String, dynamic>> _lowStockProducts   = [];
  List<Map<String, dynamic>> _nearExpiryProducts = [];
  List<Map<String, dynamic>> _topMovers          = [];
  List<Map<String, dynamic>> _categoryValues     = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final db  = await _db.database;
    final tid = _tenant.activeTenantId;

    // 1. إجمالي قيمة المخزون = qty × buyPrice
    final valRows = await db.rawQuery('''
      SELECT IFNULL(SUM(qty * buyPrice), 0) AS val,
             COUNT(*) AS total
      FROM products WHERE isActive = 1 AND tenantId = ?
    ''', [tid]);
    _inventoryValue = (valRows.first['val'] as num?)?.toDouble() ?? 0;
    _totalProducts  = (valRows.first['total'] as num?)?.toInt() ?? 0;

    // 2. منتجات نفدت (qty <= 0)
    final outRows = await db.rawQuery('''
      SELECT COUNT(*) AS c FROM products
      WHERE isActive = 1 AND tenantId = ? AND qty <= 0
    ''', [tid]);
    _outOfStockCount = (outRows.first['c'] as num?)?.toInt() ?? 0;

    // 3. منتجات بالحد الأدنى (qty <= lowStockThreshold AND qty > 0)
    final lowRows = await db.rawQuery('''
      SELECT id, name, qty, lowStockThreshold, buyPrice, sellPrice
      FROM products
      WHERE isActive = 1 AND tenantId = ?
        AND lowStockThreshold > 0
        AND qty > 0
        AND qty <= lowStockThreshold
      ORDER BY qty ASC
      LIMIT 20
    ''', [tid]);
    _lowStockProducts = List.from(lowRows);
    _lowStockCount    = _lowStockProducts.length;

    // 4. منتجات قريبة الانتهاء (خلال 60 يوم)
    final threshold60 = DateTime.now().add(const Duration(days: 60)).toIso8601String().substring(0, 10);
    final expRows = await db.rawQuery('''
      SELECT id, name, qty, expiryDate
      FROM products
      WHERE isActive = 1 AND tenantId = ?
        AND expiryDate IS NOT NULL
        AND expiryDate != ''
        AND expiryDate <= ?
        AND qty > 0
      ORDER BY expiryDate ASC
      LIMIT 20
    ''', [tid, threshold60]);
    _nearExpiryProducts = List.from(expRows);
    _nearExpiryCount    = _nearExpiryProducts.length;

    // 5. أكثر المنتجات مبيعاً (آخر 30 يوم)
    final since30 = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
    final topRows = await db.rawQuery('''
      SELECT ii.productId, ii.productName,
             SUM(ii.quantity) AS totalSold,
             SUM(ii.total)    AS totalRevenue
      FROM invoice_items ii
      JOIN invoices inv ON inv.id = ii.invoiceId
      WHERE inv.tenantId = ?
        AND inv.date >= ?
        AND inv.isReturned = 0
        AND ii.productId IS NOT NULL
      GROUP BY ii.productId
      ORDER BY totalSold DESC
      LIMIT 10
    ''', [tid, since30]);
    _topMovers = List.from(topRows);

    // 6. قيمة المخزون حسب الفئة
    final catRows = await db.rawQuery('''
      SELECT IFNULL(c.name, 'بدون فئة') AS catName,
             IFNULL(SUM(p.qty * p.buyPrice), 0) AS catValue,
             COUNT(p.id) AS catCount
      FROM products p
      LEFT JOIN categories c ON c.id = p.categoryId
      WHERE p.isActive = 1 AND p.tenantId = ?
      GROUP BY p.categoryId
      ORDER BY catValue DESC
      LIMIT 10
    ''', [tid]);
    _categoryValues = List.from(catRows);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  Color _expiryColor(String? iso) {
    if (iso == null || iso.isEmpty) return Colors.grey;
    try {
      final d = DateTime.parse(iso);
      final days = d.difference(DateTime.now()).inDays;
      if (days < 0)  return Colors.red;
      if (days < 14) return Colors.red;
      if (days < 30) return Colors.orange;
      return Colors.amber;
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(builder: (context, tp, _) {
      final isDark  = tp.isDarkMode;
      final bg      = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF2F5F9);
      final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;

      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: _kAccent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('تحليلات المخزون',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_outlined, color: Colors.white),
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      // ── الإحصاءات الرئيسية ────────────────────────────────
                      const _SectionTitle(title: 'نظرة عامة على المخزون'),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.2,
                        children: [
                          _KpiCard(
                            icon:    Icons.inventory_2_outlined,
                            label:   'قيمة المخزون',
                            value:   _fmt.format(_inventoryValue),
                            color:   _kAccent,
                            surface: surface,
                          ),
                          _KpiCard(
                            icon:    Icons.category_outlined,
                            label:   'إجمالي المنتجات',
                            value:   '$_totalProducts',
                            color:   Colors.teal,
                            surface: surface,
                          ),
                          _KpiCard(
                            icon:    Icons.warning_amber_outlined,
                            label:   'مخزون منخفض',
                            value:   '$_lowStockCount',
                            color:   Colors.orange,
                            surface: surface,
                          ),
                          _KpiCard(
                            icon:    Icons.remove_shopping_cart_outlined,
                            label:   'نفد المخزون',
                            value:   '$_outOfStockCount',
                            color:   Colors.red,
                            surface: surface,
                          ),
                        ],
                      ),

                      if (_nearExpiryCount > 0) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            border: Border.all(
                                color: Colors.red.withOpacity(0.3)),
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_busy_outlined,
                                  color: Colors.red, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '$_nearExpiryCount منتج قريب الانتهاء خلال 60 يوماً — راجع القائمة أدناه',
                                  style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ── منتجات المخزون المنخفض ─────────────────────────────
                      if (_lowStockProducts.isNotEmpty) ...[
                        _SectionTitle(
                          title: 'مخزون منخفض',
                          badge: '$_lowStockCount',
                          badgeColor: Colors.orange,
                        ),
                        const SizedBox(height: 8),
                        _TableCard(
                          surface: surface,
                          headers: const ['المنتج', 'الكمية', 'الحد الأدنى'],
                          rows: _lowStockProducts.map((p) {
                            final qty   = (p['qty'] as num?)?.toDouble() ?? 0;
                            final low   = (p['lowStockThreshold'] as num?)?.toDouble() ?? 0;
                            return [
                              p['name'] as String? ?? '',
                              _fmt.format(qty),
                              _fmt.format(low),
                            ];
                          }).toList(),
                          rowColors: _lowStockProducts.map((p) {
                            final qty  = (p['qty'] as num?)?.toDouble() ?? 0;
                            final low  = (p['lowStockThreshold'] as num?)?.toDouble() ?? 0;
                            final pct  = low > 0 ? qty / low : 1.0;
                            if (pct <= 0.25) return Colors.red.withOpacity(0.06);
                            return Colors.orange.withOpacity(0.04);
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── قريبة الانتهاء ─────────────────────────────────────
                      if (_nearExpiryProducts.isNotEmpty) ...[
                        _SectionTitle(
                          title: 'قريبة الانتهاء (60 يوم)',
                          badge: '$_nearExpiryCount',
                          badgeColor: Colors.red,
                        ),
                        const SizedBox(height: 8),
                        _TableCard(
                          surface: surface,
                          headers: const ['المنتج', 'الكمية', 'تاريخ الانتهاء'],
                          rows: _nearExpiryProducts.map((p) => [
                            p['name'] as String? ?? '',
                            _fmt.format((p['qty'] as num?)?.toDouble() ?? 0),
                            _formatDate(p['expiryDate'] as String?),
                          ]).toList(),
                          rowColors: _nearExpiryProducts
                              .map((p) => _expiryColor(p['expiryDate'] as String?).withOpacity(0.06))
                              .toList(),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── الأكثر مبيعاً (30 يوم) ────────────────────────────
                      if (_topMovers.isNotEmpty) ...[
                        const _SectionTitle(title: 'الأكثر مبيعاً — آخر 30 يوم'),
                        const SizedBox(height: 8),
                        _TableCard(
                          surface: surface,
                          headers: const ['المنتج', 'الكمية المباعة', 'الإيرادات'],
                          rows: _topMovers.map((p) => [
                            p['productName'] as String? ?? '',
                            _fmt.format((p['totalSold'] as num?)?.toDouble() ?? 0),
                            _fmt.format((p['totalRevenue'] as num?)?.toDouble() ?? 0),
                          ]).toList(),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── قيمة المخزون حسب الفئة ────────────────────────────
                      if (_categoryValues.isNotEmpty) ...[
                        const _SectionTitle(title: 'قيمة المخزون حسب الفئة'),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: surface,
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Column(
                            children: _categoryValues.map((cat) {
                              final val   = (cat['catValue'] as num?)?.toDouble() ?? 0;
                              final pct   = _inventoryValue > 0
                                  ? (val / _inventoryValue).clamp(0.0, 1.0)
                                  : 0.0;
                              final count = (cat['catCount'] as num?)?.toInt() ?? 0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            cat['catName'] as String? ?? '—',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        Text('$count منتج',
                                            style: const TextStyle(
                                                fontSize: 11, color: Colors.grey)),
                                        const SizedBox(width: 12),
                                        Text(_fmt.format(val),
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    LinearProgressIndicator(
                                      value: pct,
                                      backgroundColor: Colors.grey.shade100,
                                      color: _kAccent,
                                      minHeight: 5,
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      );
    });
  }
}

// ── مكونات مساعدة ──────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.badge, this.badgeColor});
  final String title;
  final String? badge;
  final Color?  badgeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: _kAccent)),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: (badgeColor ?? Colors.grey).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(badge!,
                style: TextStyle(
                    color: badgeColor ?? Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.surface,
  });
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  final Color    surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.zero,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.zero,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(label,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.surface,
    required this.headers,
    required this.rows,
    this.rowColors,
  });
  final Color                  surface;
  final List<String>           headers;
  final List<List<String>>     rows;
  final List<Color?>?          rowColors;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        children: [
          // رأس الجدول
          Container(
            color: _kAccent.withOpacity(0.06),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: headers
                  .map((h) => Expanded(
                        child: Text(h,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _kAccent)),
                      ))
                  .toList(),
            ),
          ),
          ...rows.asMap().entries.map((entry) {
            final i    = entry.key;
            final row  = entry.value;
            final bg   = rowColors != null && i < rowColors!.length
                ? rowColors![i]
                : null;
            return Container(
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                    top: BorderSide(color: Colors.grey.shade100)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: row
                    .map((cell) => Expanded(
                          child: Text(cell,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
              ),
            );
          }),
        ],
      ),
    );
  }
}
