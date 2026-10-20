import '../providers/auth_provider.dart';
import '../providers/business_features_provider.dart';
import '../providers/permissions_provider.dart';
import '../services/permission_service.dart';
import 'guide_tour.dart';

class GuideSuggestedChip {
  const GuideSuggestedChip({
    required this.label,
    required this.question,
    this.tourId,
  });

  final String label;
  final String question;
  final String? tourId;
}

/// نطاق مساعد التطبيق — يحدد ماذا يُسمح بشرحه أو فتح جولة له حسب الدور والصلاحيات.
class AppAssistantScope {
  const AppAssistantScope({
    required this.isOwner,
    required this.roleKey,
    required this.oilFeatureEnabled,
    required this.allowedPermissionKeys,
  });

  final bool isOwner;
  final String roleKey;
  final bool oilFeatureEnabled;
  final Set<String> allowedPermissionKeys;

  factory AppAssistantScope.fromProviders({
    required AuthProvider auth,
    required PermissionsProvider permissions,
    required BusinessFeaturesProvider features,
  }) {
    final keys = <String>{};
    for (final k in PermissionKeys.allKeys) {
      if (auth.isOwner || permissions.can(k)) keys.add(k);
    }
    return AppAssistantScope(
      isOwner: auth.isOwner,
      roleKey: auth.roleKey.isNotEmpty
          ? auth.roleKey
          : (auth.isOwner ? 'owner' : 'staff'),
      oilFeatureEnabled: features.data.enableOilChange,
      allowedPermissionKeys: keys,
    );
  }

  /// غسيل السيارات يظهر مع عمودي الزيت على الرئيسية.
  bool get canUseOilAssistant => oilFeatureEnabled;

  bool get canUseCarWashAssistant => oilFeatureEnabled;

  bool get canUseAppAssistant =>
      canUseOilAssistant ||
      canUseCarWashAssistant ||
      isOwner ||
      canManageProducts;

  /// إعدادات واتساب/الربط الحساسة — للمالك أو من لديه إعدادات التطبيق.
  bool get canManageWhatsappConnect =>
      isOwner || allowedPermissionKeys.contains(PermissionKeys.settingsApp);

  bool get canCustomizeHome =>
      isOwner || allowedPermissionKeys.contains(PermissionKeys.settingsApp);

  /// إضافة/إدارة الموظفين — حالياً في التطبيق للمالك أو المدير.
  bool get canManageUsers =>
      isOwner ||
      roleKey == 'admin' ||
      allowedPermissionKeys.contains(PermissionKeys.usersManage);

  bool get canViewUsers =>
      canManageUsers ||
      allowedPermissionKeys.contains(PermissionKeys.usersView);

  bool get canViewOwnerDashboard =>
      isOwner ||
      allowedPermissionKeys.contains(PermissionKeys.ownerDashboardView);

  bool get canManageProducts =>
      isOwner ||
      allowedPermissionKeys.contains(PermissionKeys.inventoryProductsManage);

  bool get canViewInventory =>
      canManageProducts ||
      allowedPermissionKeys.contains(PermissionKeys.inventoryView);

  bool canStartTour(String tourId) {
    if (tourId == GuideTourIds.none) return false;
    switch (tourId) {
      case GuideTourIds.oilWhatsapp:
        return canUseOilAssistant && canManageWhatsappConnect;
      case GuideTourIds.oilFirstRun:
      case GuideTourIds.oilPendingTab:
      case GuideTourIds.oilPlateAutofill:
      case GuideTourIds.oilHubSettings:
      case GuideTourIds.oilCatalogOil:
      case GuideTourIds.oilCatalogFilter:
      case GuideTourIds.oilCatalogHydraulic:
      case GuideTourIds.oilServicesBase:
        return canUseOilAssistant;
      case GuideTourIds.carWashHome:
      case GuideTourIds.carWashCreate:
        return canUseCarWashAssistant;
      case GuideTourIds.carWashVisibility:
        return canUseCarWashAssistant && canCustomizeHome;
      case GuideTourIds.usersAddStaff:
        return canManageUsers;
      case GuideTourIds.usersModuleOverview:
      case GuideTourIds.usersIdentity:
      case GuideTourIds.usersShifts:
        return canViewUsers;
      case GuideTourIds.productAddOverview:
      case GuideTourIds.productStockCount:
      case GuideTourIds.productStockVolume:
      case GuideTourIds.productStockHydraulic:
      case GuideTourIds.productStockOil:
      case GuideTourIds.productPricingInventory:
        // جولة تعليمية لمن يستطيع رؤية المخزون أو إدارته.
        return canViewInventory;
      default:
        return isOwner;
    }
  }

