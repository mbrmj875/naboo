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
    PermissionGroupUi(
      title: 'التطبيق والوصول',
      items: const [
        PermissionItemUi(
          key: PermissionKeys.appDashboard,
          label: 'الرئيسية والتنقّل',
          subtitle: 'الوصول إلى لوحة التطبيق والأقسام الرئيسية',
        ),
      ],
    ),
    PermissionGroupUi(
      title: 'العملاء',
      items: const [
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
    PermissionGroupUi(
      title: 'ولاء العملاء',
      items: const [
        PermissionItemUi(
          key: PermissionKeys.loyaltyAccess,
          label: 'نقاط الولاء والإعدادات',
        ),
      ],
    ),
    PermissionGroupUi(
      title: 'المبيعات',
      items: const [
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
    PermissionGroupUi(
      title: 'المخزون',
      items: const [
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
    PermissionGroupUi(
      title: 'الصندوق',
      items: const [
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
    PermissionGroupUi(
      title: 'الديون (آجل)',
      items: const [
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
    PermissionGroupUi(
      title: 'الأقساط',
      items: const [
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
    PermissionGroupUi(
      title: 'التقارير والطباعة',
      items: const [
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
    PermissionGroupUi(
      title: 'المستخدمون والورديات',
      items: const [
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
    PermissionGroupUi(
      title: 'الإعدادات العامة',
      items: const [
        PermissionItemUi(
          key: PermissionKeys.settingsApp,
          label: 'إعدادات النظام والترخيص',
        ),
      ],
    ),
  ];
}
