import 'package:flutter/material.dart';

import '../../services/business_setup_settings.dart';
import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import 'models/owner_command_center_snapshot.dart';
import 'models/owner_kpi_models.dart';
import 'models/owner_section_result.dart';
import 'models/owner_section_ttl.dart';
import 'providers/owner_command_center_provider.dart';
import 'specs/owner_dashboard_l10n_keys.dart';
import 'specs/owner_kpi_catalog.dart';
import 'specs/owner_kpi_catalog_entry.dart';
import 'utils/owner_shortcut_navigation.dart';
import 'widgets/owner_oil_kpi_stitch_tile.dart';
import 'widgets/owner_hero_kpi_card.dart';
import 'widgets/owner_hybrid_revenue_kpi_card.dart';
import 'widgets/owner_kpi_card_v3.dart';
import 'widgets/owner_kpi_card_skeleton.dart';
import 'widgets/owner_kpi_card.dart';
import 'widgets/owner_top_sellers_kpi_card.dart';
import 'widgets/owner_slow_movers_kpi_card.dart';

/// يبني بطاقات v3 من catalog + snapshot.
abstract final class OwnerDashboardCardBuilder {
  OwnerDashboardCardBuilder._();

  static OwnerSectionResult<dynamic>? sectionFor(
    OwnerKpiCatalogEntry entry,
    OwnerCommandCenterSnapshot snapshot,
  ) {
    switch (entry.sectionId) {
      case OwnerSectionIds.oilActiveCars:
        return snapshot.oilActiveCars;
      case OwnerSectionIds.oilChangesCount:
        return snapshot.oilChangesCount;
      case OwnerSectionIds.carWashCount:
        return snapshot.carWashCount;
      case OwnerSectionIds.oilStockShortages:
        return snapshot.oilStockShortages;
      case OwnerSectionIds.oilAvgTicket:
        return snapshot.oilAvgTicket;
      case OwnerSectionIds.hybridRevenueSplit:
        return snapshot.hybridRevenueSplit;
      case OwnerSectionIds.retailTopSellers:
        return snapshot.retailTopSellers;
      case OwnerSectionIds.clothingVariantShortages:
        return snapshot.clothingVariantShortages;
      case OwnerSectionIds.clothingSlowMovers:
        return snapshot.clothingSlowMovers;
      case OwnerSectionIds.sales:
        return snapshot.sales;
      case OwnerSectionIds.inventoryShortages:
        return snapshot.inventoryShortages;
      case OwnerSectionIds.debts:
        return snapshot.debts;
      case OwnerSectionIds.openShifts:
        return snapshot.openShifts;
      case OwnerSectionIds.cash:
        return snapshot.cash;
      case OwnerSectionIds.inventoryValue:
        return snapshot.inventoryValue;
      case OwnerSectionIds.installments:
        return snapshot.installments;
      default:
        return null;
    }
  }

