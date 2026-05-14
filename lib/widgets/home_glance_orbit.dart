import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/shift_provider.dart';
import '../services/cloud_sync_service.dart';
import '../services/database_helper.dart';
import '../services/tenant_context_service.dart';
import '../utils/iraqi_currency_format.dart';
import '../utils/screen_layout.dart';

/// أهداف البطاقات المصغّرة في الرئيسية — تُمرَّر إلى [HomeScreen] للتنقّل.
enum HomeGlanceAction {
  cash,
  newSale,
  inventoryProducts,
  parkedSales,
  reportsExecutive,
  completedOrders,
}

const _kOrderPrefsKey = 'home_glance_order_v1';

const List<String> _kAllGlanceIds = [
  'cash',
  'sale',
  'orders',
  'stock',
  'parked',
  'reports',
];

/// شريط بطاقات مصغّرة (bento) — أرقام حيّة، إعادة ترتيب، واتصال بالوردية.
class HomeGlanceOrbit extends StatefulWidget {
  const HomeGlanceOrbit({super.key, required this.onAction});

  final void Function(HomeGlanceAction action) onAction;

  @override
  State<HomeGlanceOrbit> createState() => _HomeGlanceOrbitState();
}

class _HomeGlanceOrbitState extends State<HomeGlanceOrbit> {
  final DatabaseHelper _db = DatabaseHelper();
  Timer? _poll;

  List<String> _order = List<String>.from(_kAllGlanceIds);

