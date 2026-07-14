/// مفاتيح ترجمة لوحة المالk v3 — لا نصوص صريحة في Catalog.
abstract class OwnerDashboardL10nKeys {
  OwnerDashboardL10nKeys._();

  // ── KPI titles ──
  static const oilActiveCarsTitle = 'owner.kpi.oil_active_cars.title';
  static const oilChangesPeriodTitle = 'owner.kpi.oil_changes_period.title';
  static const oilStockShortagesTitle = 'owner.kpi.oil_stock_shortages.title';
  static const oilAvgTicketTitle = 'owner.kpi.oil_avg_ticket.title';
  static const hybridRevenueSplitTitle = 'owner.kpi.hybrid_revenue_split.title';
  static const debtsSummaryTitle = 'owner.kpi.debts_summary.title';
  static const installmentsSummaryTitle = 'owner.kpi.installments_summary.title';
  static const openShiftsTitle = 'owner.kpi.open_shifts.title';
  static const cashSummaryTitle = 'owner.kpi.cash_summary.title';
  static const inventoryValueTitle = 'owner.kpi.inventory_value.title';

  // ── Empty states ──
  static const oilActiveCarsEmpty = 'owner.kpi.oil_active_cars.empty';
  static const oilActiveCarsEmptyCta = 'owner.kpi.oil_active_cars.empty_cta';
  static const oilChangesEmpty = 'owner.kpi.oil_changes_period.empty';
  static const oilChangesEmptyCta = 'owner.kpi.oil_changes_period.empty_cta';

  // ── Shortcuts ──
  static const scOilReport = 'owner.shortcut.oil_report';
  static const scPurchasePdf = 'owner.shortcut.purchase_pdf';
  static const scOilLog = 'owner.shortcut.oil_log';
  static const scCustomers = 'owner.shortcut.customers';
  static const scInventory = 'owner.shortcut.inventory';
  static const scCash = 'owner.shortcut.cash';

  // ── Morning brief ──
  static const morningBriefOilChange = 'owner.morning_brief.oil_change';

  // ── v3.1 supermarket ──
  static const retailStockShortagesTitle =
      'owner.kpi.retail_stock_shortages.title';
  static const retailSalesPeriodTitle = 'owner.kpi.retail_sales_period.title';
  static const retailTopSellersTitle = 'owner.kpi.retail_top_sellers.title';
  static const retailStockShortagesEmpty =
      'owner.kpi.retail_stock_shortages.empty';
  static const retailTopSellersEmpty = 'owner.kpi.retail_top_sellers.empty';
  static const scReports = 'owner.shortcut.reports';
  static const scAddInvoice = 'owner.shortcut.add_invoice';
  static const scUsers = 'owner.shortcut.users';
  static const morningBriefSupermarket = 'owner.morning_brief.supermarket';

  // ── v3.1 clothing ──
  static const clothingVariantShortagesTitle =
      'owner.kpi.clothing_variant_shortages.title';
  static const clothingSlowMoversTitle = 'owner.kpi.clothing_slow_movers.title';
  static const clothingSalesPeriodTitle =
      'owner.kpi.clothing_sales_period.title';
  static const clothingTopSellersTitle = 'owner.kpi.clothing_top_sellers.title';
  static const clothingVariantShortagesEmpty =
      'owner.kpi.clothing_variant_shortages.empty';
  static const clothingSlowMoversEmpty = 'owner.kpi.clothing_slow_movers.empty';
  static const clothingTopSellersEmpty = 'owner.kpi.clothing_top_sellers.empty';
  static const morningBriefClothing = 'owner.morning_brief.clothing';
}

/// fallback عربي للاختبارات والـ UI حتى ربط ARB رسمي.
String ownerDashboardL10n(String key) {
  return _fallbackAr[key] ?? key;
}