  List<GuideSuggestedChip> suggestedChips() {
    if (!canUseAppAssistant) {
      return const [
        GuideSuggestedChip(
          label: 'ما الذي أستطيع سؤاله؟',
          question: 'ما الذي يمكنني سؤاله الآن؟',
        ),
      ];
    }

    final chips = <GuideSuggestedChip>[];

    if (canViewUsers) {
      chips.add(
        const GuideSuggestedChip(
          label: 'دليل المستخدمين',
          question:
              'اشرح لي وحدة المستخدمين بالتفصيل: إدارة المستخدمين والهويات والورديات',
          tourId: GuideTourIds.usersModuleOverview,
        ),
      );
    }
    if (canManageUsers) {
      chips.add(
        const GuideSuggestedChip(
          label: 'إضافة موظف',
          question:
              'كيف أضيف مستخدماً جديداً؟ اشرح صفحة بيانات المستخدم والحقول بالتفصيل',
          tourId: GuideTourIds.usersAddStaff,
        ),
      );
    }

    if (canViewInventory) {
      chips.addAll(const [
        GuideSuggestedChip(
          label: 'إضافة منتج',
          question:
              'كيف أضيف منتجاً جديداً؟ اشرح الحقول وما هي فائدة كل خانة',
          tourId: GuideTourIds.productAddOverview,
        ),
        GuideSuggestedChip(
          label: 'منتج بالعدد',
          question: 'شلون أضيف منتج بالعدد (قطعة) خطوة بخطوة؟',
          tourId: GuideTourIds.productStockCount,
        ),
        GuideSuggestedChip(
          label: 'منتج بالحجم',
          question: 'شلون أضيف منتج بالحجم (لتر) مع وحدات إضافية؟',
          tourId: GuideTourIds.productStockVolume,
        ),
        GuideSuggestedChip(
          label: 'عائلة هيدروليك',
          question: 'شلون أسوي عائلة هيدروليك بدرجات وعبوات؟',
          tourId: GuideTourIds.productStockHydraulic,
        ),
        GuideSuggestedChip(
          label: 'عائلة زيت',
          question: 'شلون أسوي عائلة زيت بلزوجات وعبوات؟',
          tourId: GuideTourIds.productStockOil,
        ),
        GuideSuggestedChip(
          label: 'تسعير ومخزون',
          question: 'اشرح خانات التسعير وإدارة المخزون للمنتج',
          tourId: GuideTourIds.productPricingInventory,
        ),
      ]);
    }

    if (canViewUsers) {
      chips.addAll(const [
        GuideSuggestedChip(
          label: 'هويات الموظفين',
          question: 'وين هويات الموظفين وشلون أعرض بطاقة الهوية؟',
          tourId: GuideTourIds.usersIdentity,
        ),
        GuideSuggestedChip(
          label: 'ورديات الموظفين',
          question: 'وين ورديات الموظفين الأسبوعية وكيف أقرأها؟',
          tourId: GuideTourIds.usersShifts,
        ),
      ]);
    }

    if (canUseCarWashAssistant) {
      chips.add(
        const GuideSuggestedChip(
          label: 'غسيل السيارات',
          question: 'شلون أسجّل غسيل سيارة من الرئيسية؟',
          tourId: GuideTourIds.carWashCreate,
        ),
      );
      if (canCustomizeHome) {
        chips.add(
          const GuideSuggestedChip(
            label: 'إخفاء زر الغسيل',
            question: 'كيف أخفي أو أظهر زر غسيل السيارات من الرئيسية؟',
            tourId: GuideTourIds.carWashVisibility,
          ),
        );
      }
    }

    if (canUseOilAssistant) {
      chips.addAll(const [
        GuideSuggestedChip(
          label: 'زيت مناسب لسيارتي',
          question:
              'عندي سيارة بنزين عدادها حوالي 120 ألف كم في العراق، شنو اللزوجة والزيت المناسب؟',
        ),
        GuideSuggestedChip(
          label: 'لزوجة لصيف العراق',
          question:
              'بأجواء صيف العراق الحارة، شنو أفضل لزوجات زيت شائعة للسيارات اليابانية والكورية؟',
        ),
        GuideSuggestedChip(
          label: 'كيف أسجّل غيار زيت؟',
          question: 'كيف أسجّل غيار زيت؟',
          tourId: GuideTourIds.oilFirstRun,
        ),
        GuideSuggestedChip(
          label: 'وين المعلّقة؟',
          question: 'وين الفواتير المعلّقة؟',
          tourId: GuideTourIds.oilPendingTab,
        ),
        GuideSuggestedChip(
          label: 'جلب بيانات اللوحة',
          question: 'كيف أجيب بيانات السيارة من رقم اللوحة؟',
          tourId: GuideTourIds.oilPlateAutofill,
        ),
        GuideSuggestedChip(
          label: 'إعدادات غيار الزيت',
          question: 'وين إعدادات غيار الزيت وشلون أضبطها؟',
          tourId: GuideTourIds.oilHubSettings,
        ),
        GuideSuggestedChip(
          label: 'كتالوج الزيت',
          question: 'كيف أضيف زيت ولزوجة للكتالوج؟',
          tourId: GuideTourIds.oilCatalogOil,
        ),
        GuideSuggestedChip(
          label: 'السعر الأساسي',
          question: 'وين سعر تبديل الزيت الأساسي؟',
          tourId: GuideTourIds.oilServicesBase,
        ),
      ]);
    }

    if (canManageWhatsappConnect && canUseOilAssistant) {
      chips.addAll(const [
        GuideSuggestedChip(
          label: 'طرق ربط واتساب',
          question: 'ما هي طرق ربط وفصل واتساب؟',
          tourId: GuideTourIds.oilWhatsapp,
        ),
        GuideSuggestedChip(
          label: 'ليش ما يوصل واتساب؟',
          question: 'ليش ما يوصل واتساب للزبون؟',
          tourId: GuideTourIds.oilWhatsapp,
        ),
      ]);
    }

    if (canViewOwnerDashboard) {
      chips.add(
        const GuideSuggestedChip(
          label: 'لوحة صاحب العمل',
          question:
              'كيف أستخدم لوحة صاحب العمل لمراقبة غيار الزيت والمؤشرات؟',
        ),
      );
    }

    return chips;
  }

