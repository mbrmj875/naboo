import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/shift_provider.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../theme/app_corner_style.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/screen_layout.dart';
import '../widgets/oil_change_royal_card.dart';
import '../../../home/home_kpi_repository.dart';
import '../../../home/specs/home_dashboard_spec.dart';

/// لوحة رئيسية لنشاط غيار الزيت — CTA ذهبي + بطاقات KPI زجاجية.
class OilChangeHomeDashboard extends StatefulWidget {
  const OilChangeHomeDashboard({
    super.key,
    required this.spec,
    required this.onAction,
  });

  final HomeDashboardSpec spec;
  final void Function(HomeDashboardAction action) onAction;

  @override
  State<OilChangeHomeDashboard> createState() => _OilChangeHomeDashboardState();
}

class _OilChangeHomeDashboardState extends State<OilChangeHomeDashboard> {
  Timer? _poll;
  bool _loadingKpi = true;
  HomeKpiSnapshot _kpi = HomeKpiSnapshot.empty;

  @override
  void initState() {
    super.initState();
    CloudSyncService.instance.remoteImportGeneration.addListener(
      _onRemoteImport,
    );
    unawaited(_loadKpi());
    _poll = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) unawaited(_loadKpi());
    });
  }

  @override
  void dispose() {
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onRemoteImport,
    );
    _poll?.cancel();
    super.dispose();
  }

  void _onRemoteImport() {
    HomeKpiRepository.instance.invalidate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadKpi(force: true));
    });
  }

  Future<void> _loadKpi({bool force = false}) async {
    if (!mounted) return;
    final shift = context.read<ShiftProvider>().activeShift;
    final shiftId = (shift?['id'] as num?)?.toInt();
    final snap = await HomeKpiRepository.instance.load(
      openShiftId: shiftId,
      force: force,
      includeAllProductShortages:
          widget.spec.profile == HomeDashboardProfile.oilChangeHybrid,
    );
    if (!mounted) return;
    setState(() {
      _kpi = snap;
      _loadingKpi = false;
    });
  }

  String _subtitleFor(HomeDashboardAction action) {
    if (_loadingKpi) return '…';
    switch (action.id) {
      case 'oil_garage':
        return '${_kpi.activeCarsInGarage}';
      case 'oil_stock':
        final n = _kpi.stockShortages;
        return n > 0 ? 'نواقص: $n' : 'لا نواقص';
      case 'oil_cash':
        if (!_kpi.hasOpenShift) return 'لا وردية مفتوحة';
        final cash = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(_kpi.todayShiftCashInFils),
        );
        if (_kpi.todayShiftCashInFils <= 0 &&
            _kpi.todayShiftSalesFils > 0) {
          final sales = IraqiCurrencyFormat.formatIqd(
            IqdMoney.fromFils(_kpi.todayShiftSalesFils),
          );
          return '$cash · مبيعات $sales';
        }
        return cash;
      default:
        return action.subtitle;
    }
  }

  bool _alertFor(HomeDashboardAction action) {
    if (_loadingKpi) return false;
    if (action.id == 'oil_stock') return _kpi.stockShortages > 0;
    if (action.id == 'oil_garage') return _kpi.activeCarsInGarage > 0;
    return action.showAlert;
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.appCorners;
    final sl = ScreenLayout.of(context);
    final gold = OilChangeRoyalCard.gold;
    final primary = widget.spec.primaryCta;
    final tiles = widget.spec.secondaryTiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (primary != null) ...[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => widget.onAction(primary),
              borderRadius: ac.md,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: sl.isHandsetForLayout ? 16 : 20,
                  vertical: sl.isHandsetForLayout ? 16 : 18,
                ),
                decoration: BoxDecoration(
                  borderRadius: ac.md,
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [
                      gold.withValues(alpha: 0.92),
                      gold.withValues(alpha: 0.72),
                    ],
                  ),
                  border: Border.all(
                    color: gold.withValues(alpha: 0.95),
                    width: 1.75,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: AppGlass.goldGlow,
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      primary.icon,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            primary.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            primary.subtitle,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, c) {
            final twoCol = c.maxWidth >= 520 && tiles.length >= 2;
            if (!twoCol) {
              return Column(
                children: [
                  for (int i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _OilKpiTile(
                      action: tiles[i],
                      subtitle: _subtitleFor(tiles[i]),
                      showAlert: _alertFor(tiles[i]),
                      onTap: () => widget.onAction(tiles[i]),
                    ),
                  ],
                ],
              );
            }
            final rows = <Widget>[];
            for (var i = 0; i < tiles.length; i += 2) {
              if (i > 0) rows.add(const SizedBox(height: 8));
              final left = tiles[i];
              final right = i + 1 < tiles.length ? tiles[i + 1] : null;
              rows.add(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _OilKpiTile(
                        action: left,
                        subtitle: _subtitleFor(left),
                        showAlert: _alertFor(left),
                        onTap: () => widget.onAction(left),
                      ),
                    ),
                    if (right != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: _OilKpiTile(
                          action: right,
                          subtitle: _subtitleFor(right),
                          showAlert: _alertFor(right),
                          onTap: () => widget.onAction(right),
                        ),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
              );
            }
            return Column(children: rows);
          },
        ),
      ],
    );
  }
}

class _OilKpiTile extends StatelessWidget {
  const _OilKpiTile({
    required this.action,
    required this.subtitle,
    required this.onTap,
    this.showAlert = false,
  });

  final HomeDashboardAction action;
  final String subtitle;
  final VoidCallback onTap;
  final bool showAlert;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = action.accentColor;
    final alert = showAlert && action.id == 'oil_stock';

    final tileBg = alert
        ? cs.errorContainer.withValues(alpha: isDark ? 0.35 : 0.45)
        : (isDark
            ? AppGlass.surfaceTintStrong
            : cs.surface.withValues(alpha: 0.95));

    return Material(
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: ac.md,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.accentGold.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: AppColors.accentGold.withValues(alpha: 0.9),
                    child: const SizedBox(width: 3.5),
                  ),
                Expanded(
                  child: ColoredBox(
                    color: tileBg,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        12,
                        12,
                        12,
                        12,
                      ),
                      child: Row(
                        children: [
                          Icon(action.icon, color: AppColors.accentGold, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  action.id == 'oil_garage'
                                      ? '${action.title}: $subtitle'
                                      : action.title,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: cs.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  action.id == 'oil_garage'
                                      ? (action.hint ?? '')
                                      : subtitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: action.id == 'oil_garage'
                                        ? cs.onSurfaceVariant
                                        : (alert
                                            ? cs.error
                                            : cs.onSurfaceVariant),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}