const Map<String, String> _fallbackAr = {
  OwnerDashboardL10nKeys.oilActiveCarsTitle: 'سيارات في الورشة',
  OwnerDashboardL10nKeys.oilChangesPeriodTitle: 'غيارات الفترة',
  OwnerDashboardL10nKeys.oilStockShortagesTitle: 'نواقص زيوت وفلاتر',
  OwnerDashboardL10nKeys.oilAvgTicketTitle: 'متوسط قيمة الغيار',
  OwnerDashboardL10nKeys.hybridRevenueSplitTitle: 'إجمالي الإيرادات',
  OwnerDashboardL10nKeys.debtsSummaryTitle: 'ديون العملاء',
  OwnerDashboardL10nKeys.installmentsSummaryTitle: 'الأقساط',
  OwnerDashboardL10nKeys.openShiftsTitle: 'الورديات النشطة',
  OwnerDashboardL10nKeys.cashSummaryTitle: 'الصندوق',
  OwnerDashboardL10nKeys.inventoryValueTitle: 'قيمة المخزون',
  OwnerDashboardL10nKeys.oilActiveCarsEmpty: 'لا توجد سيارات في الورشة الآن',
  OwnerDashboardL10nKeys.oilActiveCarsEmptyCta: 'غيار زيت جديد',
  OwnerDashboardL10nKeys.oilChangesEmpty: 'لم تُسجَّل غيارات في هذه الفترة',
  OwnerDashboardL10nKeys.oilChangesEmptyCta: 'أول غيار',
  OwnerDashboardL10nKeys.scOilReport: 'تقرير الغيارات',
  OwnerDashboardL10nKeys.scPurchasePdf: 'PDF طلبية',
  OwnerDashboardL10nKeys.scOilLog: 'سجل الغيارات',
  OwnerDashboardL10nKeys.scCustomers: 'العملاء',
  OwnerDashboardL10nKeys.scInventory: 'المخزون',
  OwnerDashboardL10nKeys.scCash: 'الصندوق',
  OwnerDashboardL10nKeys.morningBriefOilChange: 'owner.morning_brief.oil_change',
  OwnerDashboardL10nKeys.retailStockShortagesTitle: 'نواقص الرفوف',
  OwnerDashboardL10nKeys.retailSalesPeriodTitle: 'مبيعات الفترة',
  OwnerDashboardL10nKeys.retailTopSellersTitle: 'أعلى 5 أصناف',
  OwnerDashboardL10nKeys.retailStockShortagesEmpty: 'المخزون جيد — لا نواقص',
  OwnerDashboardL10nKeys.retailTopSellersEmpty: 'لا مبيعات في هذه الفترة',
  OwnerDashboardL10nKeys.scReports: 'التقارير',
  OwnerDashboardL10nKeys.scAddInvoice: 'بيع سريع',
  OwnerDashboardL10nKeys.scUsers: 'إدارة المستخدمين',
  OwnerDashboardL10nKeys.morningBriefSupermarket: 'owner.morning_brief.supermarket',
  OwnerDashboardL10nKeys.clothingVariantShortagesTitle: 'نواقص المقاسات والألوان',
  OwnerDashboardL10nKeys.clothingSlowMoversTitle: 'أرصدة بطيئة الحركة',
  OwnerDashboardL10nKeys.clothingSalesPeriodTitle: 'مبيعات الفترة',
  OwnerDashboardL10nKeys.clothingTopSellersTitle: 'أعلى 5 أصناف',
  OwnerDashboardL10nKeys.clothingVariantShortagesEmpty:
      'لا نواقص — المقاسات متوفرة',
  OwnerDashboardL10nKeys.clothingSlowMoversEmpty: 'لا أرصدة راكدة في المخzون',
  OwnerDashboardL10nKeys.clothingTopSellersEmpty: 'لا مبيعات في هذه الفترة',
  OwnerDashboardL10nKeys.morningBriefClothing: 'owner.morning_brief.clothing',
};
