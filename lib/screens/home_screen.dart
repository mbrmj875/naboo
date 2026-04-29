import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../services/app_settings_repository.dart';
import '../services/business_setup_settings.dart';
import '../providers/notification_provider.dart';
import '../providers/shift_provider.dart';
import '../providers/product_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/sale_draft_provider.dart';
import '../providers/parked_sales_provider.dart';
import '../widgets/search_virtual_keyboard.dart';
import '../widgets/virtual_keyboard_controller.dart';
import '../widgets/dashboard_view.dart';
import '../widgets/home_glance_orbit.dart';
import '../widgets/invoice_detail_sheet.dart';
import '../models/recent_activity_entry.dart';
import '../widgets/barcode_input_launcher.dart';
import '../widgets/app_notifications_sheet.dart';
import 'invoices/invoices_screen.dart';
import 'installments/installment_settings_screen.dart';
import 'installments/installments_screen.dart';
import 'debts/customer_debt_detail_screen.dart';
import 'debts/debts_screen.dart';
import 'debts/debt_settings_screen.dart';
import 'inventory/inventory_hub_screen.dart';
import 'inventory/add_product_screen.dart';
import 'inventory/quick_product_update_screen.dart';
import 'inventory/inventory_products_screen.dart';
import 'inventory/barcode_labels_screen.dart';
import 'inventory/inventory_management_screen.dart';
import 'inventory/warehouses_screen.dart';
import 'inventory/stocktaking_screen.dart';
import 'inventory/purchase_orders_screen.dart';
import 'inventory/stock_analytics_screen.dart';
import 'inventory/inventory_settings_screen.dart';
import 'cash/cash_screen.dart';
import 'printing/printing_screen.dart';
import 'users/users_screen.dart';
import 'users/employee_identity_screen.dart';
import 'users/staff_shifts_week_screen.dart';
import 'reports/reports_screen.dart';
import 'expenses/expenses_screen.dart';
import 'invoices/add_invoice_screen.dart';
import 'invoices/process_return_screen.dart';
import '../utils/iraqi_currency_format.dart';
import 'invoices/parked_sales_screen.dart';
import 'invoices/sale_pos_settings_screen.dart';
import 'customers/customers_screen.dart';
import 'customers/customer_form_screen.dart';
import 'customers/customer_contacts_screen.dart';
import 'loyalty/loyalty_settings_screen.dart';
import 'loyalty/loyalty_ledger_screen.dart';
import 'settings/settings_screen.dart';
import '../services/mac_style_settings_prefs.dart';
import '../widgets/mac_style_settings_panel.dart';
import '../widgets/floating_calculator_overlay.dart';
import '../widgets/app_brand_mark.dart';
import 'shift/close_shift_dialog.dart';
import '../theme/app_corner_style.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_breadcrumb_strip.dart';
import '../widgets/sidebar_nav_highlight.dart';
import '../navigation/content_navigation.dart';
import '../utils/screen_layout.dart';
import '../models/invoice.dart';
import '../services/database_helper.dart';
import '../services/product_repository.dart';
import '../services/cloud_sync_service.dart';
import '../services/permission_service.dart';
import '../providers/global_barcode_route_bridge.dart';
import '../utils/invoice_barcode.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  /// لوحة مفاتيح عربي/إنجليزي — تظهر فوق المحتوى دون تقليص نافذة التطبيق.
  bool _showVirtualSearchKeyboard = false;
  String _searchQuery = '';
  Timer? _searchDebounce;
  bool _globalSearchLoading = false;
  final ProductRepository _productRepo = ProductRepository();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _hitProducts = [];
  List<Map<String, dynamic>> _hitCustomers = [];
  List<Map<String, dynamic>> _hitUsers = [];
  List<ModuleItem> _hitModules = [];

  bool get _isDarkMode =>
      Provider.of<ThemeProvider>(context, listen: false).isDarkMode;

  final ValueNotifier<bool> _isDrawerOpen = ValueNotifier(false);
  late AnimationController _nameAnimController;

  /// Inner Navigator key — keeps sidebar visible across screens on large displays.
  final GlobalKey<NavigatorState> _innerNavKey = GlobalKey<NavigatorState>();

  /// Inner Navigator key for small screens — keeps bottom nav fixed.
  final GlobalKey<NavigatorState> _innerNavKeySmall =
      GlobalKey<NavigatorState>();

  ShiftProvider? _shiftProviderForGateListener;

  GlobalBarcodeRouteBridge? _barcodeBridge;
  bool _barcodeBridgeAttached = false;

  /// بعد تطبيق صلاحيات موظف الوردية على القائمة الجانبية/السفلية.
  bool _navFilterApplied = false;
  List<ModuleItem> _visibleNavModules = [];

  List<ModuleItem> get _navForUi =>
      _navFilterApplied ? _visibleNavModules : _orderedModules;

  void _shiftGateListener() {
    if (!mounted) return;
    final shift = _shiftProviderForGateListener;
    if (shift == null) return;
    unawaited(_recomputeNavModules());
    if (shift.hasOpenShift) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = _shiftProviderForGateListener;
      if (s != null && !s.hasOpenShift) {
        Navigator.of(context).pushReplacementNamed('/open-shift');
      }
    });
  }

  String? _navPermissionKeyForMainRoute(String routeId) {
    if (routeId.startsWith(AppContentRoutes.reportsPrefix)) {
      return PermissionKeys.reportsAccess;
    }
    switch (routeId) {
      case AppContentRoutes.invoices:
        return PermissionKeys.salesPos;
      case AppContentRoutes.customers:
        return PermissionKeys.customersView;
      case AppContentRoutes.loyaltySettings:
        return PermissionKeys.loyaltyAccess;
      case AppContentRoutes.installments:
        return PermissionKeys.installmentsPlans;
      case AppContentRoutes.debts:
        return PermissionKeys.debtsPanel;
      case AppContentRoutes.inventory:
        return PermissionKeys.inventoryView;
      case AppContentRoutes.cash:
        return PermissionKeys.cashView;
      case AppContentRoutes.users:
        return null;
      case AppContentRoutes.printing:
        return PermissionKeys.printingAccess;
      default:
        return null;
    }
  }

  Future<void> _recomputeNavModules() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final shiftProv = context.read<ShiftProvider>();
    final activeShift = shiftProv.activeShift;
    final perm = PermissionService.instance;
    final settingsRepo = AppSettingsRepository.instance;

    bool enableDebts = true;
    bool enableInstallments = true;
    bool enableCustomers = true;
    bool enableLoyalty = true;
    try {
      final tenantId = await settingsRepo.getActiveTenantId();
      enableDebts =
          (await settingsRepo.getForTenant(
                BusinessSetupKeys.enableDebts,
                tenantId: tenantId,
              ) ??
              '1') ==
          '1';
      enableInstallments =
          (await settingsRepo.getForTenant(
                BusinessSetupKeys.enableInstallments,
                tenantId: tenantId,
              ) ??
              '1') ==
          '1';
      enableCustomers =
          (await settingsRepo.getForTenant(
                BusinessSetupKeys.enableCustomers,
                tenantId: tenantId,
              ) ??
              '1') ==
          '1';
      enableLoyalty =
          (await settingsRepo.getForTenant(
                BusinessSetupKeys.enableLoyalty,
                tenantId: tenantId,
              ) ??
              '1') ==
          '1';
    } catch (_) {
      // في حال تعذر قراءة الإعدادات: لا نكسر التصفح.
    }

    Future<bool> allow(String key) => perm.canForSession(
      sessionUserId: auth.userId,
      sessionRoleKey: auth.isAdmin ? 'admin' : 'staff',
      activeShift: activeShift,
      permissionKey: key,
    );

    final source = _orderedModules;
    final out = <ModuleItem>[];

    for (final m in source) {
      if (!enableDebts && m.routeId == AppContentRoutes.debts) continue;
      if (!enableInstallments && m.routeId == AppContentRoutes.installments) {
        continue;
      }
      if (!enableCustomers && m.routeId == AppContentRoutes.customers) continue;
      if (!enableLoyalty && m.routeId == AppContentRoutes.loyaltySettings) {
        continue;
      }
      if (m.routeId == AppContentRoutes.users) {
        final subs = m.subItems;
        if (subs == null) continue;
        final newSubs = <SubMenuItem>[];
        for (final s in subs) {
          String key;
          switch (s.routeId) {
            case AppContentRoutes.users:
              key = PermissionKeys.usersView;
              break;
            case AppContentRoutes.staffShiftsWeek:
              key = PermissionKeys.shiftsAccess;
              break;
            case AppContentRoutes.employeeIdentity:
              key = PermissionKeys.usersView;
              break;
            default:
              key = PermissionKeys.usersView;
          }
          if (await allow(key)) newSubs.add(s);
        }
        if (newSubs.isEmpty) continue;
        out.add(
          ModuleItem(
            icon: m.icon,
            title: m.title,
            iconColor: m.iconColor,
            routeId: m.routeId,
            breadcrumbTitle: m.breadcrumbTitle,
            destination: m.destination,
            subItems: newSubs,
          ),
        );
        continue;
      }

      final key = _navPermissionKeyForMainRoute(m.routeId);
      if (key == null) {
        out.add(m);
        continue;
      }
      if (await allow(key)) out.add(m);
    }

    if (!mounted) return;
    setState(() {
      _visibleNavModules = out;
      _navFilterApplied = true;
    });
  }

  /// جلسة العمل مرتبطة بوردية مفتوحة: لا وصول للرئيسية بدون وردية (بعد إغلاقها أو مزامنة أزلتها).
  Future<void> _ensureActiveShiftGate() async {
    if (!mounted) return;
    try {
      await context.read<ShiftProvider>().refresh();
    } catch (_) {}
    if (!mounted) return;
    if (!context.read<ShiftProvider>().hasOpenShift) {
      Navigator.of(context).pushReplacementNamed('/open-shift');
    }
  }

  /// مزامنة فتات الخبز مع مكدس [Navigator] الداخلي.
  late final NavigatorObserver _innerNavObserver = _HomeInnerNavObserver(this);

  /// مسار الشاشات الحالي (الرئيسية → …) للعرض والرجوع السريع.
  final List<BreadcrumbSegment> _breadcrumbTrail = [
    const BreadcrumbSegment(id: AppContentRoutes.home, title: 'الرئيسية'),
  ];

  /// Active tab index for the bottom nav bar (small screens) ومزامنة تمييز الشريط الجانبي.
  int _activeBottomIndex = 0;

  /// يطابق مسار المحتوى الحالي مع فهرس وحدة في [_orderedModules] لتمييز الشريط السفلي/الجانبي.
  int? _indexForContentRoute(String name) {
    if (name == AppContentRoutes.home) return 0;
    for (var i = 0; i < _navForUi.length; i++) {
      if (_navForUi[i].routeId == name) return i;
    }
    for (var i = 0; i < _navForUi.length; i++) {
      for (final s in _navForUi[i].subItems ?? const <SubMenuItem>[]) {
        if (s.routeId == name) return i;
      }
    }
    if (name.startsWith(AppContentRoutes.reportsPrefix)) {
      final i = _navForUi.indexWhere(
        (m) => m.routeId.startsWith(AppContentRoutes.reportsPrefix),
      );
      if (i >= 0) return i;
    }
    final invIdx = _navForUi.indexWhere(
      (m) => m.routeId == AppContentRoutes.invoices,
    );
    if (invIdx >= 0) {
      if (name == AppContentRoutes.addInvoice ||
          name == AppContentRoutes.parkedSales ||
          name == AppContentRoutes.salePosSettings ||
          name.startsWith('app_process_return')) {
        return invIdx;
      }
    }
    final hubIdx = _navForUi.indexWhere(
      (m) => m.routeId == AppContentRoutes.inventory,
    );
    if (hubIdx >= 0 &&
        (name.startsWith('app_inventory') ||
            name == AppContentRoutes.addProduct ||
            name == AppContentRoutes.quickUpdateProducts)) {
      return hubIdx;
    }
    return null;
  }

  /// يُستدعى من [NavigatorObserver] أثناء تركيب/استعادة الـ Navigator — لا [setState] متزامن.
  void _syncActiveModuleIndexFromRoute(String? name) {
    if (!mounted || name == null) return;
    final idx = _indexForContentRoute(name);
    final expandParents = <String>{};
    for (final m in _navForUi) {
      for (final s in m.subItems ?? const <SubMenuItem>[]) {
        if (s.routeId == name) {
          expandParents.add(m.title);
          break;
        }
      }
    }
    // بعد دورة الحدث ثم بعد الإطار — يقلل تعارض استعادة الـ Navigator مع تركيب العناصر.
    scheduleMicrotask(() {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          for (final t in expandParents) {
            _expandedSubmenus.add(t);
          }
          if (idx != null) {
            _activeBottomIndex = idx;
          }
        });
      });
    });
  }

  // تتبع الوحدات التي فتحت قائمتها الفرعية
  final Set<String> _expandedSubmenus = {};

  // ===== قائمة الاختصارات السريعة الديناميكية =====
  List<QuickAction> _quickActions = [];
  bool _isEditMode = false; // وضع التحرير

  /// ترتيب الوحدات: مبيعات وعملاء → أقساط ومخزون وصندوق → تقارير وإدارة → أدوات.
  final List<ModuleItem> _originalModules = [
    ModuleItem(
      icon: Icons.receipt,
      title: 'الفواتير',
      iconColor: Colors.green,
      routeId: AppContentRoutes.invoices,
      destination: (context) => const InvoicesScreen(),
      subItems: [
        SubMenuItem(
          title: 'قائمة الفواتير',
          routeId: AppContentRoutes.invoices,
          destination: (context) => const InvoicesScreen(),
        ),
        SubMenuItem(
          title: 'بيع جديد',
          routeId: AppContentRoutes.addInvoice,
          destination: (context) => const AddInvoiceScreen(),
        ),
        SubMenuItem(
          title: 'معلّقة مؤقتاً',
          routeId: AppContentRoutes.parkedSales,
          destination: (context) => const ParkedSalesScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات نقطة البيع',
          routeId: AppContentRoutes.salePosSettings,
          destination: (context) => const SalePosSettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.person_outline,
      title: 'العملاء',
      iconColor: Colors.teal,
      routeId: AppContentRoutes.customers,
      destination: (context) => const CustomersScreen(),
      subItems: [
        SubMenuItem(
          title: 'إدارة العملاء',
          routeId: AppContentRoutes.customers,
          destination: (context) => const CustomersScreen(),
        ),
        SubMenuItem(
          title: 'إضافة عميل جديد',
          routeId: AppContentRoutes.customersAdd,
          breadcrumbTitle: 'إضافة عميل',
          destination: (context) => const CustomerFormScreen(),
        ),
        SubMenuItem(
          title: 'قائمة الاتصال',
          routeId: AppContentRoutes.customerContacts,
          destination: (context) => const CustomerContactsScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات العميل (الولاء)',
          routeId: AppContentRoutes.loyaltySettings,
          destination: (context) => const LoyaltySettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.card_giftcard_rounded,
      title: 'ولاء العملاء',
      iconColor: Colors.deepPurple,
      routeId: AppContentRoutes.loyaltySettings,
      destination: (context) => const LoyaltySettingsScreen(),
      subItems: [
        SubMenuItem(
          title: 'إعدادات النقاط والاستبدال',
          routeId: AppContentRoutes.loyaltySettings,
          destination: (context) => const LoyaltySettingsScreen(),
        ),
        SubMenuItem(
          title: 'سجل حركات النقاط',
          routeId: AppContentRoutes.loyaltyLedger,
          destination: (context) => const LoyaltyLedgerScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.calendar_today,
      title: 'الأقساط',
      iconColor: Colors.blue,
      routeId: AppContentRoutes.installments,
      destination: (context) => const InstallmentsScreen(),
      subItems: [
        SubMenuItem(
          title: 'خطط التقسيط',
          icon: Icons.receipt_long_rounded,
          routeId: AppContentRoutes.installments,
          destination: (context) => const InstallmentsScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات تقسيط',
          icon: Icons.tune_rounded,
          routeId: AppContentRoutes.installmentSettings,
          destination: (context) => const InstallmentSettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.balance_outlined,
      title: 'الديون',
      iconColor: Colors.amber,
      routeId: AppContentRoutes.debts,
      destination: (context) => const DebtsScreen(),
      subItems: [
        SubMenuItem(
          title: 'لوحة الديون (آجل)',
          icon: Icons.dashboard_customize_outlined,
          routeId: AppContentRoutes.debts,
          destination: (context) => const DebtsScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات الدين',
          icon: Icons.tune_rounded,
          routeId: AppContentRoutes.debtSettings,
          destination: (context) => const DebtSettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.inventory_2,
      title: 'المخزون',
      iconColor: Colors.orange,
      routeId: AppContentRoutes.inventory,
      destination: (context) => const InventoryHubScreen(),
      subItems: [
        SubMenuItem(
          title: 'قائمة المنتجات',
          routeId: AppContentRoutes.inventoryProducts,
          destination: (context) => const InventoryProductsScreen(),
        ),
        SubMenuItem(
          title: 'إضافة منتج جديد',
          routeId: AppContentRoutes.addProduct,
          destination: (context) => const AddProductScreen(),
        ),
        SubMenuItem(
          title: 'تحديث منتج موجود',
          routeId: AppContentRoutes.quickUpdateProducts,
          destination: (context) => const QuickProductUpdateScreen(),
        ),
        SubMenuItem(
          title: 'طباعة ملصقات باركود',
          routeId: AppContentRoutes.inventoryBarcodeLabels,
          destination: (context) => const BarcodeLabelsScreen(),
        ),
        SubMenuItem(
          title: 'حركات المخزون',
          routeId: AppContentRoutes.inventoryManagement,
          destination: (context) => const InventoryManagementScreen(),
        ),
        SubMenuItem(
          title: 'المستودعات',
          routeId: AppContentRoutes.inventoryWarehouses,
          destination: (context) => const WarehousesScreen(),
        ),
        SubMenuItem(
          title: 'الجرد الدوري',
          routeId: AppContentRoutes.inventoryStocktaking,
          destination: (context) => const StocktakingScreen(),
        ),
        SubMenuItem(
          title: 'أوامر الشراء',
          routeId: AppContentRoutes.inventoryPurchaseOrders,
          destination: (context) => const PurchaseOrdersScreen(),
        ),
        SubMenuItem(
          title: 'تحليلات المخزون',
          routeId: AppContentRoutes.inventoryAnalytics,
          destination: (context) => const StockAnalyticsScreen(),
        ),
        SubMenuItem(
          title: 'إعدادات المخزون',
          routeId: AppContentRoutes.inventorySettings,
          destination: (context) => const InventorySettingsScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.account_balance_wallet,
      title: 'الصندوق',
      iconColor: Colors.purple,
      routeId: AppContentRoutes.cash,
      destination: (context) => const CashScreen(),
    ),
    ModuleItem(
      icon: Icons.payments_outlined,
      title: 'المصروفات',
      iconColor: Colors.teal,
      routeId: AppContentRoutes.expenses,
      destination: (context) => const ExpensesScreen(),
    ),
    ModuleItem(
      icon: Icons.bar_chart,
      title: 'التقارير',
      iconColor: Colors.red,
      routeId: AppContentRoutes.reports(0),
      destination: (context) => const ReportsScreen(initialSection: 0),
    ),
    ModuleItem(
      icon: Icons.people_alt,
      title: 'المستخدمين',
      iconColor: Colors.indigo,
      routeId: AppContentRoutes.users,
      destination: (context) => const UsersScreen(),
      subItems: [
        SubMenuItem(
          title: 'إدارة المستخدمين',
          icon: Icons.manage_accounts_outlined,
          routeId: AppContentRoutes.users,
          destination: (context) => const UsersScreen(),
        ),
        SubMenuItem(
          title: 'ورديات الموظفين (أسبوع)',
          icon: Icons.date_range_rounded,
          routeId: AppContentRoutes.staffShiftsWeek,
          destination: (context) => const StaffShiftsWeekScreen(),
        ),
        SubMenuItem(
          title: 'هويات الموظفين',
          icon: Icons.badge_outlined,
          routeId: AppContentRoutes.employeeIdentity,
          destination: (context) => const EmployeeIdentityScreen(),
        ),
      ],
    ),
    ModuleItem(
      icon: Icons.print,
      title: 'الطباعة',
      iconColor: Colors.blueGrey,
      routeId: AppContentRoutes.printing,
      destination: (context) => const PrintingScreen(),
    ),
  ];

  late List<ModuleItem> _orderedModules;

  // الاختصارات الافتراضية
  List<QuickAction> get _defaultQuickActions => [
    QuickAction(
      icon: Icons.add_circle_outline,
      label: 'البيع',
      routeId: AppContentRoutes.addInvoice,
      breadcrumbTitle: 'بيع جديد',
      destination: (context) => const AddInvoiceScreen(),
    ),
    QuickAction(
      icon: Icons.receipt_long,
      label: 'المرتجعات',
      routeId: AppContentRoutes.invoices,
      breadcrumbTitle: 'الفواتير',
      destination: (context) => const InvoicesScreen(),
    ),
    QuickAction(
      icon: Icons.payment,
      label: 'تسديد قسط',
      routeId: AppContentRoutes.installments,
      breadcrumbTitle: 'الأقساط',
      destination: (context) => const InstallmentsScreen(),
    ),
    QuickAction(
      icon: Icons.search,
      label: 'بحث',
      routeId: 'app_quick_search',
      breadcrumbTitle: 'بحث',
      destination: (context) => const SizedBox(),
    ),
  ];

  // ── Responsive helpers ──────────────────────────────────────────────────────
  double _quickActionSize(double width) {
    if (width >= 900) return 90;
    if (width >= 600) return 80;
    return 70;
  }

  // ── Colours ──────────────────────────────────────────────────────────────────
  // يجب أن تُؤخذ من [Theme] (بعد دمج إعدادات الهوية ولون النص) وليس ألواناً ثابتة.
  Color get _bgColor => Theme.of(context).scaffoldBackgroundColor;
  Color get _surfaceColor => Theme.of(context).colorScheme.surface;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _dividerColor => Theme.of(context).dividerColor;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // تهيئة فورية — تمنع LateInitializationError قبل انتهاء الـ async
    _orderedModules = List.from(_originalModules);
    _nameAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    unawaited(_loadHomeDiskPrefsOnce());
    _searchController.addListener(_onSearchControllerChanged);
    _searchFocusNode.addListener(_onSearchFocusTick);
    CloudSyncService.instance.remoteImportGeneration.addListener(
      _onRemoteSnapshotImported,
    );
    // يؤجّل تحديث المزودين الثقيلة حتى بعد أول إطار + لحظة لتفادي التجمّد مع بناء الرئيسية.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shiftProviderForGateListener = context.read<ShiftProvider>();
      _shiftProviderForGateListener!.addListener(_shiftGateListener);
      unawaited(_ensureActiveShiftGate());
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        if (!mounted) return;
        unawaited(_refreshHomeAuxProviders());
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureActiveShiftGate());
    }
  }

  /// قراءة [SharedPreferences] مرة واحدة لترتيب الوحدات والاختصارات — إعادة رسم واحدة.
  Future<void> _loadHomeDiskPrefsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final savedOrder = prefs.getStringList('modules_order');
    if (savedOrder != null && savedOrder.isNotEmpty) {
      final Map<String, ModuleItem> moduleMap = {
        for (var m in _originalModules) m.title: m,
      };
      final List<ModuleItem> newOrder = [];
      for (final title in savedOrder) {
        if (moduleMap.containsKey(title)) newOrder.add(moduleMap[title]!);
      }
      for (final m in _originalModules) {
        if (!newOrder.contains(m)) newOrder.add(m);
      }
      _orderedModules = newOrder;
    } else {
      _orderedModules = List.from(_originalModules);
    }

    final savedLabels = prefs.getStringList('quick_actions_labels');
    if (savedLabels != null && savedLabels.isNotEmpty) {
      final List<QuickAction> loaded = [];
      for (final label in savedLabels) {
        final module = _originalModules.firstWhere(
          (m) => m.title == label,
          orElse: () => ModuleItem(
            icon: Icons.help,
            title: label,
            iconColor: Colors.grey,
            routeId: 'app_unknown_$label',
            destination: (context) => const SizedBox(),
          ),
        );
        if (_originalModules.contains(module)) {
          loaded.add(
            QuickAction(
              icon: module.icon,
              label: module.title,
              destination: module.destination,
              routeId: module.routeId,
              breadcrumbTitle: module.breadcrumbTitle,
            ),
          );
        } else {
          final def = _defaultQuickActions.firstWhere(
            (q) => q.label == label,
            orElse: () => QuickAction(
              icon: Icons.help,
              label: label,
              routeId: 'app_quick_$label',
              breadcrumbTitle: label,
              destination: (context) => const SizedBox(),
            ),
          );
          loaded.add(def);
        }
      }
      _quickActions = loaded.isNotEmpty
          ? loaded
          : List.from(_defaultQuickActions);
    } else {
      _quickActions = List.from(_defaultQuickActions);
    }

    if (!mounted) return;
    setState(() {});
    await _recomputeNavModules();
  }

  Future<void> _refreshHomeAuxProviders() async {
    if (!mounted) return;
    try {
      await context.read<ParkedSalesProvider>().refresh();
    } catch (_) {}
    if (!mounted) return;
    try {
      await context.read<NotificationProvider>().refresh();
    } catch (_) {}
  }

  /// استيراد لقطة من جهاز آخر (أو مزامنة يدوية): تحديث المزودات المعروضة على الرئيسية.
  void _onRemoteSnapshotImported() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await context.read<ShiftProvider>().refresh();
      } catch (_) {}
      if (!mounted) return;
      if (!context.read<ShiftProvider>().hasOpenShift) {
        Navigator.of(context).pushReplacementNamed('/open-shift');
        return;
      }
      await _refreshHomeAuxProviders();
      if (!mounted) return;
      try {
        await context.read<ProductProvider>().loadProducts(seedIfEmpty: false);
      } catch (_) {}
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _barcodeBridge ??= context.read<GlobalBarcodeRouteBridge>();
    if (!_barcodeBridgeAttached) {
      _barcodeBridgeAttached = true;
      _barcodeBridge!.attach(_applyScannedCode);
      final pending = GlobalBarcodeRouteBridge.takePendingScan();
      if (pending != null && pending.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_applyScannedCode(pending));
          }
        });
      }
    }
    final hideVk = ScreenLayout.of(context).hideInAppSearchKeyboard;
    if (hideVk && _showVirtualSearchKeyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showVirtualSearchKeyboard = false);
      });
    }
  }

  void _onSearchControllerChanged() {
    final v = _searchController.text.toLowerCase();
    if (_searchQuery != v) {
      setState(() => _searchQuery = v);
    }
    _scheduleGlobalSearch();
  }

  @override
  void dispose() {
    if (_barcodeBridgeAttached) {
      _barcodeBridge?.detach();
    }
    WidgetsBinding.instance.removeObserver(this);
    _shiftProviderForGateListener?.removeListener(_shiftGateListener);
    _shiftProviderForGateListener = null;
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onRemoteSnapshotImported,
    );
    _searchDebounce?.cancel();
    _nameAnimController.dispose();
    _searchController.removeListener(_onSearchControllerChanged);
    _searchFocusNode.removeListener(_onSearchFocusTick);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _isDrawerOpen.dispose();
    super.dispose();
  }

  void _onSearchFocusTick() {
    if (_searchFocusNode.hasFocus) {
      VirtualKeyboardController.instance.registerField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onSubmit: _scheduleGlobalSearch,
      );
      return;
    }
    VirtualKeyboardController.instance.unregisterField(_searchFocusNode);
  }

  Future<void> _saveQuickActions() async {
    final prefs = await SharedPreferences.getInstance();
    final labels = _quickActions.map((q) => q.label).toList();
    await prefs.setStringList('quick_actions_labels', labels);
  }

  void _addQuickAction(ModuleItem module) {
    if (_quickActions.any((q) => q.label == module.title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${module.title} موجود بالفعل في الاختصارات'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _quickActions.add(
        QuickAction(
          icon: module.icon,
          label: module.title,
          destination: module.destination,
          routeId: module.routeId,
          breadcrumbTitle: module.breadcrumbTitle,
        ),
      );
      _saveQuickActions();
    });
  }

  void _removeQuickAction(int index) {
    setState(() {
      _quickActions.removeAt(index);
      _saveQuickActions();
      if (_quickActions.isEmpty) {
        _quickActions = List.from(_defaultQuickActions);
        _saveQuickActions();
      }
    });
  }

  void _showAddQuickActionDialog() {
    final availableModules = _originalModules
        .where((module) => !_quickActions.any((q) => q.label == module.title))
        .toList();

    if (availableModules.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('جميع الوحدات مضافة بالفعل'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: ctx.appCorners.lg),
        title: Text(
          'إضافة اختصار سريع',
          style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: availableModules.length,
            itemBuilder: (context, index) {
              final module = availableModules[index];
              return ListTile(
                leading: Icon(module.icon, color: module.iconColor),
                title: Text(
                  module.title,
                  style: TextStyle(color: _textPrimary),
                ),
                onTap: () {
                  _addQuickAction(module);
                  Navigator.pop(ctx);
                },
                shape: RoundedRectangleBorder(borderRadius: ctx.appCorners.md),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'إلغاء',
              style: TextStyle(color: Color(0xFF6C63FF)),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: Text('حذف الاختصار', style: TextStyle(color: _textPrimary)),
        content: Text(
          'هل تريد حذف "${_quickActions[index].label}" من الاختصارات السريعة؟',
          style: TextStyle(color: _textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              _removeQuickAction(index);
              Navigator.pop(ctx);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _animateCompanyName() {
    _nameAnimController.forward().then((_) => _nameAnimController.reverse());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Welcome to NaBoo',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 18,
            height: 1.2,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _isDarkMode
            ? Colors.grey.shade900
            : Colors.grey.shade800,
        shape: RoundedRectangleBorder(borderRadius: context.appCorners.md),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _toggleDrawer() {
    _isDrawerOpen.value = !_isDrawerOpen.value;
    setState(() {});
  }

  /// الاسم في رأس الشريط الجانبي — يفضّل الاسم المعروض ويختصر البريد إن وُجد.
  String _sidebarUserTitle(AuthProvider auth) {
    final dn = auth.displayName.trim();
    if (dn.isNotEmpty) {
      if (dn.contains('@') && !dn.contains(' ')) {
        return dn.split('@').first;
      }
      return dn;
    }
    final u = auth.username.trim();
    if (u.contains('@') && !u.contains(' ')) return u.split('@').first;
    return u.isNotEmpty ? u : 'المستخدم';
  }

  Future<void> _confirmAndLogout(AuthProvider auth) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تسجيل الخروج'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'هل أنت متأكد أنك تريد تسجيل الخروج؟',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('تأكيد'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('إلغاء'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    await auth.logout();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _scheduleGlobalSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _runGlobalSearch();
    });
  }

  bool get _hasActiveSearch => _searchController.text.trim().isNotEmpty;

  void _clearGlobalSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _hitProducts = [];
      _hitCustomers = [];
      _hitUsers = [];
      _hitModules = [];
      _globalSearchLoading = false;
    });
  }

  Future<void> _runGlobalSearch() async {
    final raw = _searchController.text.trim();
    if (raw.isEmpty) {
      if (!mounted) return;
      setState(() {
        _globalSearchLoading = false;
        _hitProducts = [];
        _hitCustomers = [];
        _hitUsers = [];
        _hitModules = [];
      });
      return;
    }
    final invId = tryParseInvoiceIdFromBarcode(raw);
    if (invId != null) {
      if (!mounted) return;
      setState(() {
        _globalSearchLoading = false;
        _hitProducts = [];
        _hitCustomers = [];
        _hitUsers = [];
        _hitModules = [];
      });
      await _offerReturnForScannedInvoiceId(invId);
      return;
    }
    setState(() => _globalSearchLoading = true);
    try {
      final qLower = raw.toLowerCase();
      final results = await Future.wait([
        _productRepo.searchProducts(raw, limit: 25),
        _dbHelper.searchCustomers(raw, limit: 20),
        _dbHelper.searchUsers(raw, limit: 20),
      ]);
      if (!mounted) return;
      final modules = _navForUi
          .where((m) => m.title.toLowerCase().contains(qLower))
          .toList();
      setState(() {
        _hitProducts = results[0];
        _hitCustomers = results[1];
        _hitUsers = results[2];
        _hitModules = modules;
        _globalSearchLoading = false;
      });
    } catch (e, st) {
      debugPrint('global search: $e\n$st');
      if (!mounted) return;
      setState(() => _globalSearchLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إكمال البحث: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// يفتح إضافة منتج **فوق** الشاشة الحالية دون [popUntilContentRoute] —
  /// وإلا عند التبديل إلى `app_add_product` يُفرَّغ المكدس فيُزال «بيع جديد» ومعه مسودة السلة.
  Future<void> _pushAddProductOverlay(String raw) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final route = contentMaterialRoute(
      routeId: AppContentRoutes.addProduct,
      breadcrumbTitle: 'إضافة منتج',
      builder: (_) =>
          AddProductScreen(initialBarcode: raw, autoFillFromScan: true),
    );
    final nav = _contentNavigator;
    if (nav != null) {
      await nav.push<void>(route);
    } else {
      await Navigator.of(context).push<void>(route);
    }
  }

  /// قارئ HID (عالمي)، كاميرا البحث، وغيرهما: بيع سريع أو إضافة منتج.
  Future<void> _applyScannedCode(String scanned) async {
    final raw = scanned.trim();
    if (raw.isEmpty || !mounted) return;

    final invFromReceipt = tryParseInvoiceIdFromBarcode(raw);
    if (invFromReceipt != null) {
      await _offerReturnForScannedInvoiceId(invFromReceipt);
      return;
    }
    final debtCustomerId = tryParseCustomerDebtIdFromScannedText(raw);
    if (debtCustomerId != null) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      await nav.push<void>(
        FastContentPageRoute(
          builder: (_) => CustomerDebtDetailScreen.fromCustomerId(
            registeredCustomerId: debtCustomerId,
          ),
        ),
      );
      return;
    }

    final productProvider = context.read<ProductProvider>();
    final product = await productProvider.findProductByBarcode(raw);
    if (!mounted) return;
    // بعد async: يجب جدولة إطار وإلا قد يتأخر الرسم حتى حدث إدخال (ماوس/لوحة).
    SchedulerBinding.instance.scheduleFrame();
    if (product != null) {
      final draft = context.read<SaleDraftProvider>();
      draft.enqueueProductLine({'barcode': raw});
      if (!draft.isSaleScreenOpen) {
        _pushInContentTagged(
          AppContentRoutes.addInvoice,
          'بيع جديد',
          (_) => const AddInvoiceScreen(),
        );
      }
      return;
    }

    final draft = context.read<SaleDraftProvider>();
    if (draft.isSaleScreenOpen) {
      await _pushAddProductOverlay(raw);
      if (!mounted) return;
      SchedulerBinding.instance.scheduleFrame();
      final afterAdd = await productProvider.findProductByBarcode(raw);
      if (!mounted) return;
      if (afterAdd != null) {
        draft.enqueueProductLine({'barcode': raw});
      }
      return;
    }

    _pushInContentTagged(
      AppContentRoutes.addProduct,
      'إضافة منتج',
      (_) => AddProductScreen(initialBarcode: raw, autoFillFromScan: true),
    );
  }

  NavigatorState? get _contentNavigator =>
      _innerNavKey.currentState ?? _innerNavKeySmall.currentState;

  /// مسارات تُفتح في النافذة العائمة (mac-style) عند تفعيل التفضيل.
  static const Set<String> _macFloatingRouteIds = {
    AppContentRoutes.settings,
    AppContentRoutes.cash,
    AppContentRoutes.installments,
    AppContentRoutes.installmentSettings,
    AppContentRoutes.invoices,
    AppContentRoutes.addInvoice,
    AppContentRoutes.parkedSales,
    AppContentRoutes.salePosSettings,
    AppContentRoutes.users,
    AppContentRoutes.staffShiftsWeek,
    AppContentRoutes.employeeIdentity,
    AppContentRoutes.printing,
    AppContentRoutes.loyaltySettings,
    AppContentRoutes.loyaltyLedger,
    AppContentRoutes.debts,
    AppContentRoutes.debtSettings,
  };

  /// يفتح الشاشة داخل مسار المحتوى مع معرّف ثابت: لا يُكرّر نفس الشاشة في المكدس.
  /// عند تفعيل [MacStyleSettingsPrefs] والمسار ضمن [_macFloatingRouteIds] يُفتح عائماً
  /// على الشاشات العريضة فقط؛ على الهاتف ([ScreenLayout.isHandsetForLayout]) دائماً ملء الشاشة.
  void _pushInContentTagged(
    String routeId,
    String breadcrumbTitle,
    Widget Function(BuildContext) builder, {
    Widget Function(BuildContext)? floatingPageBuilder,
  }) {
    unawaited(
      _pushInContentTaggedAsync(
        routeId,
        breadcrumbTitle,
        builder,
        floatingPageBuilder: floatingPageBuilder,
      ),
    );
  }

  Future<void> _pushInContentTaggedAsync(
    String routeId,
    String breadcrumbTitle,
    Widget Function(BuildContext) builder, {
    Widget Function(BuildContext)? floatingPageBuilder,
  }) async {
    if (!mounted) return;
    // على الهاتف: صفحة كاملة داخل المحتوى — لا نافذة عائمة ضيقة فوق الواجهة.
    if (ScreenLayout.of(context).isHandsetForLayout) {
      _pushInContentTaggedSync(routeId, breadcrumbTitle, builder);
      return;
    }
    final cached = MacStyleSettingsPrefs.cachedValue;
    final useMacPanel =
        cached ?? await MacStyleSettingsPrefs.isMacStylePanelEnabled();
    if (!mounted) return;
    if (useMacPanel && _macFloatingRouteIds.contains(routeId)) {
      final page = floatingPageBuilder ?? builder;
      await showMacStyleFloatingPanel(
        context,
        routeId: routeId,
        windowTitle: breadcrumbTitle,
        pageBuilder: page,
      );
      return;
    }
    _pushInContentTaggedSync(routeId, breadcrumbTitle, builder);
  }

  void _pushInContentTaggedSync(
    String routeId,
    String breadcrumbTitle,
    Widget Function(BuildContext) builder,
  ) {
    // تأجيل الدفع إلى ما بعد إطار الرسم حتى لا يُستدعى push أثناء قفل Navigator
    // (مثلاً من onTap في الشريط الجانبي أثناء معالجة الإيماءة).
    SchedulerBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = _contentNavigator;
      final route = contentMaterialRoute(
        routeId: routeId,
        breadcrumbTitle: breadcrumbTitle,
        builder: (ctx) => builder(ctx),
      );
      if (nav != null) {
        final alreadyThere = popUntilContentRoute(nav, routeId);
        if (!alreadyThere) {
          nav.push(route);
        }
      } else {
        Navigator.of(context).push(route);
      }
    });
  }

  /// يغلق الورقة/الحوار ثم يفتح المسار بعد انتهاء إطار الرسم حتى لا يُستدعى [Navigator.push]
  /// أثناء قفل الـ Navigator (انظر: `!_debugLocked`).
  void _popSheetThenPushInContentTagged(
    String routeId,
    String breadcrumbTitle,
    Widget Function(BuildContext) builder, {
    Widget Function(BuildContext)? floatingPageBuilder,
  }) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pushInContentTagged(
        routeId,
        breadcrumbTitle,
        builder,
        floatingPageBuilder: floatingPageBuilder,
      );
    });
  }

  /// [NavigatorObserver] يستدعي هذا أثناء تركيب الـ Navigator؛ لا يُسمح بـ [setState] هنا مباشرة.
  void _appendBreadcrumbForRoute(Route<dynamic> route) {
    final id = route.settings.name;
    if (id is! String) return;
    final title = breadcrumbTitleForRouteSettings(route.settings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (_breadcrumbTrail.isNotEmpty && _breadcrumbTrail.last.id == id) {
          return;
        }
        if (id == AppContentRoutes.home &&
            _breadcrumbTrail.any((e) => e.id == AppContentRoutes.home)) {
          return;
        }
        _breadcrumbTrail.add(BreadcrumbSegment(id: id, title: title));
      });
    });
  }

  void _removeBreadcrumbForRoute(Route<dynamic> route) {
    final id = route.settings.name;
    if (id is! String) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (_breadcrumbTrail.isEmpty) return;
        if (_breadcrumbTrail.last.id == id) {
          _breadcrumbTrail.removeLast();
          return;
        }
        final idx = _breadcrumbTrail.lastIndexWhere((s) => s.id == id);
        if (idx >= 0) {
          _breadcrumbTrail.removeRange(idx, _breadcrumbTrail.length);
        }
      });
    });
  }

  void _onBreadcrumbSegmentTap(BreadcrumbSegment segment) {
    final nav = _contentNavigator;
    if (nav == null) return;
    nav.popUntil((route) => route.settings.name == segment.id || route.isFirst);
  }

  Widget _buildBreadcrumbStrip() {
    return AppBreadcrumbStrip(
      segments: _breadcrumbTrail,
      onSegmentTap: _onBreadcrumbSegmentTap,
      surfaceColor: _surfaceColor,
      dividerColor: _dividerColor,
      primaryTextColor: _textPrimary,
      secondaryTextColor: _textSecondary,
    );
  }

  /// تثبيت حجم المحتوى: اللوحة تُرسَم فوق الجسم ولا تُصغّر النافذة (مثل سلوك لوحة فوق المحتوى).
  Widget _wrapBodyWithSearchKeyboard(Widget bodyColumn) {
    final hideVk = ScreenLayout.of(context).hideInAppSearchKeyboard;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        // يملأ [Stack] بشكل صريح؛ يمنع قيوداً غير متوقعة على [Column]/[Expanded] داخل المحتوى.
        Positioned.fill(child: bodyColumn),
        if (_showVirtualSearchKeyboard && !hideVk)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SearchVirtualKeyboard(
              controller: _searchController,
              isDark: _isDarkMode,
              onClose: () => setState(() => _showVirtualSearchKeyboard = false),
              onSubmit: () {
                _scheduleGlobalSearch();
                setState(() => _showVirtualSearchKeyboard = false);
                if (mounted) FocusScope.of(context).unfocus();
              },
            ),
          ),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return LayoutBuilder(
          builder: (outerCtx, outerConstraints) {
            // ≥800dp: شريط جانبي + محتوى (بدون شريط سفلي). أضيق: شريط سفلي فقط بدون عمود جانبي.
            const kWideBreakpoint = 800.0;
            final isLarge = outerConstraints.maxWidth >= kWideBreakpoint;

            // ── LARGE SCREEN: persistent sidebar + nested Navigator ──────────
            if (isLarge) {
              return PopScope(
                canPop: false,
                onPopInvokedWithResult: (didPop, _) {
                  if (_innerNavKey.currentState?.canPop() ?? false) {
                    _innerNavKey.currentState!.pop();
                  }
                },
                child: Scaffold(
                  resizeToAvoidBottomInset: false,
                  backgroundColor: _bgColor,
                  appBar: _buildAppBar(themeProvider),
                  body: _wrapBodyWithSearchKeyboard(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildBreadcrumbStrip(),
                        Expanded(
                          child: Row(
                            children: [
                              ValueListenableBuilder<bool>(
                                valueListenable: _isDrawerOpen,
                                builder: (_, isOpen, _) {
                                  const double collapsedW = 56.0;
                                  const double expandedW = 220.0;
                                  final sideW = isOpen ? expandedW : collapsedW;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 240),
                                    curve: Curves.easeInOut,
                                    width: sideW,
                                    child: _buildPersistentSidebar(isOpen),
                                  );
                                },
                              ),
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  clipBehavior: Clip.none,
                                  children: [
                                    SizedBox.expand(
                                      child: Navigator(
                                        key: _innerNavKey,
                                        restorationScopeId:
                                            'home_inner_nav_main',
                                        observers: [_innerNavObserver],
                                        onGenerateInitialRoutes: (_, _) => [
                                          FastContentPageRoute(
                                            settings: const RouteSettings(
                                              name: AppContentRoutes.home,
                                              arguments: BreadcrumbMeta(
                                                'الرئيسية',
                                              ),
                                            ),
                                            builder: (_) => _HomeContentPage(
                                              parentState: this,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_hasActiveSearch) ...[
                                      Positioned.fill(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _clearGlobalSearch,
                                          child: Container(
                                            color: Colors.black.withValues(
                                              alpha: 0.4,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        right: 0,
                                        child: _buildSearchOverlayDropdown(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // ── NARROW SCREEN: شريط سفلي للوحدات فقط — بدون عمود جانبي (هاتف/نافذة ضيقة) ─
            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (_innerNavKeySmall.currentState?.canPop() ?? false) {
                  _innerNavKeySmall.currentState!.pop();
                }
              },
              child: Scaffold(
                resizeToAvoidBottomInset: false,
                backgroundColor: _bgColor,
                appBar: _buildAppBar(themeProvider),
                body: _wrapBodyWithSearchKeyboard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // مسار التنقل يُعرض على الشاشات العريضة فقط (≥800dp)؛ على الهاتف/النافذة الضيقة لا حاجة له.
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.none,
                          children: [
                            SizedBox.expand(
                              child: Navigator(
                                key: _innerNavKeySmall,
                                restorationScopeId: 'home_inner_nav_small',
                                observers: [_innerNavObserver],
                                onGenerateInitialRoutes: (_, _) => [
                                  FastContentPageRoute(
                                    settings: const RouteSettings(
                                      name: AppContentRoutes.home,
                                      arguments: BreadcrumbMeta('الرئيسية'),
                                    ),
                                    builder: (_) =>
                                        _HomeContentPage(parentState: this),
                                  ),
                                ],
                              ),
                            ),
                            if (_hasActiveSearch) ...[
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _clearGlobalSearch,
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                left: 0,
                                right: 0,
                                child: _buildSearchOverlayDropdown(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: _buildBottomNavBar(_navForUi),
              ),
            );
          },
        );
      },
    );
  }

  /// أزرار شريط التطبيق العلوي — تتبع [AppCornerStyle] (خلفية وحواف عند «مستدير»).
  ButtonStyle _homeAppBarActionStyle({Color? foreground}) {
    final ac = context.appCorners;
    final onPrimary = foreground ?? Theme.of(context).colorScheme.onPrimary;
    if (!ac.isRounded) {
      return IconButton.styleFrom(foregroundColor: onPrimary);
    }
    return IconButton.styleFrom(
      foregroundColor: onPrimary,
      backgroundColor: onPrimary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: ac.sm,
        side: BorderSide(color: onPrimary.withValues(alpha: 0.35), width: 1),
      ),
      padding: const EdgeInsets.all(4),
      minimumSize: const Size(36, 36),
    );
  }

  /// فاصل رأسي خفيف بين مجموعات أزرار شريط التطبيق (على الشاشات العريضة).
  Widget _appBarDivider() {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: onPrimary.withValues(alpha: 0.28),
      ),
    );
  }

  Widget _appBarShiftButton() {
    return Consumer<ShiftProvider>(
      builder: (context, shift, _) {
        if (!shift.hasOpenShift) return const SizedBox.shrink();
        final label = shift.activeShift?['shiftStaffName'] as String?;
        return IconButton(
          style: _homeAppBarActionStyle(),
          icon: const Icon(Icons.event_available_outlined, size: 20),
          tooltip: label != null && label.isNotEmpty
              ? 'وردية: $label — إغلاق'
              : 'إغلاق الوردية',
          onPressed: () => showCloseShiftDialog(context),
        );
      },
    );
  }

  Widget _appBarUserButton(AuthProvider auth) {
    return IconButton(
      style: _homeAppBarActionStyle(),
      icon: const Icon(Icons.person_outline_rounded, size: 20),
      onPressed: () => _showUserInfoDialog(auth),
      tooltip: auth.username.isNotEmpty ? auth.username : 'مستخدم',
    );
  }

  Widget _appBarNotifButton() {
    return Consumer<NotificationProvider>(
      builder: (context, notif, _) {
        final c = notif.unreadCount;
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            IconButton(
              style: _homeAppBarActionStyle(),
              icon: const Icon(Icons.notifications_outlined, size: 20),
              onPressed: () => showAppNotificationsSheet(
                context,
                contentNavigator: _contentNavigator,
              ),
              tooltip: 'التنبيهات',
            ),
            if (c > 0)
              PositionedDirectional(
                end: 6,
                top: 6,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _appBarCalculatorButton() {
    return IconButton(
      style: _homeAppBarActionStyle(),
      icon: const Icon(Icons.calculate_rounded, size: 20),
      onPressed: () => showFloatingCalculator(context),
      tooltip: 'حاسبة',
    );
  }

  Widget _appBarSettingsButton() {
    return IconButton(
      style: _homeAppBarActionStyle(),
      icon: const Icon(Icons.settings_rounded, size: 20),
      onPressed: () => _pushInContentTagged(
        AppContentRoutes.settings,
        'الإعدادات',
        (_) => const SettingsScreen(),
        floatingPageBuilder: (_) => const SettingsScreen(showAppBar: false),
      ),
      tooltip: 'الإعدادات',
    );
  }

  Widget _appBarEditButton() {
    return IconButton(
      style: _homeAppBarActionStyle(
        foreground: _isEditMode ? const Color(0xFF86EFAC) : null,
      ),
      icon: Icon(_isEditMode ? Icons.check : Icons.edit, size: 18),
      onPressed: () => setState(() => _isEditMode = !_isEditMode),
      tooltip: _isEditMode ? 'إنهاء التحرير' : 'تخصيص الاختصارات',
    );
  }

  /// على الهاتف والعروض الضيقة: أيقونة «المزيد» بدل صف طويل من الأزرار.
  Widget _appBarOverflowMenu(ThemeProvider themeProvider) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      style: _homeAppBarActionStyle(),
      icon: const Icon(Icons.more_horiz_rounded, size: 22),
      tooltip: 'المزيد',
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      onSelected: (value) {
        switch (value) {
          case 'calc':
            showFloatingCalculator(context);
            break;
          case 'settings':
            _pushInContentTagged(
              AppContentRoutes.settings,
              'الإعدادات',
              (_) => const SettingsScreen(),
              floatingPageBuilder: (_) =>
                  const SettingsScreen(showAppBar: false),
            );
            break;
          case 'edit':
            setState(() => _isEditMode = !_isEditMode);
            break;
          case 'theme':
            themeProvider.toggleDarkMode();
            setState(() {});
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'calc',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.calculate_rounded, color: cs.onSurface),
            title: const Text('حاسبة'),
          ),
        ),
        PopupMenuItem(
          value: 'settings',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_rounded, color: cs.onSurface),
            title: const Text('الإعدادات'),
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _isEditMode ? Icons.check_rounded : Icons.edit_rounded,
              color: cs.onSurface,
            ),
            title: Text(
              _isEditMode ? 'إنهاء تخصيص الاختصارات' : 'تخصيص الاختصارات',
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              themeProvider.isDarkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              color: cs.onSurface,
            ),
            title: Text(
              themeProvider.isDarkMode ? 'الوضع النهاري' : 'الوضع الليلي',
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAppBarActions(
    ThemeProvider themeProvider,
    AuthProvider auth,
  ) {
    final sl = ScreenLayout.of(context);
    final w = MediaQuery.sizeOf(context).width;
    // على نوافذ ضيقة (حتى مع عرض الجذر ≥800dp) مساحة أزرار AppBar قد لا تكفي —
    // نستخدم قائمة التجاوز مبكراً لتفادي overflow أفقي.
    final compact = sl.isHandsetForLayout || w < 960;

    if (compact) {
      return [
        _appBarShiftButton(),
        _appBarNotifButton(),
        _appBarUserButton(auth),
        _appBarOverflowMenu(themeProvider),
      ];
    }

    return [
      _appBarShiftButton(),
      _appBarDivider(),
      _appBarUserButton(auth),
      _appBarNotifButton(),
      _appBarDivider(),
      _appBarCalculatorButton(),
      _appBarSettingsButton(),
      _appBarEditButton(),
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 6, start: 2),
        child: _buildDarkModeToggle(themeProvider),
      ),
    ];
  }

  // ── AppBar ──────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(ThemeProvider themeProvider) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final sl = ScreenLayout.of(context);
    final ac = context.appCorners;
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      shape: ac.isRounded
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(ac.rLg),
              ),
            )
          : null,
      title: _buildZorahTitle(),
      actions: _buildAppBarActions(themeProvider, auth),
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(sl.appBarSearchSectionHeight),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            sl.pageHorizontalGap,
            4,
            sl.pageHorizontalGap,
            sl.isCompactHeight ? 6 : 10,
          ),
          child: _buildSearchBar(),
        ),
      ),
    );
  }

  Widget _buildZorahTitle() {
    final sl = ScreenLayout.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth.isFinite ? c.maxWidth : 280.0;
        return GestureDetector(
          onTap: _animateCompanyName,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxW.clamp(48.0, 400.0),
                  ),
                  child: AppBrandMark(
                    title: 'naboo',
                    logoSize: sl.isNarrowWidth ? 34 : 38,
                    gap: sl.isNarrowWidth ? 8 : 10,
                    borderColor: const Color(0xFFB8960C),
                    borderWidth: 1.6,
                    showTitle: false,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showUserInfoDialog(AuthProvider auth) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final mq = MediaQuery.sizeOf(ctx);
        final dialogW = math.min(400.0, mq.width - 48);
        const goldClose = Color(0xFFF5C518);

        Widget row(
          String label,
          String value, {
          bool ltrValue = false,
          bool allowCopy = true,
        }) {
          final trimmed = label.endsWith(':')
              ? label.substring(0, label.length - 1)
              : label;
          final show = '$trimmed:';

          Widget valueWidget() {
            if (ltrValue && value.isNotEmpty && value != '—') {
              return SelectableText(
                value,
                textAlign: TextAlign.right,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              );
            }
            return SelectableText(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            );
          }

          return Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 2,
              end: 2,
              bottom: 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(flex: 3, child: valueWidget()),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 118,
                        child: Text(
                          show,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: _textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'نسخ',
                  visualDensity: VisualDensity.compact,
                  onPressed: allowCopy && value.isNotEmpty && value != '—'
                      ? () async {
                          await Clipboard.setData(ClipboardData(text: value));
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('تم النسخ'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      : null,
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 20,
                    color: allowCopy && value.isNotEmpty && value != '—'
                        ? AppColors.primary
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        return Center(
          child: SizedBox(
            width: dialogW,
            child: AlertDialog(
              backgroundColor: _surfaceColor,
              shape: RoundedRectangleBorder(borderRadius: ctx.appCorners.lg),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              title: Row(
                textDirection: TextDirection.rtl,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFF6366F1),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'بيانات المستخدم',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(color: _dividerColor),
                    const SizedBox(height: 6),
                    row(
                      'الاسم المعروض:',
                      auth.displayName.isNotEmpty ? auth.displayName : '—',
                    ),
                    row(
                      'اسم الدخول:',
                      auth.username.isNotEmpty ? auth.username : '—',
                    ),
                    row('الصلاحية:', auth.role.isNotEmpty ? auth.role : '—'),
                    row(
                      'البريد الإلكتروني:',
                      auth.email.isNotEmpty ? auth.email : '—',
                      ltrValue: true,
                    ),
                    Divider(color: _dividerColor),
                  ],
                ),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'إغلاق',
                    style: TextStyle(
                      color: goldClose,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDarkModeToggle(ThemeProvider themeProvider) {
    final ac = context.appCorners;
    return GestureDetector(
      onTap: () {
        themeProvider.toggleDarkMode();
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: 48,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: ac.radius(13),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.45),
            width: 1,
          ),
          color: _isDarkMode
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.22),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 5,
              child: Icon(
                Icons.wb_sunny_rounded,
                size: 13,
                color: _isDarkMode ? Colors.white54 : Colors.orange,
              ),
            ),
            Positioned(
              right: 5,
              child: Icon(
                Icons.nights_stay_rounded,
                size: 12,
                color: _isDarkMode ? Colors.white : Colors.grey.shade500,
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: _isDarkMode
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: ac.radius(10),
                    border: Border.all(color: Colors.black12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// أيقونات حقل البحث (باركود، لوحة مفاتيح، مسح) — نفس منطق الزوايا عند «مستدير».
  ButtonStyle? _searchBarSuffixIconStyle(Color iconColor) {
    final ac = context.appCorners;
    if (!ac.isRounded) return null;
    return IconButton.styleFrom(
      foregroundColor: iconColor,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      minimumSize: const Size(36, 36),
      shape: RoundedRectangleBorder(
        borderRadius: ac.sm,
        side: BorderSide(color: iconColor.withValues(alpha: 0.45), width: 1),
      ),
    );
  }

  Widget _buildSearchBarSuffixRow(Color iconInField, bool hideVk) {
    final sl = ScreenLayout.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final collapse = sl.isHandsetForLayout && w < 400 && !hideVk;

    final barcodeBtn = IconButton(
      style: _searchBarSuffixIconStyle(iconInField),
      tooltip:
          'قراءة باركود (كاميرا على الجهاز المحمول، أو نافذة القارئ على الحاسوب)',
      icon: Icon(Icons.qr_code_scanner_rounded, color: iconInField, size: 21),
      onPressed: _scanFromDashboardSearch,
    );

    final keyboardBtn = IconButton(
      style: _searchBarSuffixIconStyle(iconInField),
      tooltip: _showVirtualSearchKeyboard
          ? 'إخفاء لوحة المفاتيح'
          : 'لوحة مفاتيح عربي / English — اسحب من المقبض أو ثبّتها بالدبوس',
      icon: Icon(
        _showVirtualSearchKeyboard
            ? Icons.keyboard_hide_rounded
            : Icons.keyboard_rounded,
        color: iconInField,
        size: 21,
      ),
      onPressed: () {
        setState(() {
          _showVirtualSearchKeyboard = !_showVirtualSearchKeyboard;
        });
        if (_showVirtualSearchKeyboard) {
          _searchFocusNode.requestFocus();
        }
      },
    );

    final clearBtn = _searchQuery.isNotEmpty
        ? IconButton(
            style: _searchBarSuffixIconStyle(iconInField),
            tooltip: 'مسح البحث',
            icon: Icon(Icons.clear_rounded, color: iconInField, size: 20),
            onPressed: _clearGlobalSearch,
          )
        : null;

    if (!collapse) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [barcodeBtn, if (!hideVk) keyboardBtn, ?clearBtn],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        barcodeBtn,
        PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          tooltip: 'أدوات البحث',
          color: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          icon: Icon(Icons.tune_rounded, color: iconInField, size: 20),
          onSelected: (value) {
            if (value != 'kb') return;
            setState(() {
              _showVirtualSearchKeyboard = !_showVirtualSearchKeyboard;
            });
            if (_showVirtualSearchKeyboard) {
              _searchFocusNode.requestFocus();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'kb',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _showVirtualSearchKeyboard
                      ? Icons.keyboard_hide_rounded
                      : Icons.keyboard_rounded,
                ),
                title: Text(
                  _showVirtualSearchKeyboard
                      ? 'إخفاء لوحة المفاتيح'
                      : 'إظهار لوحة المفاتيح (عربي / English)',
                ),
              ),
            ),
          ],
        ),
        ?clearBtn,
      ],
    );
  }

  Widget _buildSearchBar() {
    final sl = ScreenLayout.of(context);
    final ac = context.appCorners;
    final hideVk = sl.hideInAppSearchKeyboard;
    final iconInField = _textSecondary;
    final w = MediaQuery.sizeOf(context).width;
    final shortHint = sl.isHandsetForLayout && w < 400;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        readOnly:
            _showVirtualSearchKeyboard &&
            !hideVk &&
            VirtualKeyboardController.instance.isPinned,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _scheduleGlobalSearch(),
        style: TextStyle(color: _textPrimary),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search_rounded, color: iconInField, size: 22),
          suffixIcon: _buildSearchBarSuffixRow(iconInField, hideVk),
          suffixIconConstraints: const BoxConstraints(
            minHeight: 48,
            maxHeight: 52,
          ),
          hintText: shortHint
              ? 'بحث سريع: وحدات، منتجات، عملاء…'
              : 'بحث: وحدات، منتجات، عملاء، موظفون، باركود…',
          hintStyle: TextStyle(
            color: _textSecondary,
            fontSize: sl.isNarrowWidth ? 12 : 13,
          ),
          isDense: true,
          filled: true,
          fillColor: _isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          border: OutlineInputBorder(
            borderRadius: ac.lg,
            borderSide: BorderSide(
              color: _isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: ac.lg,
            borderSide: BorderSide(
              color: _isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: ac.lg,
            borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
          ),
          contentPadding: EdgeInsets.symmetric(
            vertical: sl.isCompactHeight ? 8 : 10,
            horizontal: sl.isNarrowWidth ? 4 : 8,
          ),
        ),
      ),
    );
  }

  String _invoiceTypeAr(InvoiceType t) {
    switch (t) {
      case InvoiceType.cash:
        return 'نقدي';
      case InvoiceType.credit:
        return 'دين';
      case InvoiceType.installment:
        return 'تقسيط';
      case InvoiceType.delivery:
        return 'توصيل';
      case InvoiceType.debtCollection:
        return 'تحصيل دين';
      case InvoiceType.installmentCollection:
        return 'تسديد قسط';
      case InvoiceType.supplierPayment:
        return 'دفع مورد';
    }
  }

  Future<void> _offerReturnForScannedInvoiceId(int id) async {
    final inv = await _dbHelper.getInvoiceById(id);
    if (!mounted) return;
    if (inv == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('لا توجد فاتورة برقم $id')));
      return;
    }
    if (inv.isReturned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الفاتورة مسجّلة كمرتجع مسبقاً')),
      );
      return;
    }
    if (inv.type == InvoiceType.debtCollection ||
        inv.type == InvoiceType.installmentCollection ||
        inv.type == InvoiceType.supplierPayment) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هذا السند لا يُفتَح كمرتجع بيع — عكس الدفعة من شاشة المورد أو إدارة الأقساط حسب النوع.',
          ),
        ),
      );
      return;
    }
    final go =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('فاتورة بيع #${inv.id}'),
            content: Text(
              'العميل: ${inv.customerName.trim().isEmpty ? '(فارغ)' : inv.customerName}\n'
              'الدفع: ${_invoiceTypeAr(inv.type)}\n'
              'الإجمالي: ${IraqiCurrencyFormat.formatIqd(inv.total)}\n\n'
              'فتح شاشة المرتجع؟ يمكنك تقليل الكمية أو حذف الأسطر لإرجاع جزئي فقط.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('مرتجع'),
              ),
            ],
          ),
        ) ??
        false;
    if (!go || !mounted) return;
    final rid = inv.id ?? id;
    _pushInContentTagged(
      AppContentRoutes.processReturn(rid),
      'مرتجع #$rid',
      (_) => ProcessReturnScreen(originalInvoice: inv),
    );
  }

  Future<void> _scanFromDashboardSearch() async {
    final code = await BarcodeInputLauncher.captureBarcode(
      context,
      title: 'مسح QR / Barcode',
    );
    if (!mounted || code == null || code.trim().isEmpty) return;
    await _applyScannedCode(code.trim());
  }

  // ── الشريط الجانبي الثابت ──────────────────────────────────────────────────
  Widget _buildPersistentSidebar(bool isExpanded) {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    void navToTagged(
      String routeId,
      String breadcrumbTitle,
      Widget Function(BuildContext) destination,
    ) {
      _pushInContentTagged(routeId, breadcrumbTitle, destination);
    }

    // قائمة العناصر في الشريط الجانبي
    final sidebarItems = [
      ..._navForUi.map(
        (module) => _SidebarItem(
          icon: module.icon,
          title: module.title,
          iconColor: module.iconColor,
          subItems: module.subItems
              ?.map(
                (s) => _SubItem(
                  title: s.title,
                  icon: s.icon,
                  onTap: () =>
                      navToTagged(s.routeId, s.breadcrumbTitle, s.destination),
                ),
              )
              .toList(),
          onTap: () => navToTagged(
            module.routeId,
            module.breadcrumbTitle,
            module.destination,
          ),
        ),
      ),
      _SidebarItem(
        icon: Icons.logout,
        title: 'تسجيل الخروج',
        iconColor: Colors.red,
        onTap: () => _confirmAndLogout(auth),
      ),
    ];

    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final sl = ScreenLayout.of(context);
    final sidebarBg = _isDarkMode
        ? Color.lerp(cs.primary, Colors.black, 0.45)!
        : cs.primary;
    final panelCurve = Radius.circular(ac.isRounded ? ac.rLg + 10 : 0);

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: panelCurve,
        bottomLeft: panelCurve,
      ),
      child: Container(
        color: sidebarBg,
        child: Column(
          children: [
            // ── زر التوسيع/الطي ──
            SizedBox(
              height: 56,
              child: Tooltip(
                message: isExpanded ? 'طي القائمة' : 'توسيع القائمة',
                child: IconButton(
                  padding: const EdgeInsets.all(10),
                  style: IconButton.styleFrom(foregroundColor: cs.onPrimary),
                  onPressed: _toggleDrawer,
                  icon: const Icon(Icons.menu_rounded, size: 22),
                ),
              ),
            ),

            // ── اسم الشركة (عند التوسع) ──
            if (isExpanded)
              Container(
                width: double.infinity,
                padding: EdgeInsetsDirectional.only(
                  start: sl.pageHorizontalGap,
                  end: sl.pageHorizontalGap,
                  top: 8,
                  bottom: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sidebarUserTitle(auth),
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      auth.role.isNotEmpty ? auth.role : 'NaBoo',
                      style: TextStyle(
                        color: cs.onPrimary.withValues(alpha: 0.72),
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

            Divider(
              color: cs.onPrimary.withValues(alpha: 0.18),
              height: 1,
              thickness: 1,
            ),

            // ── قائمة الوحدات ──
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: sidebarItems.length,
                itemBuilder: (context, index) {
                  final isModule = index < _navForUi.length;
                  final isActive = isModule && _activeBottomIndex == index;
                  // فاصل قبل تسجيل الخروج
                  if (index == sidebarItems.length - 1) {
                    return Column(
                      children: [
                        Divider(
                          color: cs.onPrimary.withValues(alpha: 0.18),
                          height: 16,
                          thickness: 1,
                        ),
                        if (isExpanded)
                          SidebarLogoutPill(
                            colorScheme: cs,
                            label: 'تسجيل الخروج',
                            onTap: () => _confirmAndLogout(auth),
                          )
                        else
                          _buildSidebarItem(
                            sidebarItems[index],
                            isExpanded,
                            isActive: false,
                          ),
                      ],
                    );
                  }
                  return _buildSidebarItem(
                    sidebarItems[index],
                    isExpanded,
                    isActive: isActive,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    _SidebarItem item,
    bool isExpanded, {
    required bool isActive,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hasSubmenu = item.subItems != null && item.subItems!.isNotEmpty;
    final isSubmenuOpen = _expandedSubmenus.contains(item.title);

    return Column(
      children: [
        Tooltip(
          message: isExpanded ? '' : item.title,
          preferBelow: false,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              splashColor: cs.onPrimary.withValues(alpha: 0.14),
              highlightColor: cs.onPrimary.withValues(alpha: 0.07),
              onTap: () {
                if (hasSubmenu) {
                  setState(() {
                    if (isSubmenuOpen) {
                      _expandedSubmenus.remove(item.title);
                    } else {
                      _expandedSubmenus.add(item.title);
                      // افتح الشريط إذا كان مطوياً
                      if (!_isDrawerOpen.value) _isDrawerOpen.value = true;
                    }
                  });
                } else {
                  item.onTap();
                }
              },
              child: SizedBox(
                height: 48,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canShowExpanded =
                        isExpanded &&
                        constraints.hasBoundedWidth &&
                        constraints.maxWidth >= 140;

                    if (!canShowExpanded) {
                      return Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive
                                ? cs.surface.withValues(alpha: 0.95)
                                : Colors.transparent,
                            border: isActive
                                ? Border.all(
                                    color: cs.onPrimary.withValues(alpha: 0.35),
                                  )
                                : null,
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: cs.shadow.withValues(alpha: 0.2),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            item.icon,
                            color: isActive ? cs.primary : item.iconColor,
                            size: 22,
                          ),
                        ),
                      );
                    }

                    final row = Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: isActive ? 2 : 4,
                        end: 12,
                      ),
                      child: Row(
                        children: [
                          AnimatedScale(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            scale: isActive ? 1.06 : 1.0,
                            child: Icon(
                              item.icon,
                              color: item.iconColor.withValues(
                                alpha: isActive ? 1.0 : 0.85,
                              ),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                color: isActive ? cs.onSurface : cs.onPrimary,
                                fontSize: 13,
                                fontWeight: isActive
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (hasSubmenu)
                            AnimatedRotation(
                              turns: isSubmenuOpen ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                color: isActive
                                    ? cs.onSurface.withValues(alpha: 0.55)
                                    : cs.onPrimary.withValues(alpha: 0.65),
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    );

                    if (isActive) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Material(
                          color: cs.surface.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(12),
                          child: row,
                        ),
                      );
                    }
                    return row;
                  },
                ),
              ),
            ),
          ),
        ),
        // القائمة الفرعية (مثل توسيع قسم العملاء / المخزون)
        if (hasSubmenu && isSubmenuOpen && isExpanded)
          Container(
            width: double.infinity,
            color: cs.onPrimary.withValues(alpha: 0.1),
            child: Column(
              children: [
                for (final e in item.subItems!.asMap().entries) ...[
                  if (e.key > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.onPrimary.withValues(alpha: 0.12),
                    ),
                  InkWell(
                    onTap: e.value.onTap,
                    splashColor: cs.onPrimary.withValues(alpha: 0.12),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 14, left: 10),
                      child: SizedBox(
                        height: 40,
                        child: Row(
                          children: [
                            if (e.value.icon != null) ...[
                              Icon(
                                e.value.icon,
                                size: 17,
                                color: cs.onPrimary.withValues(alpha: 0.88),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                e.value.title,
                                style: TextStyle(
                                  color: cs.onPrimary.withValues(alpha: 0.95),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// إضافة صنف لبيع جديد من البحث أو من عمود المنتجات على الشاشات العريضة.
  void _handleProductQuickPick(Map<String, dynamic> p) {
    final draft = context.read<SaleDraftProvider>();
    final line = <String, dynamic>{
      'name': p['name'],
      'sell': p['sell'],
      'minSell': p['minSell'],
      'productId': p['id'],
      'trackInventory': p['trackInventory'],
      'allowNegativeStock': p['allowNegativeStock'],
      'qty': p['qty'],
      'stockBaseKind': p['stockBaseKind'],
      'defaultVariantId': p['defaultVariantId'],
      'defaultUnitFactor': p['defaultUnitFactor'],
      'defaultUnitLabel': p['defaultUnitLabel'],
    };
    if (!draft.isSaleScreenOpen) {
      _pushInContentTagged(
        AppContentRoutes.addInvoice,
        'بيع جديد',
        (_) => const AddInvoiceScreen(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        draft.enqueueProductLine(line);
        _clearGlobalSearch();
      });
    } else {
      draft.enqueueProductLine(line);
      _clearGlobalSearch();
    }
  }

  // ── Main content (مع شريط الاختصارات القابل للتخصيص) ──────────────────────
  Widget _buildMainContent(double availableWidth) {
    final qSize = _quickActionSize(availableWidth);

    final dashboard = DashboardView(
      isDark: _isDarkMode,
      onPinnedProductQuickSale: (preset) {
        _pushInContentTagged(
          AppContentRoutes.addInvoice,
          'بيع جديد',
          (_) => AddInvoiceScreen(presetProductLine: preset),
        );
      },
      onGlanceAction: (action) {
        switch (action) {
          case HomeGlanceAction.cash:
            _pushInContentTagged(
              AppContentRoutes.cash,
              'الصندوق',
              (_) => const CashScreen(),
            );
            break;
          case HomeGlanceAction.newSale:
            _pushInContentTagged(
              AppContentRoutes.addInvoice,
              'بيع جديد',
              (_) => const AddInvoiceScreen(),
            );
            break;
          case HomeGlanceAction.inventoryProducts:
            _pushInContentTagged(
              AppContentRoutes.inventoryProducts,
              'الأصناف',
              (_) => const InventoryProductsScreen(),
            );
            break;
          case HomeGlanceAction.parkedSales:
            _pushInContentTagged(
              AppContentRoutes.parkedSales,
              'معلّقة مؤقتاً',
              (_) => const ParkedSalesScreen(),
            );
            break;
          case HomeGlanceAction.reportsExecutive:
            _pushInContentTagged(
              AppContentRoutes.reports(0),
              'التقارير',
              (_) => const ReportsScreen(initialSection: 0),
            );
            break;
          case HomeGlanceAction.completedOrders:
            _pushInContentTagged(
              AppContentRoutes.invoices,
              'الفواتير',
              (_) => const InvoicesScreen(),
            );
            break;
        }
      },
      onRecentActivity: (entry) async {
        if (!mounted) return;
        switch (entry.kind) {
          case RecentActivityKind.invoice:
            final id = entry.invoiceId;
            if (id != null) {
              await showInvoiceDetailSheet(context, DatabaseHelper(), id);
            }
            break;
          case RecentActivityKind.cashMovement:
            final link = entry.linkedInvoiceId;
            if (link != null) {
              await showInvoiceDetailSheet(context, DatabaseHelper(), link);
            } else {
              _pushInContentTagged(
                AppContentRoutes.cash,
                'الصندوق',
                (_) => const CashScreen(),
              );
            }
            break;
          case RecentActivityKind.parkedSale:
            _pushInContentTagged(
              AppContentRoutes.parkedSales,
              'معلّقة مؤقتاً',
              (_) => const ParkedSalesScreen(),
            );
            break;
          case RecentActivityKind.loyalty:
            final inv = entry.linkedInvoiceId;
            if (inv != null) {
              await showInvoiceDetailSheet(context, DatabaseHelper(), inv);
            } else {
              _pushInContentTagged(
                AppContentRoutes.loyaltyLedger,
                'سجل النقاط',
                (_) => const LoyaltyLedgerScreen(),
              );
            }
            break;
          case RecentActivityKind.stockVoucher:
            _pushInContentTagged(
              AppContentRoutes.inventory,
              'المخزون',
              (_) => const InventoryHubScreen(),
            );
            break;
          case RecentActivityKind.customerCreated:
            _pushInContentTagged(
              AppContentRoutes.customers,
              'العملاء',
              (_) => const CustomersScreen(),
            );
            break;
          case RecentActivityKind.productCreated:
            _pushInContentTagged(
              AppContentRoutes.inventoryProducts,
              'الأصناف',
              (_) => const InventoryProductsScreen(),
            );
            break;
          case RecentActivityKind.workShift:
            _pushInContentTagged(
              AppContentRoutes.staffShiftsWeek,
              'ورديات الموظفين',
              (_) => const StaffShiftsWeekScreen(),
            );
            break;
        }
      },
      onOpenInvoicesFromActivity: () => _pushInContentTagged(
        AppContentRoutes.invoices,
        'الفواتير',
        (_) => const InvoicesScreen(),
      ),
      onOpenCashFromActivity: () => _pushInContentTagged(
        AppContentRoutes.cash,
        'الصندوق',
        (_) => const CashScreen(),
      ),
    );

    return Column(
      children: [
        Consumer<ShiftProvider>(
          builder: (context, shift, _) {
            final row = shift.activeShift;
            final raw = row?['shiftStaffUserId'];
            if (raw == null) return const SizedBox.shrink();
            final name = (row!['shiftStaffName'] as String?)?.trim() ?? '';
            final label = name.isEmpty ? 'موظف الوردية' : name;
            final gap = ScreenLayout.of(context).pageHorizontalGap;
            return Material(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.55),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: gap,
                  vertical: 8,
                ),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'صلاحيات التشغيل مرتبطة بموظف الوردية: $label',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        _buildQuickActionsBar(qSize),
        Divider(height: 1, thickness: 1, color: _dividerColor),
        Expanded(child: dashboard),
      ],
    );
  }

  /// نتائج البحث تظهر تحت شريط البحث مباشرة (فوق المحتوى) بقوائم أفقية لكل قسم.
  Widget _buildSearchOverlayDropdown() {
    final maxH = MediaQuery.sizeOf(context).height * 0.55;
    return Material(
      elevation: 12,
      color: _surfaceColor,
      shadowColor: Colors.black45,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: _globalSearchLoading
              ? const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _buildSearchOverlayScrollable(),
        ),
      ),
    );
  }

  Widget _buildSearchOverlayScrollable() {
    final sl = ScreenLayout.of(context);
    final hasAny =
        _hitModules.isNotEmpty ||
        _hitProducts.isNotEmpty ||
        _hitCustomers.isNotEmpty ||
        _hitUsers.isNotEmpty;
    if (!hasAny) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: sl.pageHorizontalGap,
          vertical: 20,
        ),
        child: Text(
          'لا توجد نتائج لـ «${_searchController.text.trim()}»',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.4),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.only(
        start: sl.pageHorizontalGap,
        end: sl.pageHorizontalGap,
        top: 12,
        bottom: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hitModules.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'الوحدات',
              count: _hitModules.length,
              height: 92,
              itemCount: _hitModules.length,
              itemBuilder: (i) {
                final m = _hitModules[i];
                return _searchHChip(
                  onTap: () {
                    _clearGlobalSearch();
                    _pushInContentTagged(
                      m.routeId,
                      m.breadcrumbTitle,
                      m.destination,
                    );
                  },
                  icon: m.icon,
                  iconColor: m.iconColor,
                  title: m.title,
                  subtitle: 'فتح الوحدة',
                );
              },
            ),
          if (_hitProducts.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'المنتجات',
              count: _hitProducts.length,
              height: 128,
              itemCount: _hitProducts.length,
              itemBuilder: (i) {
                final p = _hitProducts[i];
                final sellRaw = p['sell'] as num?;
                final sell = sellRaw != null
                    ? IraqiCurrencyFormat.formatInt(sellRaw)
                    : '—';
                final stockLine = _productSearchStockLine(p);
                return _searchHChip(
                  onTap: () => _handleProductQuickPick(p),
                  icon: Icons.inventory_2_outlined,
                  iconColor: const Color(0xFF0D9488),
                  title: '${p['name'] ?? ''}',
                  subtitle: 'بيع $sell د.ع',
                  belowSubtitle: stockLine,
                );
              },
            ),
          if (_hitCustomers.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'العملاء',
              count: _hitCustomers.length,
              height: 96,
              itemCount: _hitCustomers.length,
              itemBuilder: (i) {
                final c = _hitCustomers[i];
                final sub = [
                  if ((c['phone'] ?? '').toString().isNotEmpty)
                    c['phone'].toString(),
                  if ((c['email'] ?? '').toString().isNotEmpty)
                    c['email'].toString(),
                ].where((s) => s.isNotEmpty).take(2).join(' · ');
                return _searchHChip(
                  onTap: () {
                    _clearGlobalSearch();
                    _pushInContentTagged(
                      AppContentRoutes.customers,
                      'العملاء',
                      (_) => const CustomersScreen(),
                    );
                  },
                  icon: Icons.person_outline,
                  iconColor: const Color(0xFF0D9488),
                  title: '${c['name'] ?? ''}',
                  subtitle: sub.isEmpty ? 'عرض العملاء' : sub,
                );
              },
            ),
          if (_hitUsers.isNotEmpty)
            _buildHorizontalSearchSection(
              title: 'الموظفون',
              count: _hitUsers.length,
              height: 96,
              itemCount: _hitUsers.length,
              itemBuilder: (i) {
                final u = _hitUsers[i];
                final sub = [
                  if ((u['role'] ?? '').toString().isNotEmpty)
                    u['role'].toString(),
                  if ((u['email'] ?? '').toString().isNotEmpty)
                    u['email'].toString(),
                ].where((s) => s.isNotEmpty).join(' · ');
                return _searchHChip(
                  onTap: () {
                    _clearGlobalSearch();
                    _pushInContentTagged(
                      AppContentRoutes.users,
                      'المستخدمين',
                      (_) => const UsersScreen(),
                    );
                  },
                  icon: Icons.badge_outlined,
                  iconColor: const Color(0xFF3B82F6),
                  title: '${u['username'] ?? ''}',
                  subtitle: sub.isEmpty ? 'عرض الموظفين' : sub,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalSearchSection({
    required String title,
    required int count,
    required double height,
    required int itemCount,
    required Widget Function(int index) itemBuilder,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _searchSectionTitle(title, count),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: itemCount,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => itemBuilder(i),
            ),
          ),
        ],
      ),
    );
  }

  /// سطر المخزون تحت السعر في نتائج بحث المنتجات.
  String _productSearchStockLine(Map<String, dynamic> p) {
    final track = (p['trackInventory'] as int?) != 0;
    if (!track) return 'غير متتبّع للمخزون';
    final q = p['qty'];
    if (q == null) return 'المتوفر: —';
    final n = (q as num).toDouble();
    if (n < -1e-9) {
      final qStr = (n % 1).abs() < 1e-6
          ? IraqiCurrencyFormat.formatInt(n)
          : IraqiCurrencyFormat.formatDecimal2(n);
      final soldOver = (n.abs() % 1).abs() < 1e-6
          ? IraqiCurrencyFormat.formatInt(n.abs())
          : IraqiCurrencyFormat.formatDecimal2(n.abs());
      return 'رصيد سالب $qStr — بيع زائد قدره $soldOver عن آخر رصيد';
    }
    if (n.abs() < 1e-9) {
      return 'المتوفر: 0';
    }
    final s = (n % 1).abs() < 1e-6
        ? IraqiCurrencyFormat.formatInt(n)
        : IraqiCurrencyFormat.formatDecimal2(n);
    return 'المتوفر: $s';
  }

  Widget _searchHChip({
    required VoidCallback onTap,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? belowSubtitle,
  }) {
    final ac = context.appCorners;
    return Material(
      color: _isDarkMode ? const Color(0xFF1E293B) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: ac.md),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: _isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _textSecondary,
                        height: 1.2,
                      ),
                    ),
                    if (belowSubtitle != null && belowSubtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        belowSubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: _textSecondary.withValues(alpha: 0.92),
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchSectionTitle(String title, int count) {
    final ac = context.appCorners;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: ac.sm,
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // شريط الاختصارات مع دعم التحرير والإضافة
  Widget _buildQuickActionsBar(double qSize) {
    // الارتفاع = حجم الأيقونة (52%) + نص (20px) + padding (16px top+bottom) + مسافة (4px)
    final barHeight = (qSize * 0.52) + 20 + 16 + 4 + 16;
    return SizedBox(
      height: barHeight,
      child: ColoredBox(
        color: _bgColor,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _quickActions.length + (_isEditMode ? 1 : 0),
          itemBuilder: (context, index) {
            if (_isEditMode && index == _quickActions.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _buildAddQuickActionButton(qSize),
              );
            }
            final action = _quickActions[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _buildQuickActionButton(
                icon: action.icon,
                label: action.label,
                size: qSize,
                isEditMode: _isEditMode,
                onTap: () {
                  if (_isEditMode) {
                    _showDeleteConfirmation(index);
                  } else {
                    _pushInContentTagged(
                      action.routeId,
                      action.breadcrumbTitle,
                      action.destination,
                    );
                  }
                },
                onLongPress: () {
                  if (!_isEditMode) {
                    setState(() {
                      _isEditMode = true;
                    });
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAddQuickActionButton(double size) {
    final ac = context.appCorners;
    return GestureDetector(
      onTap: _showAddQuickActionDialog,
      child: SizedBox(
        width: size * 0.85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: size * 0.52,
              height: size * 0.52,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: ac.md,
                border: Border.all(color: Colors.green.shade700, width: 1),
              ),
              child: const Icon(Icons.add, color: Colors.green, size: 28),
            ),
            const SizedBox(height: 4),
            Text(
              'إضافة',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: _textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required double size,
    required bool isEditMode,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final ac = context.appCorners;
    final iconBoxSize = size * 0.52;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: size * 0.85,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: ac.md,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.primary,
                    size: iconBoxSize * 0.45,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: size * 0.85,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: _textPrimary,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (isEditMode)
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _persistModulesOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final titles = _orderedModules.map((m) => m.title).toList();
    await prefs.setStringList('modules_order', titles);
  }

  void _reorderBottomModules(
    List<ModuleItem> currentVisible,
    int oldI,
    int newI,
  ) {
    if (newI > oldI) newI -= 1;
    if (oldI < 0 || oldI >= currentVisible.length) return;
    if (newI < 0 || newI >= currentVisible.length) return;

    final selectedRoute =
        currentVisible[_activeBottomIndex.clamp(0, currentVisible.length - 1)]
            .routeId;

    final nextVisible = List<ModuleItem>.from(currentVisible);
    final moved = nextVisible.removeAt(oldI);
    nextVisible.insert(newI, moved);

    final removed = nextVisible.map((m) => m.routeId).toSet();
    final original = List<ModuleItem>.from(_orderedModules);
    final minIndex = original.indexWhere((m) => removed.contains(m.routeId));
    final base = original.where((m) => !removed.contains(m.routeId)).toList();
    final insertAt = (minIndex < 0 || minIndex > base.length)
        ? base.length
        : minIndex;
    base.insertAll(insertAt, nextVisible);

    final newActive = nextVisible.indexWhere((m) => m.routeId == selectedRoute);
    setState(() {
      _orderedModules = base;
      _activeBottomIndex = newActive >= 0 ? newActive : 0;
    });
    unawaited(_persistModulesOrder());
    unawaited(_recomputeNavModules());
  }

  // ── Bottom Navigation Bar — Material 3 (مؤشر كبسولة + خلفية فاتحة كالمرجع) ─
  Widget _buildBottomNavBar(List<ModuleItem> bottomModules) {
    if (bottomModules.isEmpty) return const SizedBox.shrink();
    final sl = ScreenLayout.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = _isDarkMode;
    final barBg = isDark ? cs.surfaceContainerHigh : const Color(0xFFF7F4EF);
    final indicator = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFE8E0D6);
    // على بعض أجهزة الهاتف يظهر overflow بسيط (≈5px) بسبب SafeArea + حشوات عناصر الشريط.
    // نعطي ارتفاعاً أعلى قليلاً مع تقليل الحشوات الداخلية.
    final height = sl.isCompactHeight ? 76.0 : 82.0;
    final idx = _activeBottomIndex.clamp(0, bottomModules.length - 1);

    return Material(
      color: barBg,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            proxyDecorator: (child, index, anim) {
              return Material(
                color: Colors.transparent,
                elevation: 6,
                shadowColor: Colors.black.withValues(alpha: 0.18),
                child: child,
              );
            },
            onReorder: (oldI, newI) =>
                _reorderBottomModules(bottomModules, oldI, newI),
            itemCount: bottomModules.length,
            itemBuilder: (ctx, i) {
              final m = bottomModules[i];
              final selected = i == idx;
              return ReorderableDelayedDragStartListener(
                key: ValueKey(m.routeId),
                index: i,
                child: _BottomNavTile(
                  module: m,
                  selected: selected,
                  barColor: barBg,
                  indicatorColor: indicator,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    final hasSubItems =
                        m.subItems != null && m.subItems!.isNotEmpty;
                    setState(() => _activeBottomIndex = i);
                    if (hasSubItems) {
                      _showSubItemsSheet(m);
                    } else {
                      _pushInContentTagged(
                        m.routeId,
                        m.breadcrumbTitle,
                        m.destination,
                      );
                    }
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// ورقة القائمة الفرعية لعنصر ذي sub-items
  void _showSubItemsSheet(ModuleItem module) {
    final ac = context.appCorners;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: _isDarkMode ? const Color(0xFF1E1E2E) : Colors.white,
            borderRadius: ac.lg,
            border: Border.all(
              color: _isDarkMode ? AppColors.borderDark : AppColors.borderLight,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 12,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: ac.radius(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: module.iconColor.withOpacity(0.12),
                        borderRadius: ac.sm,
                      ),
                      child: Icon(
                        module.icon,
                        color: module.iconColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            module.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _textPrimary,
                            ),
                          ),
                          Text(
                            'اختر من القائمة أدناه',
                            style: TextStyle(
                              fontSize: 11,
                              color: _textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // زر الوصول المباشر للصفحة الرئيسية للوحدة
                    TextButton(
                      onPressed: () {
                        _popSheetThenPushInContentTagged(
                          module.routeId,
                          module.breadcrumbTitle,
                          module.destination,
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: module.iconColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                      ),
                      child: const Text(
                        'عرض الكل',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: _dividerColor),
              // Sub-items list
              ...module.subItems!.map(
                (sub) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 2,
                  ),
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: module.iconColor.withOpacity(0.08),
                      borderRadius: ac.sm,
                    ),
                    child: Icon(
                      sub.icon ?? Icons.arrow_left,
                      color: module.iconColor,
                      size: 18,
                    ),
                  ),
                  title: Text(
                    sub.title,
                    style: TextStyle(
                      color: _textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_left,
                    color: _textSecondary,
                    size: 18,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: ac.md),
                  onTap: () {
                    _popSheetThenPushInContentTagged(
                      sub.routeId,
                      sub.breadcrumbTitle,
                      sub.destination,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data models ────────────────────────────────────────────────────────────────
class QuickAction {
  final IconData icon;
  final String label;
  final String routeId;
  final String breadcrumbTitle;
  final Widget Function(BuildContext) destination;
  QuickAction({
    required this.icon,
    required this.label,
    required this.routeId,
    String? breadcrumbTitle,
    required this.destination,
  }) : breadcrumbTitle = breadcrumbTitle ?? label;
}

class _HomeInnerNavObserver extends NavigatorObserver {
  _HomeInnerNavObserver(this._state);
  final _HomeScreenState _state;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._appendBreadcrumbForRoute(route);
    _state._syncActiveModuleIndexFromRoute(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._removeBreadcrumbForRoute(route);
    _state._syncActiveModuleIndexFromRoute(previousRoute?.settings.name);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _state._removeBreadcrumbForRoute(route);
    _state._syncActiveModuleIndexFromRoute(previousRoute?.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _state._removeBreadcrumbForRoute(oldRoute);
    if (newRoute != null) {
      _state._appendBreadcrumbForRoute(newRoute);
      _state._syncActiveModuleIndexFromRoute(newRoute.settings.name);
    }
  }
}

/// أيقونة شريط سفلي M3 — نقطة صغيرة عند وجود قائمة فرعية.
class _BottomNavIcon extends StatelessWidget {
  const _BottomNavIcon({required this.module, required this.barColor});

  final ModuleItem module;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    final hasSub = module.subItems != null && module.subItems!.isNotEmpty;
    final iconTheme = IconTheme.of(context);
    return SizedBox(
      width: 32,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(module.icon, size: 24, color: iconTheme.color),
          if (hasSub)
            PositionedDirectional(
              top: -2,
              end: -3,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: module.iconColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: barColor, width: 1.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomNavTile extends StatelessWidget {
  const _BottomNavTile({
    required this.module,
    required this.selected,
    required this.barColor,
    required this.indicatorColor,
    required this.onTap,
  });

  final ModuleItem module;
  final bool selected;
  final Color barColor;
  final Color indicatorColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSurface : cs.onSurfaceVariant;
    return SizedBox(
      width: 78,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppShape.none,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? indicatorColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: _BottomNavIcon(module: module, barColor: barColor),
                ),
                const SizedBox(height: 5),
                Text(
                  module.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    letterSpacing: -0.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Home content page (used inside inner Navigator on large screens) ──────────
class _HomeContentPage extends StatelessWidget {
  final _HomeScreenState parentState;

  const _HomeContentPage({required this.parentState});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: LayoutBuilder(
        builder: (_, c) => parentState._buildMainContent(c.maxWidth),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
class ModuleItem {
  final IconData icon;
  final String title;
  final Color iconColor;

  /// معرّف فريد لمسار التنقل وفتات الخبز (لا يُكرّر في المكدس).
  final String routeId;
  final String breadcrumbTitle;
  final Widget Function(BuildContext) destination;
  final List<SubMenuItem>? subItems;
  ModuleItem({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.routeId,
    String? breadcrumbTitle,
    required this.destination,
    this.subItems,
  }) : breadcrumbTitle = breadcrumbTitle ?? title;
}

class SubMenuItem {
  final String title;
  final String routeId;
  final String breadcrumbTitle;
  final Widget Function(BuildContext) destination;
  final IconData? icon;
  SubMenuItem({
    required this.title,
    required this.routeId,
    String? breadcrumbTitle,
    required this.destination,
    this.icon,
  }) : breadcrumbTitle = breadcrumbTitle ?? title;
}

class _SidebarItem {
  final IconData icon;
  final String title;
  final Color iconColor;
  final VoidCallback onTap;
  final List<_SubItem>? subItems;
  _SidebarItem({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.onTap,
    this.subItems,
  });
}

class _SubItem {
  final String title;
  final VoidCallback onTap;
  final IconData? icon;
  _SubItem({required this.title, required this.onTap, this.icon});
}
