import 'package:flutter/material.dart';

import '../../home/specs/home_dashboard_spec.dart';
import '../../models/fluid_grade_sale_option.dart';
import '../../owner/models/owner_section_load_context.dart';
import '../../owner/specs/owner_kpi_catalog_entry.dart';
import '../../services/business_setup_settings.dart';
import '../../services/inventory_policy_settings.dart';
import '../../services/reports_repository.dart';

/// افتراضيات onboarding لميزات نشاط تجاري.
class VerticalDefaultFeatures {
  const VerticalDefaultFeatures({
    required this.settings,
  });

  final BusinessSetupSettingsData settings;

  factory VerticalDefaultFeatures.forVertical(String verticalId) {
    return VerticalDefaultFeatures(
      settings: BusinessSetupSettingsData.createForVertical(verticalId),
    );
  }
}

/// عنصر فرعي في القائمة الجانبية — metadata فقط (المسارات في [VerticalManifest.routes]).
class NavSubItemSpec {
  const NavSubItemSpec({
    required this.title,
    required this.routeId,
    this.breadcrumbTitle,
    this.icon,
  });

  final String title;
  final String routeId;
  final String? breadcrumbTitle;
  final IconData? icon;

  String get effectiveBreadcrumbTitle => breadcrumbTitle ?? title;
}

/// وحدة تنقل رئيسية في القائمة الجانبية.
class NavModuleSpec {
  const NavModuleSpec({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.routeId,
    this.breadcrumbTitle,
    this.subItems,
  });

  final IconData icon;
  final String title;
  final Color iconColor;
  final String routeId;
  final String? breadcrumbTitle;
  final List<NavSubItemSpec>? subItems;

  String get effectiveBreadcrumbTitle => breadcrumbTitle ?? title;
}

/// قسم تقارير يُسجَّله التخصص في شاشة التقارير المشتركة.
class ReportSectionSpec {
  const ReportSectionSpec({
    required this.sectionId,
    required this.titleAr,
    required this.requiredFeatureKey,
  });

  /// معرّف رقمي لمسار `reports(sectionId)` — مثل 8 لغيار الزيت.
  final int sectionId;
  final String titleAr;

  /// مفتاح ميزة من [BusinessSetupKeys] — يُفحص قبل عرض القسم.
  final String requiredFeatureKey;
}

/// سياسة مخزون/منتجات خاصة بالتخصص.
class InventoryPolicy {
  const InventoryPolicy({
    required this.businessProfileKey,
    this.preferVolumeLiterProducts = false,
    this.enableProductVariants = false,
    this.enableWeightSales = false,
  });

  /// قيمة [InventoryPolicyKeys.businessProfile] — مثل `retail` أو `clothing`.
  final String businessProfileKey;
  final bool preferVolumeLiterProducts;
  final bool enableProductVariants;
  final bool enableWeightSales;

  /// تحويل إلى [InventoryPolicySettingsData] الافتراضي للتخصص.
  InventoryPolicySettingsData toSettingsDefaults() {
    final profile = BusinessProfile.fromKey(businessProfileKey);
    return InventoryPolicySettingsData.defaults().copyWith(
      businessProfile: profile.key,
      enableProductVariants: enableProductVariants,
    );
  }
}

/// نتيجة معالجة مسح باركود على مستوى التخصص.
enum BarcodeScanDisposition {
  /// تمت المعالجة — لا تمرير للسياسة الافتراضية.
  handled,

  /// تجاهل — جرّب سياسة أخرى أو السلوك الافتراضي.
  passThrough,
}

/// سياق مسح باركود عام — يُمرَّر للتخصص النشط.
class BarcodeScanContext {
  const BarcodeScanContext({
    required this.barcode,
    required this.currentRouteId,
    this.hasOpenOilChangeCard = false,
  });

  final String barcode;
  final String currentRouteId;
  final bool hasOpenOilChangeCard;
}

/// سياسة مسح الباركود — كل vertical يحدّد Scan-to-Card أو غيره.
abstract class BarcodeScanPolicy {
  const BarcodeScanPolicy();

  BarcodeScanDisposition handleScan(BarcodeScanContext context);
}

/// alias موحّد لبطاقات KPI في catalog المالk.
typedef KpiCatalogEntry = OwnerKpiCatalogEntry;