  static IconData iconFor(String catalogId) {
    switch (catalogId) {
      case OwnerCatalogIds.oilActiveCars:
        return Icons.directions_car_filled_outlined;
      case OwnerCatalogIds.oilChangesPeriod:
        return Icons.oil_barrel_outlined;
      case OwnerCatalogIds.carWashPeriod:
        return Icons.local_car_wash_rounded;
      case OwnerCatalogIds.oilStockShortages:
        return Icons.inventory_2_outlined;
      case OwnerCatalogIds.oilAvgTicket:
        return Icons.receipt_long_outlined;
      case OwnerCatalogIds.hybridRevenueSplit:
        return Icons.pie_chart_outline;
      case OwnerCatalogIds.debtsSummary:
        return Icons.account_balance_wallet_outlined;
      case OwnerCatalogIds.openShifts:
        return Icons.people_alt_outlined;
      case OwnerCatalogIds.cashSummary:
        return Icons.account_balance_outlined;
      case OwnerCatalogIds.inventoryValue:
        return Icons.warehouse_outlined;
      case OwnerCatalogIds.retailStockShortages:
        return Icons.shelves;
      case OwnerCatalogIds.retailSalesPeriod:
        return Icons.point_of_sale_outlined;
      case OwnerCatalogIds.retailTopSellers:
        return Icons.leaderboard_outlined;
      case OwnerCatalogIds.retailDebtsSummary:
        return Icons.account_balance_wallet_outlined;
      case OwnerCatalogIds.retailOpenShifts:
        return Icons.people_alt_outlined;
      case OwnerCatalogIds.retailCashSummary:
        return Icons.account_balance_outlined;
      case OwnerCatalogIds.retailInventoryValue:
        return Icons.warehouse_outlined;
      case OwnerCatalogIds.clothingVariantShortages:
        return Icons.style_outlined;
      case OwnerCatalogIds.clothingSlowMovers:
        return Icons.hourglass_empty_outlined;
      case OwnerCatalogIds.clothingSalesPeriod:
        return Icons.point_of_sale_outlined;
      case OwnerCatalogIds.clothingTopSellers:
        return Icons.leaderboard_outlined;
      case OwnerCatalogIds.clothingDebtsSummary:
        return Icons.account_balance_wallet_outlined;
      case OwnerCatalogIds.clothingOpenShifts:
        return Icons.people_alt_outlined;
      case OwnerCatalogIds.clothingCashSummary:
        return Icons.account_balance_outlined;
      case OwnerCatalogIds.clothingInventoryValue:
        return Icons.warehouse_outlined;
      case OwnerCatalogIds.installmentsSummary:
        return Icons.calendar_month_outlined;
      default:
        return Icons.insights_outlined;
    }
  }

  static String valueForCatalogId(String catalogId, dynamic data) {
    final entry = OwnerKpiCatalog.kpiById(catalogId);
    if (entry == null) return data.toString();
    return _valueFor(entry, data);
  }

  static Widget? buildHero({
    required BuildContext context,
    required OwnerKpiCatalogEntry entry,
    required OwnerCommandCenterSnapshot snapshot,
    required OwnerCommandCenterProvider center,
  }) {
    final section = sectionFor(entry, snapshot);
    if (section == null) return null;
    final title = ownerDashboardL10n(entry.titleKey);
    final onRetry = () => center.refreshSection(entry.sectionId);

    if (entry.id == OwnerCatalogIds.hybridRevenueSplit) {
      final hybridSection = section as OwnerSectionResult<HybridRevenueKpi>?;
      if (hybridSection == null) return null;
      return OwnerHybridRevenueKpiCard(
        title: title,
        section: hybridSection,
        sectionId: entry.sectionId,
        onRetry: onRetry,
        isHero: true,
      );
    }

    if (entry.id == OwnerCatalogIds.oilActiveCars) {
      return OwnerHeroKpiCard(
        title: title,
        section: section,
        sectionId: entry.sectionId,
        icon: iconFor(entry.id),
        onRetry: onRetry,
        valueBuilder: (data) => '${(data as OilActiveCarsKpi).activeCount}',
        subtitleBuilder: (data) {
          final n = (data as OilActiveCarsKpi).activeCount;
          if (n <= 0) return 'الورشة فارغة';
          return n == 1 ? 'سيارة واحدة قيد العمل' : '$n سيارات قيد العمل';
        },
      );
    }

    if (entry.id == OwnerCatalogIds.retailStockShortages) {
      return OwnerHeroKpiCard(
        title: title,
        section: section,
        sectionId: entry.sectionId,
        icon: iconFor(entry.id),
        onRetry: onRetry,
        valueBuilder: (data) => '${(data as InventoryAlert).shortageCount}',
        subtitleBuilder: (data) {
          final n = (data as InventoryAlert).shortageCount;
          if (n <= 0) {
            return ownerDashboardL10n(
              OwnerDashboardL10nKeys.retailStockShortagesEmpty,
            );
          }
          return n == 1 ? 'صنف واحد ناقص على الرف' : '$n أصناف ناقصة';
        },
      );
    }

    if (entry.id == OwnerCatalogIds.clothingVariantShortages) {
      return OwnerHeroKpiCard(
        title: title,
        section: section,
        sectionId: entry.sectionId,
        icon: iconFor(entry.id),
        onRetry: onRetry,
        valueBuilder: (data) =>
            '${(data as ClothingVariantShortagesKpi).shortageCount}',
        subtitleBuilder: (data) {
          final n = (data as ClothingVariantShortagesKpi).shortageCount;
          if (n <= 0) {
            return ownerDashboardL10n(
              OwnerDashboardL10nKeys.clothingVariantShortagesEmpty,
            );
          }
          return n == 1 ? 'مقاس واحد ناقص' : '$n مقاسات/ألوان ناقصة';
        },
      );
    }

    if (entry.id == OwnerCatalogIds.clothingSlowMovers) {
      return OwnerHeroKpiCard(
        title: title,
        section: section,
        sectionId: entry.sectionId,
        icon: iconFor(entry.id),
        onRetry: onRetry,
        valueBuilder: (data) => '${(data as ClothingSlowMoversKpi).slowCount}',
        subtitleBuilder: (data) {
          final kpi = data as ClothingSlowMoversKpi;
          if (kpi.slowCount <= 0) {
            return ownerDashboardL10n(
              OwnerDashboardL10nKeys.clothingSlowMoversEmpty,
            );
          }
          return 'بدون مبيعات منذ ${kpi.daysThreshold} يوماً';
        },
      );
    }

    if (entry.id == OwnerCatalogIds.retailSalesPeriod ||
        entry.id == OwnerCatalogIds.clothingSalesPeriod) {
      return OwnerHeroKpiCard(
        title: title,
        section: section,
        sectionId: entry.sectionId,
        icon: iconFor(entry.id),
        onRetry: onRetry,
        valueBuilder: (data) => IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils((data as SalesKpi).salesFils),
        ),
      );
    }