  double _cashBalance = 0;
  int _productCount = 0;
  int _lowStockCount = 0;
  int _parkedCount = 0;
  int _completedOrdersCount = 0;
  double _completedOrdersDeltaPct = 0;
  bool _completedOrdersPositive = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    CloudSyncService.instance.remoteImportGeneration.addListener(
      _onRemoteSnapshotImported,
    );
    _bootstrap();
    // احتياطي إن فات Realtime؛ الاستيراد الفعلي يحدّث فوراً عبر [remoteImportGeneration].
    _poll = Timer.periodic(const Duration(seconds: 90), (_) => _loadStats());
  }

  void _onRemoteSnapshotImported() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadStats());
    });
  }

  Future<void> _bootstrap() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kOrderPrefsKey);
    if (raw != null && raw.isNotEmpty) {
      final parts = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final merged = <String>[];
      for (final id in parts) {
        if (_kAllGlanceIds.contains(id) && !merged.contains(id)) merged.add(id);
      }
      for (final id in _kAllGlanceIds) {
        if (!merged.contains(id)) merged.add(id);
      }
      _order = merged;
    }
    await _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final cash = await _db.getCashSummary();
      final parked = await _db.countParkedSales();
      final tid = TenantContextService.instance.activeTenantId;
      final low = await _db.getProductsForLowStockNotifications(
        tenantId: tid,
        limit: 500,
      );
      final db = await _db.database;
      final pc = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM products WHERE tenantId = ? AND isActive = 1',
        [tid],
      );
      final shiftOrders = await _db.getShiftCompletedSalesInvoicesStat();
      final n = pc.isEmpty ? 0 : (pc.first['c'] as int?) ?? 0;
      if (!mounted) return;
      setState(() {
        _cashBalance = cash['balance'] ?? 0;
        _parkedCount = parked;
        _lowStockCount = low.length;
        _productCount = n;
        _completedOrdersCount =
            (shiftOrders['salesInvoicesCount'] as num?)?.toInt() ?? 0;
        _completedOrdersDeltaPct =
            (shiftOrders['diffPercent'] as num?)?.toDouble() ?? 0;
        _completedOrdersPositive = (shiftOrders['isPositive'] as bool?) ?? true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _persistOrder() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kOrderPrefsKey, _order.join(','));
  }

  void _openReorderSheet() {
    final cs = Theme.of(context).colorScheme;
    var local = List<String>.from(_order);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final maxSheetH = MediaQuery.sizeOf(ctx).height * 0.88;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxSheetH),
              child: StatefulBuilder(
                builder: (ctx, setModal) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'ترتيب البطاقات',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'اسحب العناصر لأعلى أو لأسفل. الترتيب يُحفظ على هذا الجهاز.',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: ReorderableListView.builder(
                          itemCount: local.length,
                          onReorder: (oldI, newI) {
                            setModal(() {
                              if (newI > oldI) newI -= 1;
                              final x = local.removeAt(oldI);
                              local.insert(newI, x);
                            });
                          },
                          itemBuilder: (ctx, i) {
                            final id = local[i];
                            return ListTile(
                              key: ValueKey(id),
                              leading: Icon(
                                Icons.drag_handle_rounded,
                                color: cs.outline,
                              ),
                              title: Text(
                                _titleForId(id),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(ctx).bottom + 8,
                        ),
                        child: FilledButton(
                          onPressed: () async {
                            setState(() => _order = local);
                            await _persistOrder();
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: const Text('حفظ الترتيب'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  String _titleForId(String id) {
    switch (id) {
      case 'cash':
        return 'الصندوق';
      case 'sale':
        return 'بيع جديد';
      case 'stock':
        return 'المخزون';
      case 'orders':
        return 'الطلبات المنجزة';
      case 'parked':
        return 'معلّقات';
      case 'reports':
        return 'التقارير';
      default:
        return id;
    }
  }

  @override
  void dispose() {
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onRemoteSnapshotImported,
    );
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        // 2026-05 (Pilot 1-هـ): توزيع البطاقات صار يعتمد على DeviceVariant
        // بدل breakpoints رقمية. صف واحد في tabletLG+ (≥840dp)، عمودان في
        // phoneSM/tabletSM (360-839dp)، وعمود واحد في phoneXS (<360dp).
        final variant = context.screenLayout.layoutVariant;
        final useSingleRow =
            variant.index >= DeviceVariant.tabletLG.index;
        final useTwoColumnWrap = !useSingleRow &&
            variant != DeviceVariant.phoneXS;
        final cellGap = w < 400 ? 8.0 : 10.0;
        // ارتفاع موحّد للبطاقات حتى لا تختلف بطاقة عن أخرى بسبب طول النص/الشارة.
        // (خصوصاً "الطلبات المنجزة" التي قد تضيف شارة + سطر نص أطول).
        final cardH = (w < 420 ? 108.0 : 114.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'لمحة المربّع',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: w < 360 ? 14 : 15,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إعادة ترتيب البطاقات',
                  onPressed: _openReorderSheet,
                  icon: Icon(Icons.swap_vert_rounded, color: cs.primary),
                ),
                IconButton(
                  tooltip: 'تحديث الأرقام',
                  onPressed: () {
                    setState(() => _loading = true);
                    _loadStats();
                  },
                  icon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            SizedBox(height: w < 400 ? 8 : 10),
            if (_loading)
              const LinearProgressIndicator(minHeight: 3)
            else
              const SizedBox(height: 3),
            SizedBox(height: w < 400 ? 8 : 10),
            if (useSingleRow)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _order.length; i++) ...[
                    if (i > 0) SizedBox(width: cellGap),
                    Expanded(
                      child: SizedBox(
                        height: cardH,
                        child: _cardFor(_order[i], cs),
                      ),
                    ),
                  ],
                ],
              )
            else if (useTwoColumnWrap)
              Wrap(
                spacing: cellGap,
                runSpacing: cellGap,
                alignment: WrapAlignment.end,
                children: _order.map((id) {
                  final colW = (w - cellGap) / 2;
                  return SizedBox(
                    width: colW.clamp(120.0, w),
                    height: cardH,
                    child: _cardFor(id, cs),
                  );
                }).toList(),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _order.length; i++) ...[
                    if (i > 0) SizedBox(height: cellGap),
                    SizedBox(
                      height: cardH,
                      child: _cardFor(_order[i], cs),
                    ),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _cardFor(String id, ColorScheme cs) {
    switch (id) {
      case 'cash':
        return _GlanceCard(
          accent: const Color(0xFF059669),
          icon: Icons.payments_rounded,
          title: 'الصندوق',
          subtitle: IraqiCurrencyFormat.formatIqd(_cashBalance),
          hint: 'رصيد مجمّع في السجل',
          badge: Consumer<ShiftProvider>(
            builder: (ctx, shift, _) {
              if (!shift.hasOpenShift) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'وردية',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF16A34A),
                  ),
                ),
              );
            },
          ),
          onTap: () => widget.onAction(HomeGlanceAction.cash),
        );
      case 'sale':
        return _GlanceCard(
          accent: const Color(0xFF2563EB),
          icon: Icons.add_shopping_cart_rounded,
          title: 'بيع جديد',
          subtitle: 'فاتورة سريعة',
          hint: 'اختصار للصندوق والبيع',
          onTap: () => widget.onAction(HomeGlanceAction.newSale),
        );
      case 'stock':
        return _GlanceCard(
          accent: const Color(0xFFD97706),
          icon: Icons.inventory_2_rounded,
          title: 'المخزون',
          subtitle: '$_productCount صنفاً نشطاً',
          hint: _lowStockCount > 0
              ? 'تنبيه: $_lowStockCount بمخزون منخفض'
              : 'لا تنبيهات مخزون',
          alertDot: _lowStockCount > 0,
          onTap: () => widget.onAction(HomeGlanceAction.inventoryProducts),
        );
      case 'orders':
        final pct = _completedOrdersDeltaPct.abs().toStringAsFixed(1);
        final arrow = _completedOrdersPositive
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded;
        final chColor = _completedOrdersPositive
            ? const Color(0xFF16A34A)
            : const Color(0xFFDC2626);
        return _GlanceCard(
          accent: const Color(0xFF1D4ED8),
          icon: Icons.shopping_cart_checkout_rounded,
          title: 'الطلبات المنجزة',
          subtitle: '$_completedOrdersCount طلب',
          hint: 'مكسب الوردية السابقة',
          badge: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: chColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(4),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(arrow, size: 10, color: chColor),
                  const SizedBox(width: 2),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: chColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          onTap: () => widget.onAction(HomeGlanceAction.completedOrders),
        );
      case 'parked':
        return _GlanceCard(
          accent: const Color(0xFF7C3AED),
          icon: Icons.pause_circle_filled_rounded,
          title: 'معلّقات',
          subtitle: '$_parkedCount فاتورة',
          hint: 'مؤقتاً في الانتظار',
          alertDot: _parkedCount > 0,
          onTap: () => widget.onAction(HomeGlanceAction.parkedSales),
        );
      case 'reports':
        return _GlanceCard(
          accent: const Color(0xFF0D9488),
          icon: Icons.insights_rounded,
          title: 'التقارير',
          subtitle: 'لوحة تنفيذية',
          hint: 'مؤشرات الفترة',
          onTap: () => widget.onAction(HomeGlanceAction.reportsExecutive),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _GlanceCard extends StatelessWidget {
  const _GlanceCard({
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.onTap,
    this.badge,
    this.alertDot = false,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final String hint;
  final VoidCallback onTap;
  final Widget? badge;
  final bool alertDot;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // بطاقة هادئة بسطح موحّد + شريط جانبي رفيع باللون المميّز بدل التدرّجات
    // المتنافسة، مع ظلّ خفيف يلائم الوضعين الفاتح والداكن.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: cs.surface,
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.55),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
                blurRadius: isDark ? 8 : 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            children: [
              // شريط جانبي رفيع يحمل اللون المميّز للبطاقة (RTL: على اليمين).
              PositionedDirectional(
                start: 0,
                top: 10,
                bottom: 10,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadiusDirectional.horizontal(
                      end: Radius.circular(3),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 12, 10),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final compact = c.maxHeight.isFinite && c.maxHeight < 110;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: accent.withValues(
                                  alpha: isDark ? 0.18 : 0.10,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: accent, size: 19),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Wrap(
                                    alignment: WrapAlignment.end,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 2,
                                    children: [
                                      if (alertDot)
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFEF4444),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 180,
                                        ),
                                        child: Text(
                                          title,
                                          textAlign: TextAlign.right,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.tajawal(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                      ),
                                      if (badge != null) badge!,
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    textAlign: TextAlign.right,
                                    maxLines: compact ? 1 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                      color: cs.onSurface,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 4 : 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Text(
                              hint,
                              textAlign: TextAlign.right,
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.25,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