/// نصوص محرّر عائلة السوائل (زيت/هيدروليك) — بدون ربط بـ vertical widgets.
class FluidFamilyEditorLabels {
  const FluidFamilyEditorLabels({
    required this.familyNoun,
    required this.familyNameExample,
    required this.gradeNoun,
    required this.pricingHint,
  });

  final String familyNoun;
  final String familyNameExample;
  final String gradeNoun;
  final String pricingHint;
}

/// محرّر مخزون عائلات السوائل — يُنفَّذ في vertical غيار الزيت.
abstract class VerticalFluidInventoryEditor {
  const VerticalFluidInventoryEditor();

  /// أنواع مخزون إضافية في «إضافة منتج» (4=هيدروليك، 5=زيت).
  List<int> get addProductStockTypes;

  Object newGradeDraft();

  void disposeGradeDraft(Object draft);

  void disposeGradeDrafts(Iterable<Object> drafts);

  Widget buildGradesEditor({
    required BuildContext context,
    required bool isOilFamily,
    required List<Object> grades,
    required VoidCallback onChanged,
  });

  FluidFamilyEditorLabels labels({required bool isOilFamily});

  String? validateFluidFamilyDrafts({
    required bool isOilFamily,
    required String familyName,
    required List<Object> gradeDrafts,
  });

  Future<int> createFluidFamily({
    required bool isOilFamily,
    required String familyName,
    required List<Object> gradeDrafts,
    int? categoryId,
    int? brandId,
    int? warehouseId,
    required double lowStockThreshold,
  });

  Future<List<FluidGradeSaleOption>> listSaleOptionsForParent(int parentProductId);

  /// هل أي مسودة درجة/لزوجة تحتوي حقولاً معدَّلة (لتأكيد الخروج).
  bool hasDirtyGradeDrafts(Iterable<Object> drafts);
}

/// شدة تنبيه صيدلاني عند البيع.
enum PharmacyAlertSeverity {
  error,
  warning,
  info,
}

/// سطر بيع لسياق التنبيهات — منتج + كمية + دفعة اختيارية.
class SaleAlertLine {
  const SaleAlertLine({
    required this.productId,
    required this.qty,
    this.batchId,
    this.productName,
  });

  final int productId;
  final double qty;
  final int? batchId;
  final String? productName;
}

/// تنبيه سريري/صيدلاني عند البيع.
class PharmacyAlert {
  const PharmacyAlert({
    required this.code,
    required this.messageAr,
    this.titleAr,
    this.descriptionAr,
    this.severity = PharmacyAlertSeverity.warning,
    this.blocksSale = false,
    this.allowsPharmacistOverride = false,
  });

  final String code;
  final String messageAr;
  final String? titleAr;
  final String? descriptionAr;
  final PharmacyAlertSeverity severity;
  final bool blocksSale;
  final bool allowsPharmacistOverride;

  bool get isError =>
      blocksSale || severity == PharmacyAlertSeverity.error;
}

/// سياق تقييم التنبيهات قبل إتمام البيع.
class SaleAlertContext {
  const SaleAlertContext({
    required this.tenantId,
    this.customerId,
    this.productIds = const [],
    this.lines = const [],
    this.saleDateTime,
  });

  final int tenantId;
  final int? customerId;
  final List<int> productIds;

  /// بنود البيع — يُفضَّل على [productIds] عند توفرها.
  final List<SaleAlertLine> lines;
  final DateTime? saleDateTime;
}

/// معطيات لوحة الدواء في نقطة البيع.
class PosDrugPanelArgs {
  const PosDrugPanelArgs({
    required this.productId,
    this.customerId,
    this.selectedBatchId,
    this.onBatchChanged,
    this.productName,
  });

  final int productId;
  final int? customerId;

  /// معرّف الدفعة المختارة — `null` = FEFO تلقائي.
  final int? selectedBatchId;

  /// يُستدعى عند اختيار دفعة مختلفة من لوحة POS.
  final void Function(int batchId)? onBatchChanged;

  /// اسم المنتج من Core (اختياري) — للعرض في رأس اللوحة.
  final String? productName;
}

/// لقطة مرجع دواء — للـ callbacks في Core بدون import من pharmacy.
abstract class VerticalPharmacyDrugReferenceSnapshot {
  const VerticalPharmacyDrugReferenceSnapshot();