    return OwnerHeroKpiCard(
      title: title,
      section: section,
      sectionId: entry.sectionId,
      icon: iconFor(entry.id),
      onRetry: onRetry,
      valueBuilder: (data) => _valueFor(entry, data),
    );
  }

  /// بطاقة KPI بأسلوب Stitch — ارتفاع ثابت.
  static Widget? buildStitchOilTile({
    required BuildContext context,
    required OwnerKpiCatalogEntry entry,
    required OwnerCommandCenterSnapshot snapshot,
    required OwnerCommandCenterProvider center,
    VoidCallback? onPurchasePdf,
    VoidCallback? onDebtReminders,
    VoidCallback? onOpenDebts,
    VoidCallback? onOpenInstallments,
  }) {
    final section = sectionFor(entry, snapshot);
    if (section == null) return null;

    final layout = switch (entry.id) {
      OwnerCatalogIds.oilActiveCars => OwnerOilKpiStitchLayout.hero,
      OwnerCatalogIds.inventoryValue => OwnerOilKpiStitchLayout.inventoryRow,
      OwnerCatalogIds.debtsSummary => OwnerOilKpiStitchLayout.inventoryRow,
      _ => OwnerOilKpiStitchLayout.compact,
    };

    return OwnerOilKpiStitchTile(
      catalogId: entry.id,
      title: ownerDashboardL10n(entry.titleKey),
      section: section,
      sectionId: entry.sectionId,
      onRetry: () => center.refreshSection(entry.sectionId),
      layout: layout,
      onTap: _onTapFor(
        context,
        entry,
        onOpenDebts: onOpenDebts,
        onOpenInstallments: onOpenInstallments,
      ),
      alertWhen: entry.id == OwnerCatalogIds.oilStockShortages
          ? (data) => (data as InventoryAlert).shortageCount > 0
          : null,
    );
  }

  static List<Widget> buildCatalogCard({
    required BuildContext context,
    required OwnerKpiCatalogEntry entry,
    required OwnerCommandCenterSnapshot snapshot,
    required OwnerCommandCenterProvider center,
    VoidCallback? onPurchasePdf,
    VoidCallback? onDebtReminders,
    VoidCallback? onOpenDebts,
    VoidCallback? onOpenInstallments,
  }) {
    if (entry.id == OwnerCatalogIds.openShifts ||
        entry.id == OwnerCatalogIds.retailOpenShifts ||
        entry.id == OwnerCatalogIds.clothingOpenShifts) {
      return _openShiftsBlock(context, snapshot, center);
    }

    if (entry.id == OwnerCatalogIds.retailTopSellers ||
        entry.id == OwnerCatalogIds.clothingTopSellers) {
      return _topSellersBlock(context, entry, snapshot, center);
    }

    if (entry.id == OwnerCatalogIds.clothingSlowMovers) {
      return _slowMoversBlock(context, entry, snapshot, center);
    }

    if (entry.id == OwnerCatalogIds.hybridRevenueSplit) {
      return _hybridRevenueBlock(context, entry, snapshot, center);
    }

    final section = sectionFor(entry, snapshot);
    if (section == null) return const [];

    final title = ownerDashboardL10n(entry.titleKey);
    final onRetry = () => center.refreshSection(entry.sectionId);
    final trailing = _trailingFor(
      context,
      entry,
      onPurchasePdf: onPurchasePdf,
      onDebtReminders: onDebtReminders,
    );
    final onTap = _onTapFor(
      context,
      entry,
      onOpenDebts: onOpenDebts,
      onOpenInstallments: onOpenInstallments,
    );

    final empty = _emptyStateFor(context, entry);

    Color? backgroundColor;
    Color? iconColor;

    if (entry.id == OwnerCatalogIds.debtsSummary ||
        entry.id == OwnerCatalogIds.retailDebtsSummary ||
        entry.id == OwnerCatalogIds.clothingDebtsSummary) {
      backgroundColor = Colors.orange.shade900.withValues(alpha: 0.2);
      iconColor = Colors.orange.shade300;
    } else if (entry.id == OwnerCatalogIds.installmentsSummary) {
      backgroundColor = Colors.blue.shade900.withValues(alpha: 0.2);
      iconColor = Colors.blue.shade300;
    }

    final card = OwnerKpiCardV3(
      title: title,
      section: section,
      sectionId: entry.sectionId,
      icon: iconFor(entry.id),
      valueBuilder: (data) => _valueFor(entry, data),
      onRetry: onRetry,
      trailing: trailing,
      emptyState: empty,
      isEmpty: _isEmptyFor(entry),
      trend: entry.supportsTrend ? center.trendForSection(entry.sectionId) : null,
      warningGlowWhen: _warningGlowFor(entry),
      backgroundColor: backgroundColor,
      iconColor: iconColor,
      onTap: onTap,
    );

    // اتجاه المبيعات يُعرض في [OwnerDashboardAnalyticsPanel] — لا نكرّر sparkline هنا.
    return [card];
  }

  static OwnerKpiEmptyState? _emptyStateFor(
    BuildContext context,
    OwnerKpiCatalogEntry entry,
  ) {
    switch (entry.id) {
      case OwnerCatalogIds.oilActiveCars:
        return OwnerKpiEmptyState(
          message: ownerDashboardL10n(OwnerDashboardL10nKeys.oilActiveCarsEmpty),
          ctaLabel: ownerDashboardL10n(OwnerDashboardL10nKeys.oilActiveCarsEmptyCta),
          onCta: () => OwnerShortcutNavigation.open(
            context,
            const OwnerShortcutCatalogEntry(
              id: 'oil_change_create',
              titleKey: OwnerDashboardL10nKeys.oilActiveCarsEmptyCta,
              routeId: 'oil_change_create',
              verticalAllowList: {BusinessVertical.oilChange},
            ),
          ),
        );
      case OwnerCatalogIds.oilChangesPeriod:
        return OwnerKpiEmptyState(
          message: ownerDashboardL10n(OwnerDashboardL10nKeys.oilChangesEmpty),
          ctaLabel: ownerDashboardL10n(OwnerDashboardL10nKeys.oilChangesEmptyCta),
          onCta: () => OwnerShortcutNavigation.open(
            context,
            const OwnerShortcutCatalogEntry(
              id: 'oil_change_create',
              titleKey: OwnerDashboardL10nKeys.oilActiveCarsEmptyCta,
              routeId: 'oil_change_create',
              verticalAllowList: {BusinessVertical.oilChange},
            ),
          ),
        );
      case OwnerCatalogIds.retailStockShortages:
        return OwnerKpiEmptyState(
          message: ownerDashboardL10n(
            OwnerDashboardL10nKeys.retailStockShortagesEmpty,
          ),
          ctaLabel: ownerDashboardL10n(OwnerDashboardL10nKeys.scInventory),
          onCta: () => OwnerShortcutNavigation.open(
            context,
            const OwnerShortcutCatalogEntry(
              id: OwnerShortcutIds.inventory,
              titleKey: OwnerDashboardL10nKeys.scInventory,
              routeId: 'inventory',
              verticalAllowList: {BusinessVertical.supermarket},
            ),
          ),
        );
      case OwnerCatalogIds.clothingVariantShortages:
        return OwnerKpiEmptyState(
          message: ownerDashboardL10n(
            OwnerDashboardL10nKeys.clothingVariantShortagesEmpty,
          ),
          ctaLabel: ownerDashboardL10n(OwnerDashboardL10nKeys.scInventory),
          onCta: () => OwnerShortcutNavigation.open(
            context,
            const OwnerShortcutCatalogEntry(
              id: OwnerShortcutIds.inventory,
              titleKey: OwnerDashboardL10nKeys.scInventory,
              routeId: 'inventory',
              verticalAllowList: {BusinessVertical.clothingStore},
            ),
          ),
        );
      default:
        return null;
    }
  }

  static bool Function(dynamic data)? _isEmptyFor(OwnerKpiCatalogEntry entry) {
    switch (entry.id) {
      case OwnerCatalogIds.oilActiveCars:
        return (data) => (data as OilActiveCarsKpi).activeCount <= 0;
      case OwnerCatalogIds.oilChangesPeriod:
        return (data) => (data as OilChangesKpi).changeCount <= 0;
      case OwnerCatalogIds.carWashPeriod:
        return (data) => (data as OilChangesKpi).changeCount <= 0;
      case OwnerCatalogIds.oilStockShortages:
        return (data) => (data as InventoryAlert).shortageCount <= 0;
      case OwnerCatalogIds.retailStockShortages:
        return (data) => (data as InventoryAlert).shortageCount <= 0;
      case OwnerCatalogIds.clothingVariantShortages:
        return (data) =>
            (data as ClothingVariantShortagesKpi).shortageCount <= 0;
      case OwnerCatalogIds.clothingSlowMovers:
        return (data) => (data as ClothingSlowMoversKpi).slowCount <= 0;
      default:
        return null;
    }
  }

  /// توهج تحذيري عند ≥3 نواقص — S5c.
  static bool Function(dynamic data)? _warningGlowFor(
    OwnerKpiCatalogEntry entry,
  ) {
    switch (entry.id) {
      case OwnerCatalogIds.oilStockShortages:
      case OwnerCatalogIds.retailStockShortages:
      case OwnerCatalogIds.clothingVariantShortages:
        return (data) {
          if (data is InventoryAlert) {
            return data.shortageCount >= 3;
          }
          if (data is ClothingVariantShortagesKpi) {
            return data.shortageCount >= 3;
          }
          return false;
        };
      default:
        return null;
    }
  }

  static String _valueFor(OwnerKpiCatalogEntry entry, dynamic data) {
    switch (entry.id) {
      case OwnerCatalogIds.oilActiveCars:
        return '${(data as OilActiveCarsKpi).activeCount}';
      case OwnerCatalogIds.oilChangesPeriod:
        final kpi = data as OilChangesKpi;
        final amount = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(kpi.revenueFils),
        );
        return '${kpi.changeCount} · $amount';
      case OwnerCatalogIds.carWashPeriod:
        final wash = data as OilChangesKpi;
        final washAmount = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(wash.revenueFils),
        );
        return '${wash.changeCount} · $washAmount';
      case OwnerCatalogIds.oilStockShortages:
        return '${(data as InventoryAlert).shortageCount} صنف';
      case OwnerCatalogIds.oilAvgTicket:
        return IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils((data as OilAvgTicketKpi).avgTicketFils),
        );
      case OwnerCatalogIds.hybridRevenueSplit:
        final h = data as HybridRevenueKpi;
        return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(h.totalFils));
      case OwnerCatalogIds.debtsSummary:
        final d = data as DebtSummary;
        final amount = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(d.totalReceivableFils),
        );
        return '$amount (${d.indebtedCustomerCount} عميل)';
      case OwnerCatalogIds.cashSummary:
        final c = data as CashSummary;
        final balance = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(c.balanceFils),
        );
        final todayIn = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(c.todayInFils),
        );
        return '$balance · اليوم +$todayIn';
      case OwnerCatalogIds.inventoryValue:
      case OwnerCatalogIds.retailInventoryValue:
      case OwnerCatalogIds.clothingInventoryValue:
        final v = data as InventoryValueKpi;
        final amount = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(v.totalCostFils),
        );
        return '$amount · ${v.productCount} صنف';
      case OwnerCatalogIds.retailStockShortages:
        return '${(data as InventoryAlert).shortageCount} صنف';
      case OwnerCatalogIds.retailSalesPeriod:
        return IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils((data as SalesKpi).salesFils),
        );
      case OwnerCatalogIds.clothingVariantShortages:
        return '${(data as ClothingVariantShortagesKpi).shortageCount} متغيّر';
      case OwnerCatalogIds.clothingSlowMovers:
        return '${(data as ClothingSlowMoversKpi).slowCount} متغيّر';
      case OwnerCatalogIds.clothingSalesPeriod:
        return IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils((data as SalesKpi).salesFils),
        );
      case OwnerCatalogIds.retailDebtsSummary:
        final d = data as DebtSummary;
        final amount = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(d.totalReceivableFils),
        );
        return '$amount (${d.indebtedCustomerCount} عميل)';
      case OwnerCatalogIds.retailCashSummary:
        final c = data as CashSummary;
        final balance = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(c.balanceFils),
        );
        final todayIn = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(c.todayInFils),
        );
        return '$balance · اليوم +$todayIn';
      case OwnerCatalogIds.clothingDebtsSummary:
        final cd = data as DebtSummary;
        final cdAmount = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(cd.totalReceivableFils),
        );
        return '$cdAmount (${cd.indebtedCustomerCount} عميل)';
      case OwnerCatalogIds.clothingCashSummary:
        final cc = data as CashSummary;
        final ccBalance = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(cc.balanceFils),
        );
        final ccToday = IraqiCurrencyFormat.formatIqd(
          IqdMoney.fromFils(cc.todayInFils),
        );
        return '$ccBalance · اليوم +$ccToday';
      case OwnerCatalogIds.installmentsSummary:
        final inst = data as InstallmentAlert;
        return 'متأخر: ${inst.overdueCount} · اليوم: ${inst.dueTodayCount}';
      default:
        return data.toString();
    }
  }

  static VoidCallback? _onTapFor(
    BuildContext context,
    OwnerKpiCatalogEntry entry, {
    VoidCallback? onOpenDebts,
    VoidCallback? onOpenInstallments,
  }) {
    void openShortcut(String shortcutId) {
      final sc = OwnerKpiCatalog.shortcutById(shortcutId);
      if (sc != null) OwnerShortcutNavigation.open(context, sc);
    }

    switch (entry.id) {
      case OwnerCatalogIds.oilStockShortages:
      case OwnerCatalogIds.retailStockShortages:
      case OwnerCatalogIds.clothingVariantShortages:
      case OwnerCatalogIds.inventoryValue:
      case OwnerCatalogIds.retailInventoryValue:
      case OwnerCatalogIds.clothingInventoryValue:
        return () => openShortcut(OwnerShortcutIds.inventory);
      case OwnerCatalogIds.debtsSummary:
      case OwnerCatalogIds.retailDebtsSummary:
      case OwnerCatalogIds.clothingDebtsSummary:
        return onOpenDebts;
      case OwnerCatalogIds.installmentsSummary:
        return onOpenInstallments;
      case OwnerCatalogIds.cashSummary:
      case OwnerCatalogIds.retailCashSummary:
      case OwnerCatalogIds.clothingCashSummary:
        return () => openShortcut(OwnerShortcutIds.cash);
      default:
        return null;
    }
  }

  static Widget? _trailingFor(
    BuildContext context,
    OwnerKpiCatalogEntry entry, {
    VoidCallback? onPurchasePdf,
    VoidCallback? onDebtReminders,
  }) {
    switch (entry.id) {
      case OwnerCatalogIds.oilStockShortages:
      case OwnerCatalogIds.retailStockShortages:
      case OwnerCatalogIds.clothingVariantShortages:
        if (onPurchasePdf == null) return null;
        return Tooltip(
          message: 'PDF طلبية',
          child: InkWell(
            onTap: onPurchasePdf,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.picture_as_pdf_outlined, size: 20),
            ),
          ),
        );
      case OwnerCatalogIds.debtsSummary:
      case OwnerCatalogIds.retailDebtsSummary:
      case OwnerCatalogIds.clothingDebtsSummary:
        if (onDebtReminders == null) return null;
        return Tooltip(
          message: 'تذكير واتساب',
          child: InkWell(
            onTap: onDebtReminders,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.chat_outlined, size: 20),
            ),
          ),
        );
      default:
        return null;
    }
  }

  static List<Widget> _hybridRevenueBlock(
    BuildContext context,
    OwnerKpiCatalogEntry entry,
    OwnerCommandCenterSnapshot snapshot,
    OwnerCommandCenterProvider center,
  ) {
    final section = snapshot.hybridRevenueSplit;
    if (section == null) return const [];
    return [
      OwnerHybridRevenueKpiCard(
        title: ownerDashboardL10n(entry.titleKey),
        section: section,
        sectionId: entry.sectionId,
        onRetry: () => center.refreshSection(entry.sectionId),
      ),
    ];
  }

  static List<Widget> _topSellersBlock(
    BuildContext context,
    OwnerKpiCatalogEntry entry,
    OwnerCommandCenterSnapshot snapshot,
    OwnerCommandCenterProvider center,
  ) {
    final section = snapshot.retailTopSellers;
    if (section == null) return const [];
    final emptyKey = entry.id == OwnerCatalogIds.clothingTopSellers
        ? OwnerDashboardL10nKeys.clothingTopSellersEmpty
        : OwnerDashboardL10nKeys.retailTopSellersEmpty;
    return [
      OwnerTopSellersKpiCard(
        title: ownerDashboardL10n(entry.titleKey),
        section: section,
        sectionId: entry.sectionId,
        onRetry: () => center.refreshSection(entry.sectionId),
        emptyMessageKey: emptyKey,
      ),
    ];
  }

  static List<Widget> _slowMoversBlock(
    BuildContext context,
    OwnerKpiCatalogEntry entry,
    OwnerCommandCenterSnapshot snapshot,
    OwnerCommandCenterProvider center,
  ) {
    final section = snapshot.clothingSlowMovers;
    if (section == null) return const [];
    return [
      OwnerSlowMoversKpiCard(
        title: ownerDashboardL10n(entry.titleKey),
        section: section,
        sectionId: entry.sectionId,
        onRetry: () => center.refreshSection(entry.sectionId),
      ),
    ];
  }

  static List<Widget> _openShiftsBlock(
    BuildContext context,
    OwnerCommandCenterSnapshot snapshot,
    OwnerCommandCenterProvider center,
  ) {
    final section = snapshot.openShifts;
    if (section.isLoading && !section.hasData) {
      return [const OwnerKpiCardSkeleton()];
    }
    return [
      OwnerKpiCard(
        title: ownerDashboardL10n(OwnerDashboardL10nKeys.openShiftsTitle),
        section: section,
        sectionId: OwnerSectionIds.openShifts,
        icon: iconFor(OwnerCatalogIds.openShifts),
        valueBuilder: (data) {
          final items = (data as OpenShiftsKpi).items;
          return items.isEmpty ? 'لا ورديات مفتوحة' : '${items.length} موظف';
        },
        onRetry: () => center.refreshSection(OwnerSectionIds.openShifts),
      ),
    ];
  }
}
