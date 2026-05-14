import '../services/permission_service.dart';

/// مجموعات عرض الصلاحيات في واجهة المستخدم (عربي).
class PermissionGroupUi {
  const PermissionGroupUi({
    required this.title,
    required this.items,
  });

  final String title;
  final List<PermissionItemUi> items;
}

class PermissionItemUi {
  const PermissionItemUi({
    required this.key,
    required this.label,
    this.subtitle,
  });

  final String key;
  final String label;
  final String? subtitle;
}

/// ترتيب المجموعات والعناوين — يتطابق مع [PermissionKeys.allKeys].
List<PermissionGroupUi> buildPermissionGroupsUi() {
  return [
    const PermissionGroupUi(
      title: 'التطبيق والوصول',
      items: [
        PermissionItemUi(
          key: PermissionKeys.appDashboard,
          label: 'الرئيسية والتنقّل',
          subtitle: 'الوصول إلى لوحة التطبيق والأقسام الرئيسية',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'العملاء',
      items: [
        PermissionItemUi(
          key: PermissionKeys.customersView,
          label: 'عرض العملاء والبحث',
        ),
        PermissionItemUi(
          key: PermissionKeys.customersManage,
          label: 'إضافة وتعديل العملاء',
        ),
        PermissionItemUi(
          key: PermissionKeys.customersContacts,
          label: 'قائمة اتصال العملاء',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'ولاء العملاء',
      items: [
        PermissionItemUi(
          key: PermissionKeys.loyaltyAccess,
          label: 'نقاط الولاء والإعدادات',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'المبيعات',
      items: [
        PermissionItemUi(
          key: PermissionKeys.salesPos,
          label: 'شاشة البيع (نقطة البيع)',
        ),
        PermissionItemUi(
          key: PermissionKeys.salesParked,
          label: 'المبيعات المعلّقة',
        ),
        PermissionItemUi(
          key: PermissionKeys.salesReturns,
          label: 'المرتجعات',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'المخزون',
      items: [
        PermissionItemUi(
          key: PermissionKeys.inventoryView,
          label: 'عرض المنتجات والمخزون',
        ),
        PermissionItemUi(
          key: PermissionKeys.inventoryProductsManage,
          label: 'إدارة المنتجات والأسعار',
        ),
        PermissionItemUi(
          key: PermissionKeys.inventoryVoucherIn,
          label: 'حركات وارد مخزون',
        ),
        PermissionItemUi(
          key: PermissionKeys.inventoryVoucherOut,
          label: 'حركات صادر مخزون',
        ),
        PermissionItemUi(
          key: PermissionKeys.inventoryVoucherTransfer,
          label: 'تحويل بين المستودعات',
        ),
        PermissionItemUi(
          key: PermissionKeys.inventoryStocktakingManage,
          label: 'جرد المخزون',
        ),
        PermissionItemUi(
          key: PermissionKeys.inventoryPoliciesManage,
          label: 'سياسات المخزون والإعدادات',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'الصندوق',
      items: [
        PermissionItemUi(
          key: PermissionKeys.cashView,
          label: 'عرض الصندوق والحركات',
        ),
        PermissionItemUi(
          key: PermissionKeys.cashManual,
          label: 'إيداع وسحب وقيد يدوي',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'الديون (آجل)',
      items: [
        PermissionItemUi(
          key: PermissionKeys.debtsPanel,
          label: 'لوحة الديون والمتابعة',
        ),
        PermissionItemUi(
          key: PermissionKeys.debtsSettings,
          label: 'إعدادات الدين',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'الأقساط',
      items: [
        PermissionItemUi(
          key: PermissionKeys.installmentsPlans,
          label: 'خطط التقسيط والجداول',
        ),
        PermissionItemUi(
          key: PermissionKeys.installmentsSettings,
          label: 'إعدادات التقسيط',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'التقارير والطباعة',
      items: [
        PermissionItemUi(
          key: PermissionKeys.reportsAccess,
          label: 'التقارير والدفاتر',
        ),
        PermissionItemUi(
          key: PermissionKeys.printingAccess,
          label: 'الطباعة والقوالب',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'المستخدمون والورديات',
      items: [
        PermissionItemUi(
          key: PermissionKeys.usersView,
          label: 'عرض قائمة المستخدمين',
        ),
        PermissionItemUi(
          key: PermissionKeys.usersManage,
          label: 'إضافة وتعديل المستخدمين والصلاحيات',
        ),
        PermissionItemUi(
          key: PermissionKeys.shiftsAccess,
          label: 'ورديات الموظفين',
        ),
        PermissionItemUi(
          key: PermissionKeys.absencesAccess,
          label: 'غيابات الموظفين',
        ),
      ],
    ),
    const PermissionGroupUi(
      title: 'الإعدادات العامة',
      items: [
        PermissionItemUi(
          key: PermissionKeys.settingsApp,
          label: 'إعدادات النظام والترخيص',
        ),
      ],
    ),
  ];
}