  int get id;
  String get nameAr;
  String get nameEn;
  String? get atcCode;
}

/// لقطة مسودة دفعة — للـ callbacks في Core.
abstract class VerticalPharmacyBatchDraftSnapshot {
  const VerticalPharmacyBatchDraftSnapshot();

  String get batchNo;
  DateTime get expiryDate;
  int get costFils;
  double get qty;
}

/// جلسة محرّر صيدلية مدمجة في «إضافة منتج».
abstract class VerticalPharmacyProductEditorSession {
  const VerticalPharmacyProductEditorSession();

  Widget buildAddProductSection({
    required BuildContext context,
    required VoidCallback onChanged,
    void Function(VerticalPharmacyDrugReferenceSnapshot reference)?
        onDrugReferenceSelected,
    void Function(VerticalPharmacyBatchDraftSnapshot batch)? onBatchDraftChanged,
  });

  /// رسالة خطأ عربية — `null` إذا صالح.
  String? validateForSave();

  /// يحلّ اختيار المادة الفعّالة (مطابقة أو إنشاء من النص) قبل الحفظ.
  Future<String?> resolveReferenceBeforeSave();

  Future<void> save({
    required int tenantId,
    required int productId,
  });

  String? suggestedProductName();
  double? suggestedQty();
  int? suggestedCostFils();
  String? suggestedExpiryIso();

  void resetForm();

  void dispose();
}

/// محرّر منتج صيدلاني — يُنفَّذ في [BusinessVertical.pharmacy].
abstract class VerticalPharmacyProductEditor {
  const VerticalPharmacyProductEditor();

  VerticalPharmacyProductEditorSession createSession({int? tenantId});
}

/// عقد التخصص التجاري — مصدر الحقيقة لكل ما يخص vertical واحد.
abstract class VerticalManifest {
  const VerticalManifest();

  /// معرّف النشاط — يطابق [BusinessVertical.*].
  String get id;

  /// عناصر القائمة الجانبية (metadata — البناء في shell).
  List<NavModuleSpec> get navModules;

  /// مسارات المحتوى — routeId → builder.
  Map<String, WidgetBuilder> get routes;

  /// لوحة الموظف الرئيسية.
  HomeDashboardSpec resolveHome(BusinessSetupSettingsData features);

  /// لوحة المالk — يُكمِّل RBAC لاحقاً عبر [OwnerDashboardResolveInput].
  /// `null` = التخصص غير مفعّل أو لم يُنقل المنطق بعد.
  OwnerDashboardProfileSpec? resolveOwner(BusinessSetupSettingsData features);

  /// سلوك قارئ الباركود.
  BarcodeScanPolicy get barcodePolicy;

  /// أقسام التقارير التي يملكها هذا التخصص.
  List<ReportSectionSpec> get reportSections;

  /// سياسة إدخال المنتجات والمخزون.
  InventoryPolicy get inventoryPolicy;

  /// بطاقات KPI في catalog المالk.
  List<KpiCatalogEntry> get kpiCatalogEntries;

  /// افتراضيات onboarding.
  VerticalDefaultFeatures get defaultFeatures;

  /// بادئات مسارات تُحظر عند تعطيل التخصص (Route Guard).
  List<String> get routeGuardPrefixes => const [];

  /// مسارات كاملة تُحظر عند تعطيل التخصص.
  List<String> get routeGuardExact => const [];

  /// تحميل بيانات قسم لوحة المالك — `null` إن لم يُدعَم.
  Future<Object?> loadOwnerSection(
    String sectionId,
    OwnerSectionLoadContext context,
  ) async =>
      null;

  /// تحميل اتجاه WoW لقسم لوحة المالك — `null` إن لم يُدعَم.
  Future<Object?> loadOwnerSectionTrend(
    String sectionId,
    OwnerSectionLoadContext context,
  ) async =>
      null;

  /// تحميل لقطة قسم تقارير يملكه هذا التخصص — `null` إن لم يُدعَم.
  Future<Object?> loadReportSectionSnapshot(
    int sectionId,
    ReportDateRange range,
  ) async =>
      null;

  /// بناء لوحة قسم تقارير — `null` إن لم يُدعَم.
  Widget? buildReportSectionPanel(int sectionId, Object? snapshot) => null;

  /// محرّر عائلات السوائل — `null` للتخصصات التي لا تدعم زيت/هيدروليك.
  VerticalFluidInventoryEditor? get fluidInventoryEditor => null;