  String welcomeMessage() {
    if (!canUseAppAssistant) {
      return 'مرحباً. المساعد غير متاح على هذا الحساب حالياً.';
    }
    if (isOwner) {
      return 'مرحباً بك كصاحب العمل. اسأل عن إضافة الموظفين وبوابة «من سيبدأ العمل؟»، '
          'أو كفني غيار زيت، أو الرئيسية والغسيل وواتساب — أو اختر اقتراحاً.';
    }
    return 'مرحباً. أساعدك ضمن صلاحياتك: غيار الزيت، الغسيل، '
        '${canManageUsers ? 'وإدارة المستخدمين، ' : ''}'
        'واقتراحات الزيت لأجواء العراق. اسأل أو اختر اقتراحاً.';
  }

  String get titleAr => isOwner ? 'مساعد نابو (المالك)' : 'مساعد نابو';

  String get subtitleAr {
    if (!canUseAppAssistant) return 'المساعد';
    if (canManageUsers && canUseOilAssistant) {
      return 'موظفون · فني زيت · الرئيسية';
    }
    if (canUseOilAssistant) {
      return 'فني غيار زيت · الرئيسية · الغسيل';
    }
    return 'المساعد';
  }

  /// مفاتيح تُرسل للسيرفر لتوجيه الرد فقط (لا تُستخدم كمصدر ثقة وحيد).
  Map<String, dynamic> toAiPayload() {
    return {
      'is_owner': isOwner,
      'role_key': roleKey,
      'oil_enabled': oilFeatureEnabled,
      'car_wash_enabled': canUseCarWashAssistant,
      'can_whatsapp': canManageWhatsappConnect,
      'can_customize_home': canCustomizeHome,
      'can_manage_users': canManageUsers,
      'can_owner_dashboard': canViewOwnerDashboard,
      'can_manage_products': canManageProducts,
      'can_view_inventory': canViewInventory,
      'permissions': allowedPermissionKeys.take(40).toList(),
    };
  }
}