  /// محرّر منتج صيدلاني — `null` للتخصصات غير الصيدلانية.
  VerticalPharmacyProductEditor? get pharmacyProductEditor => null;

  /// لوحة الدواء في نقطة البيع — `null` إن لم يُدعَم.
  Widget? buildPosDrugPanel(BuildContext context, PosDrugPanelArgs args) =>
      null;

  /// تنبيهات البيع السريرية — فارغة افتراضياً.
  Future<List<PharmacyAlert>> evaluateSaleAlerts(
    SaleAlertContext context,
  ) async =>
      const [];

  /// لقطة بيانات صيدلانية للعميل — للعرض في POS.
  Future<VerticalPharmacyCustomerExtSnapshot?> loadCustomerPharmacySnapshot({
    required int tenantId,
    required int customerId,
  }) async =>
      null;

  /// شريط حساسيات العميل في نقطة البيع — `null` إذا لا حساسيات أو غير مدعوم.
  Widget? buildCustomerAllergiesBanner(List<String> allergies) => null;

  /// فتح لوحة البيانات الصيدلانية للعميل.
  Future<void> openCustomerPharmacyDetailSheet({
    required BuildContext context,
    required int tenantId,
    required int customerId,
    required String customerName,
    String? customerPhone,
    required VoidCallback onUpdated,
  }) async {}

  /// قسم «معلومات صيدلانية» في نموذج العميل — `null` إن لم يُدعَم.
  Widget? buildCustomerExtensionSection({
    required BuildContext context,
    required int tenantId,
    required int customerId,
    required String customerName,
    String? customerPhone,
    required VoidCallback onUpdated,
  }) =>
      null;

  /// بعد حفظ البيع — تحديث تواريخ إعادة شراء الأدوية المزمنة.
  Future<void> recordPharmacySaleCustomerExt({
    required int tenantId,
    required int customerId,
    required List<int> productIds,
    required DateTime purchasedAt,
  }) async {}

  /// أقسام تقارير الصيدلية — فارغة افتراضياً.
  List<PharmacyReportSectionSpec> get pharmacyReportSections => const [];

  /// لوحة KPIs للمالك — `null` إن لم يُدعَم.
  Future<VerticalPharmacyOwnerDashboardSnapshot?> loadOwnerDashboard({
    required int tenantId,
  }) async =>
      null;

  /// Widget تقارير الصيدلية — `null` إن لم يُدعَم.
  Widget? buildPharmacyReportPanel({
    required PharmacyReportSectionSpec section,
    required Object? snapshot,
  }) =>
      null;

  /// لوحة KPIs خاصة بالتخصص — تُعرض أعلى لوحة المالk v3.
  Widget? buildOwnerVerticalDashboardPanel() => null;

  /// إبطال cache KPIs/تقارير التخصص بعد حفظ فاتورة أو تغيير مخزون.
  void invalidateOwnerDashboardCache() {}
}

/// قسم تقرير صيدلاني.
class PharmacyReportSectionSpec {
  const PharmacyReportSectionSpec({
    required this.section,
    required this.titleAr,
    required this.reportsScreenId,
  });

  /// inventory · sales · finance · suppliers
  final String section;
  final String titleAr;

  /// معرّف القسم في شاشة التقارير المشتركة.
  final int reportsScreenId;
}

/// KPI واحد في لوحة المالك الصيدلانية.
class VerticalPharmacyKpiEntry {
  const VerticalPharmacyKpiEntry({
    required this.id,
    required this.titleAr,
    required this.valueText,
    this.subtitleAr,
  });

  final String id;
  final String titleAr;
  final String valueText;
  final String? subtitleAr;
}

/// لقطة لوحة المالك الصيدلانية — للـ Core بدون import من pharmacy.
abstract class VerticalPharmacyOwnerDashboardSnapshot {
  const VerticalPharmacyOwnerDashboardSnapshot();

  List<VerticalPharmacyKpiEntry> get kpiEntries;
}

/// لقطة امتداد العميل الصيدلاني — للـ Core بدون import من pharmacy.
class VerticalPharmacyCustomerExtSnapshot {
  const VerticalPharmacyCustomerExtSnapshot({
    this.allergies = const [],
  });

  final List<String> allergies;
}
