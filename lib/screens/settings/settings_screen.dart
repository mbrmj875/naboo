import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../notifications/ui/owner_phone_banner.dart';
import '../../notifications/ui/push_settings_screen.dart';
import '../../platform/web_pwa_install.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/ui_feedback_settings_provider.dart';
import '../../providers/print_settings_provider.dart';
import '../../models/print_settings_data.dart';
import '../../services/effective_store_branding.dart';
import '../../services/license_service.dart';
import '../../navigation/content_navigation.dart';
import '../../theme/app_corner_style.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/secure_screen.dart';
import '../../widgets/web_pwa_install_banner.dart';
import '../invoices/sale_pos_settings_screen.dart';
import '../onboarding/business_setup_wizard_screen.dart';
import '../printing/printing_screen.dart';
import 'dashboard_layout_settings_screen.dart';
import 'market_pos_import_screen.dart';
import 'account_subscription_screen.dart';
import 'store_info_screen.dart';
import 'return_policy_settings_screen.dart';
import '../../providers/business_features_provider.dart';
import '../../services/business_setup_settings.dart';
import '../../verticals/car_wash/screens/wash_offers_settings_screen.dart';
import 'sync_queue_health_screen.dart';
import 'cash_ledger_audit_screen.dart';
import 'settings_help_screen.dart';
import '../../guides/guide_anchor.dart';
import '../../guides/guide_controller.dart';
import 'settings_registry.dart';
import '../../home/employee_access_policy.dart';
import '../../home/home_dashboard_resolver.dart';
import '../../providers/permissions_provider.dart';
import '../../models/marketplace_order.dart';
import '../../services/marketplace/marketplace_orders_service.dart';
import '../../printing/printing_center_screen.dart';
import '../../owner/widgets/owner_dashboard_layout_sheet.dart';
import '../../verticals/oil_change/screens/oil_change_hub_screen.dart'
    show showOilChangeHubSettingsSheet;
import '../debts/debt_settings_screen.dart';
import '../installments/installment_settings_screen.dart';
import '../inventory/inventory_settings_screen.dart';
import '../loyalty/loyalty_settings_screen.dart';
import '../online_orders/market_pickup_settings_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kTeal = Color(0xFF0D9488);
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFEF4444);

/// شريط عنوان إعدادات يتبع [ColorScheme.primary] — نفس هوية الثيم في باقي التطبيق.
AppBar _settingsAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final bg = dark ? const Color(0xFF0F172A) : Colors.white;
  final titleColor = dark ? const Color(0xFFD4AF37) : const Color(0xFF1E3A5F);
  final iconColor = dark ? const Color(0xFFD4AF37) : const Color(0xFF1E3A5F);

  return AppBar(
    backgroundColor: bg,
    foregroundColor: titleColor,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 17,
        color: titleColor,
      ),
    ),
    iconTheme: IconThemeData(color: iconColor, size: 22),
    actionsIconTheme: IconThemeData(color: const Color(0xFFD4AF37), size: 22),
    bottom: PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(
        height: 1,
        color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
      ),
    ),
    actions: actions,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _search = TextEditingController();
  String _query = '';

  // لوحة «إعدادات غيار الزيت»: من فتحها، حتى تغلق الجولة ما فتحته هي فقط.
  bool _oilSheetOpen = false;
  bool _oilSheetByGuide = false;
  BuildContext? _oilSheetContext;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  SettingsAccess _access(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final features = context.watch<BusinessFeaturesProvider>().data;
    final perms = context.watch<PermissionsProvider>();
    final policy = EmployeeAccessPolicy(
      can: perms.can,
      features: features,
      restricted: LicenseService.instance.state.status ==
          LicenseStatus.restricted,
      hiddenRouteIds: HomeDashboardResolver.resolve(features).hideNavRouteIds,
    );
    return SettingsAccess(
      isOwner: auth.isOwner,
      features: features,
      canSeeRoute: policy.isVisible,
      pwaInstallSupported: kIsWeb && WebPwaInstall.isWebSupported,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final guide = context.watch<GuideController>();
    final visible = visibleSettingsEntries(_access(context));
    // يُحسب هنا داخل البناء، لأن قراءة الصلاحيات خارج البناء ممنوعة.
    final canOilHub = visible.any((e) => e.id == SettingsEntryIds.oilHub);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncGuide(guide, canOilHub: canOilHub);
    });
    final searching = _query.trim().isNotEmpty;
    final results = searching
        ? visible.where((e) => settingsEntryMatches(e, _query)).toList()
        : visible;

    final children = <Widget>[
      _SettingsSearchField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: 14),
    ];

    if (searching) {
      if (results.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'لا يوجد إعداد بهذا الاسم.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        );
      } else {
        children.add(
          _SettingsGroup(
            title: 'نتائج البحث',
            isDark: isDark,
            items: [
              for (final e in results)
                _anchored(e, _tileFor(context, e, showGroup: true, isDark: isDark)),
            ],
          ),
        );
      }
    } else {
      children
        ..add(const _CompanyCard())
        ..add(const SizedBox(height: 16));
      for (final g in SettingsGroupId.values) {
        final items = results.where((e) => e.group == g).toList();
        if (items.isEmpty) continue;
        children
          ..add(
            _SettingsGroup(
              title: kSettingsGroupTitles[g]!,
              isDark: isDark,
              items: [
                for (final e in items) _anchored(e, _tileFor(context, e, isDark: isDark)),
              ],
            ),
          )
          ..add(const SizedBox(height: 14));
      }
      children.add(const SizedBox(height: 10));
    }

    return SecureScreen(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: _settingsAppBar(context, 'الإعدادات'),
          body: LayoutBuilder(
            builder: (context, constraints) {
              /// يمنع كسر [ListTile] عند عرض أقل من ~72 (مثلاً أثناء أنيميشن التصغير).
              final minW = math.max(constraints.maxWidth, 300.0);
              final gap = ScreenLayout.of(context).pageHorizontalGap;
              return Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: SizedBox(
                      width: minW,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: gap,
                          vertical: 16,
                        ),
                        child: Column(children: children),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static const _kBlue = Color(0xFF3B82F6);

  Color _iconColor(ColorScheme cs, SettingsEntry e) {
    switch (e.group) {
      case SettingsGroupId.store:
      case SettingsGroupId.printing:
        return cs.primary;
      case SettingsGroupId.sales:
      case SettingsGroupId.oilShop:
        return _kTeal;
      case SettingsGroupId.debts:
      case SettingsGroupId.notifications:
        return _kAmber;
      case SettingsGroupId.data:
        return e.id == SettingsEntryIds.syncHealth ? _kRed : _kBlue;
      case SettingsGroupId.help:
        return e.id == SettingsEntryIds.about ? Colors.grey : _kBlue;
      default:
        return _kBlue;
    }
  }

  /// كل بند له مرساة باسمه ليشير إليه المساعد (ب3). بند الزيت له مرساته القديمة.
  Widget _anchored(SettingsEntry e, Widget tile) => e.id == SettingsEntryIds.oilHub
      ? tile
      : GuideAnchor(id: OilGuideAnchors.settingsEntryFor(e.id), child: tile);

  Widget _tileFor(
    BuildContext context,
    SettingsEntry e, {
    required bool isDark,
    bool showGroup = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    // بنود تعرض مفتاحاً أو حالة حيّة داخل الصف نفسه.
    switch (e.id) {
      case SettingsEntryIds.debtsToggle:
        return const _DebtsFeatureToggleTile();
      case SettingsEntryIds.compactSnack:
        return _CompactSnackNotificationsTile(isDark: isDark);
      case SettingsEntryIds.themeToggle:
        return _ThemeToggleTile(isDark: isDark);
      case SettingsEntryIds.oilHub:
        return GuideAnchor(
          id: OilGuideAnchors.settingsEntry,
          child: _SettingItem(
            icon: e.icon,
            iconColor: _iconColor(cs, e),
            title: e.title,
            subtitle: showGroup
                ? '${kSettingsGroupTitles[e.group]} · ${e.subtitle}'
                : e.subtitle,
            onTap: () => _open(context, e),
          ),
        );
      case SettingsEntryIds.subscription:
        return ListenableBuilder(
          listenable: LicenseService.instance,
          builder: (context, _) => _SettingItem(
            icon: e.icon,
            iconColor: _kAmber,
            title: e.title,
            subtitle: _subscriptionRowSubtitle(LicenseService.instance.state),
            onTap: () => _open(context, e),
          ),
        );
    }
    final group = kSettingsGroupTitles[e.group]!;
    return _SettingItem(
      icon: e.icon,
      iconColor: _iconColor(cs, e),
      title: e.title,
      subtitle: showGroup ? '$group · ${e.subtitle}' : e.subtitle,
      trailing: e.enabled
          ? null
          : Text(
              'قريباً',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
      onTap: e.enabled ? () => _open(context, e) : null,
    );
  }

  /// ما يفتحه كل بند. البنود التي تفتح شاشة تمرّ بمعرّف مسارها حتى تبقى فتات الخبز صحيحة.
  Future<void> _open(BuildContext context, SettingsEntry e) async {
    final features = context.read<BusinessFeaturesProvider>().data;
    final isOilShop = features.enableOilChange ||
        features.effectiveVertical == BusinessVertical.oilChange;
    Widget? screen;
    switch (e.id) {
      case SettingsEntryIds.pwaInstall:
        _openPwaInstall(context);
        return;
      case SettingsEntryIds.storeInfo:
        screen = const StoreInfoScreen();
      case SettingsEntryIds.branchInfo:
        screen = const StoreInfoScreen(scope: StoreInfoScope.myBranch);
      case SettingsEntryIds.businessFeatures:
        screen = const BusinessSetupWizardScreen(openedFromSettings: true);
      case SettingsEntryIds.subscription:
        screen = const AccountSubscriptionScreen();
      case SettingsEntryIds.salePos:
        screen = const SalePosSettingsScreen();
      case SettingsEntryIds.returnPolicy:
        screen = const ReturnPolicySettingsScreen();
      case SettingsEntryIds.loyalty:
        screen = const LoyaltySettingsScreen();
      case SettingsEntryIds.debtSettings:
        screen = const DebtSettingsScreen();
      case SettingsEntryIds.installmentSettings:
        screen = const InstallmentSettingsScreen();
      case SettingsEntryIds.inventorySettings:
        screen = const InventorySettingsScreen();
      case SettingsEntryIds.oilHub:
        await _openOilSheet();
        return;
      case SettingsEntryIds.washOffers:
        screen = const WashOffersSettingsScreen();
      case SettingsEntryIds.marketPickup:
        await _openMarketPickup(context, e);
        return;
      case SettingsEntryIds.printing:
        // نفس اختيار القائمة: محل الزيت يستخدم قسم الطباعة الجديد.
        screen = isOilShop
            ? const PrintingCenterScreen()
            : const PrintingScreen();
      case SettingsEntryIds.notifications:
        screen = const _NotificationsScreen();
      case SettingsEntryIds.ownerAlerts:
      case SettingsEntryIds.ownerDashboardCards:
        await showOwnerDashboardLayoutSheet(context);
        return;
      case SettingsEntryIds.colors:
        screen = const SalePosSettingsScreen(appearanceOnly: true);
      case SettingsEntryIds.dashboardLayout:
        screen = const DashboardLayoutSettingsScreen();
      case SettingsEntryIds.import:
        screen = const MarketPosImportScreen();
      case SettingsEntryIds.syncHealth:
        screen = const SyncQueueHealthScreen();
      case SettingsEntryIds.cashAudit:
        screen = const CashLedgerAuditScreen();
      case SettingsEntryIds.help:
        screen = const SettingsHelpScreen();
      case SettingsEntryIds.about:
        await _showAbout(context);
        return;
    }
    if (screen == null || !context.mounted) return;
    await _goTo(
      context,
      screen,
      routeId: e.routeId ?? AppContentRoutes.settings,
      breadcrumbTitle: e.title,
    );
  }

  Future<void> _openOilSheet({bool fromGuide = false}) async {
    if (_oilSheetOpen) {
      if (fromGuide) _oilSheetByGuide = true;
      return;
    }
    _oilSheetOpen = true;
    _oilSheetByGuide = fromGuide;
    try {
      await showOilChangeHubSettingsSheet(
        context,
        onSheetContext: (c) => _oilSheetContext = c,
      );
    } finally {
      _oilSheetOpen = false;
      _oilSheetByGuide = false;
      _oilSheetContext = null;
    }
  }

  /// جولة «إعدادات غيار الزيت»: تفتح اللوحة لخطوات مفاتيحها وتغلقها بعدها.
  void _syncGuide(GuideController guide, {required bool canOilHub}) {
    final step = guide.currentStep;
    final running = guide.isRunning && step != null;
    if (running &&
        (step.anchorId == OilGuideAnchors.settingsEntry ||
            step.anchorId.startsWith(OilGuideAnchors.settingsEntryPrefix)) &&
        _query.isNotEmpty) {
      // البحث قد يخفي البند الذي تشير إليه الجولة.
      _search.clear();
      setState(() => _query = '');
    }
    // لا تُفتح اللوحة عبر الدليل لمن لا يرى بندها ([canOilHub]).
    final needSheet = running &&
        canOilHub &&
        (step.action == 'oil.open_hub_settings' ||
            step.anchorId.startsWith('oil.settings.'));
    if (needSheet) {
      if (!_oilSheetOpen) {
        unawaited(_openOilSheet(fromGuide: true));
      } else {
        _oilSheetByGuide = true;
      }
    } else if (_oilSheetByGuide && _oilSheetOpen) {
      final c = _oilSheetContext;
      if (c != null && Navigator.of(c).canPop()) Navigator.of(c).pop();
    }
  }

  Future<void> _goTo(
    BuildContext context,
    Widget screen, {
    required String routeId,
    required String breadcrumbTitle,
  }) {
    return Navigator.push<void>(
      context,
      FastContentPageRoute(
        settings: RouteSettings(
          name: routeId,
          arguments: BreadcrumbMeta(breadcrumbTitle),
        ),
        builder: (_) => screen,
      ),
    );
  }

  void _openPwaInstall(BuildContext context) {
    if (WebPwaInstall.isStandalone()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نابو مثبّت مسبقاً على هذا الجهاز.')),
      );
      return;
    }
    WebPwaInstall.clearBannerDismiss();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => const SafeArea(
        child: SingleChildScrollView(
          child: WebPwaInstallBanner(
            compact: false,
            margin: EdgeInsetsDirectional.all(8),
          ),
        ),
      ),
    );
  }

  /// يفتح إعداد الاستلام لأول متجر Market مربوط — نفس سلوك شاشة الطلبات.
  Future<void> _openMarketPickup(BuildContext context, SettingsEntry e) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));
    if (Supabase.instance.client.auth.currentUser == null) {
      say('سجّل الدخول للحساب السحابي أولاً.');
      return;
    }
    List<MarketplaceStoreSummary> stores;
    try {
      stores = await MarketplaceOrdersService().fetchLinkedStores();
    } catch (_) {
      say('تعذر جلب متجر Market. تحقق من الاتصال.');
      return;
    }
    if (stores.isEmpty) {
      say('لا يوجد متجر Market مربوط بحسابك.');
      return;
    }
    if (!context.mounted) return;
    final store = stores.first;
    await _goTo(
      context,
      MarketPickupSettingsScreen(storeId: store.id, storeName: store.name),
      routeId: e.routeId!,
      breadcrumbTitle: e.title,
    );
  }

  Future<void> _showAbout(BuildContext context) async {
    var version = '';
    try {
      final pkg = await PackageInfo.fromPlatform();
      version = '${pkg.version} (${pkg.buildNumber})';
    } catch (_) {}
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'نابو لإدارة المتاجر',
      applicationVersion: version.isEmpty ? null : 'الإصدار $version',
      applicationLegalese: '© 2026 نابو. جميع الحقوق محفوظة.',
      children: const [
        Padding(
          padding: EdgeInsetsDirectional.only(top: 8),
          child: Text(
            'تطبيق متكامل لإدارة المبيعات والمخزون والحسابات.',
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );
  }
}

/// حقل البحث في أعلى الإعدادات.
class _SettingsSearchField extends StatelessWidget {
  const _SettingsSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'ابحث في الإعدادات',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, v, _) => v.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'مسح البحث',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: context.appCorners.md,
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

// ── بطاقة الشركة ──────────────────────────────────────────────────────────────
class _CompanyCard extends StatefulWidget {
  const _CompanyCard();

  @override
  State<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends State<_CompanyCard> {
  PrintSettingsData? _effective;
  bool _loading = true;
  int? _loadedForUserId;
  String _loadedForGlobalId = '';

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final uid = auth.userId;
    final gid = auth.userGlobalId;
    if (uid != _loadedForUserId || gid != _loadedForGlobalId) {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    final auth = context.read<AuthProvider>();
    final base = context.read<PrintSettingsProvider>().data;
    final uid = auth.userId;
    final gid = auth.userGlobalId;
    // بطاقة الإعدادات: لا نعرض متجر المالك فوق موظف لم يعبّئ بياناته بعد.
    final resolved = await EffectiveStoreBranding.resolve(
      isOwner: auth.isOwner,
      userGlobalId: gid,
      userId: uid,
      base: base,
      fallbackToWorkspace: auth.isOwner,
    );
    if (!mounted) return;
    setState(() {
      _effective = resolved;
      _loading = false;
      _loadedForUserId = uid;
      _loadedForGlobalId = gid;
    });
  }

  static String _storeName(PrintSettingsData p, {required bool isOwner}) {
    final n = p.storeTitleLine.trim();
    if (n.isNotEmpty) return n;
    return isOwner ? 'اسم المتجر' : 'بيانات فرعي';
  }

  static String _storeSubtitle(PrintSettingsData p, {required bool isOwner}) {
    final addr = p.storeAddress.trim();
    final phones = p.storePhones
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (addr.isNotEmpty && phones.isNotEmpty) {
      return '$addr · ${phones.join(' · ')}';
    }
    if (addr.isNotEmpty) return addr;
    if (phones.isNotEmpty) return phones.join(' · ');
    return isOwner
        ? 'اضغط التعديل لإضافة العنوان والهاتف'
        : 'اضغط لإدخال اسم فرعك وشعارك وهاتفك';
  }

  Future<void> _openStoreInfo() async {
    final isOwner = context.read<AuthProvider>().isOwner;
    await Navigator.push<void>(
      context,
      FastContentPageRoute(
        settings: RouteSettings(
          name: isOwner
              ? AppContentRoutes.settingsStoreInfo
              : AppContentRoutes.settingsMyBranchInfo,
          arguments: BreadcrumbMeta(isOwner ? 'بيانات المتجر' : 'بيانات فرعي'),
        ),
        builder: (_) => StoreInfoScreen(
          scope: isOwner ? StoreInfoScope.workspace : StoreInfoScope.myBranch,
        ),
      ),
    );
    if (!mounted) return;
    await context.read<PrintSettingsProvider>().load();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final gap = ScreenLayout.of(context).pageHorizontalGap;
    final isOwner = context.watch<AuthProvider>().isOwner;
    final store = _effective ?? context.watch<PrintSettingsProvider>().data;
    final name = _loading ? '…' : _storeName(store, isOwner: isOwner);
    final subtitle = _loading ? '' : _storeSubtitle(store, isOwner: isOwner);

    return GestureDetector(
      onLongPress: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فتح أدوات الاختبار…'),
            duration: Duration(milliseconds: 900),
          ),
        );
        Navigator.of(context, rootNavigator: true).pushNamed('/dev/stress');
      },
      onTap: () => unawaited(_openStoreInfo()),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: gap, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary,
              Color.lerp(cs.primary, cs.surface, 0.12) ?? cs.primary,
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: ac.lg,
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.18),
              blurRadius: ac.isRounded ? 14 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _CompanyLogoAvatar(
              logoBytes: store.hasStoreLogo ? store.storeLogoBytes : null,
              isOwner: isOwner,
              colorScheme: cs,
              borderRadius: ac.md,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: cs.onPrimary.withValues(alpha: 0.82),
                      fontSize: 13,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  ListenableBuilder(
                    listenable: LicenseService.instance,
                    builder: (context, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.onPrimary.withValues(alpha: 0.18),
                          borderRadius: ac.sm,
                        ),
                        child: Text(
                          _subscriptionTypeAr(LicenseService.instance.state),
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: isOwner ? 'تعديل بيانات المتجر' : 'تعديل بيانات فرعي',
              icon: Icon(Icons.edit_rounded, color: cs.onPrimary),
              onPressed: () => unawaited(_openStoreInfo()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyLogoAvatar extends StatelessWidget {
  const _CompanyLogoAvatar({
    required this.logoBytes,
    required this.isOwner,
    required this.colorScheme,
    required this.borderRadius,
  });

  final Uint8List? logoBytes;
  final bool isOwner;
  final ColorScheme colorScheme;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final bytes = logoBytes;
    return Container(
      width: 60,
      height: 60,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.onPrimary.withValues(alpha: 0.18),
        borderRadius: borderRadius,
      ),
      child: bytes != null && bytes.isNotEmpty
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Icon(
                isOwner ? Icons.store_rounded : Icons.storefront_rounded,
                color: colorScheme.onPrimary,
                size: 30,
              ),
            )
          : Icon(
              isOwner ? Icons.store_rounded : Icons.storefront_rounded,
              color: colorScheme.onPrimary,
              size: 30,
            ),
    );
  }
}

// ── مجموعة إعدادات ────────────────────────────────────────────────────────────
class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> items;
  final bool isDark;
  const _SettingsGroup({
    required this.title,
    required this.items,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: ac.md,
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
                blurRadius: ac.isRounded ? 10 : 0,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: items.asMap().entries.map((e) {
              final isLast = e.key == items.length - 1;
              return Column(
                children: [
                  e.value,
                  if (!isLast)
                    Divider(
                      height: 1,
                      indent: 54,
                      color: cs.outline.withValues(alpha: 0.35),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// نوع الخطة باختصار، للشارة تحت بيانات المتجر.
String _subscriptionTypeAr(LicenseState s) {
  switch (s.status) {
    case LicenseStatus.active:
      final plan = s.plan;
      if (plan == null) return 'مفعّل';
      return switch (plan.key) {
        'monthly' => 'اشتراك شهري',
        'annual' => 'اشتراك سنوي',
        'lifetime' => 'مدى الحياة',
        'trial' => 'التجربة المجانية',
        _ => _planNameWithoutExtra(plan.nameAr),
      };
    case LicenseStatus.trial:
      return 'التجربة المجانية';
    case LicenseStatus.expired:
    case LicenseStatus.suspended:
      return 'غير نشط';
    case LicenseStatus.offline:
      return 'غير متصّل';
    case LicenseStatus.checking:
      return '…';
    case LicenseStatus.restricted:
    case LicenseStatus.pendingLock:
      return 'غير نشط';
    case LicenseStatus.none:
      return 'بدون ترخيص';
  }
}

/// سطر واحد متصل: نوع الخطة ثم الأجهزة المشمولة.
String _subscriptionRowSubtitle(LicenseState s) {
  final type = _subscriptionTypeAr(s);
  final devices = s.plan?.devicesLabel.trim() ?? '';
  if (devices.isEmpty) return type;
  if (s.status == LicenseStatus.active || s.status == LicenseStatus.trial) {
    return '$type — $devices';
  }
  return type;
}

String _planNameWithoutExtra(String nameAr) {
  final cut = nameAr.indexOf(' (');
  if (cut <= 0) return nameAr;
  return nameAr.substring(0, cut);
}

// ── عنصر الإعداد ──────────────────────────────────────────────────────────────
class _SettingItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: ac.sm,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        textAlign: TextAlign.start,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: cs.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        textAlign: TextAlign.start,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing:
          trailing ??
          Icon(
            Icons.chevron_left_rounded,
            color: cs.onSurfaceVariant,
            size: 20,
          ),
      onTap: onTap,
    );
  }
}

/// مفتاح ميزة الديون للمالك. بدونه لا طريقة لإظهار صفحة الديون بعد الإعداد الأول.
class _DebtsFeatureToggleTile extends StatefulWidget {
  const _DebtsFeatureToggleTile();

  @override
  State<_DebtsFeatureToggleTile> createState() =>
      _DebtsFeatureToggleTileState();
}

class _DebtsFeatureToggleTileState extends State<_DebtsFeatureToggleTile> {
  bool _saving = false;

  Future<void> _set(bool value) async {
    if (_saving) return;
    final features = context.read<BusinessFeaturesProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await features.save(features.data.copyWith(enableDebts: value));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            value ? 'تم تفعيل الديون وظهرت صفحتها' : 'تم إيقاف الديون',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ إعداد الديون')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = context.watch<BusinessFeaturesProvider>().data.enableDebts;
    return _SettingItem(
      icon: Icons.balance_outlined,
      iconColor: Colors.amber.shade800,
      title: 'تفعيل الديون (البيع الآجل)',
      subtitle: enabled
          ? 'صفحة الديون ظاهرة والبيع بالآجل مسموح'
          : 'مطفأة: صفحة الديون مخفية',
      trailing: Switch(
        value: enabled,
        onChanged: _saving ? null : _set,
      ),
      onTap: () => _set(!enabled),
    );
  }
}

// ── تبديل الثيم ───────────────────────────────────────────────────────────────
/// شرائط التنبيه السريعة (SnackBar) — من [SettingsScreen] الرئيسية؛ لا علاقة لها بـ «إعدادات نقطة البيع».
class _CompactSnackNotificationsTile extends StatelessWidget {
  final bool isDark;
  const _CompactSnackNotificationsTile({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Consumer<UiFeedbackSettingsProvider>(
      builder: (context, ui, _) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _kTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.zero,
            ),
            child: const Icon(
              Icons.view_sidebar_outlined,
              color: _kTeal,
              size: 20,
            ),
          ),
          title: const Text(
            'شكل تنبيهات الصفحات (كل التطبيق)',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            ui.useCompactSnackNotifications
                ? 'شرائط أضيق وعائمة في كل الشاشات — من إعدادات التطبيق العامة هنا، وليس من «إعدادات نقطة البيع»'
                : 'وضع كلاسيكي: شريط تنبيه بعرض أسفل الشاشة في كل الصفحات',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
              height: 1.35,
            ),
          ),
          trailing: Switch(
            value: ui.useCompactSnackNotifications,
            onChanged: (v) => ui.setCompactSnackNotifications(v),
          ),
        );
      },
    );
  }
}

class _ThemeToggleTile extends StatelessWidget {
  final bool isDark;
  const _ThemeToggleTile({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: (isDark ? Colors.indigo : _kAmber).withValues(alpha: 0.12),
          borderRadius: BorderRadius.zero,
        ),
        child: Icon(
          isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          color: isDark ? Colors.indigo : _kAmber,
          size: 20,
        ),
      ),
      title: const Text(
        'المظهر',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        isDark ? 'الوضع الداكن' : 'الوضع الفاتح',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: Switch(
        value: isDark,
        onChanged: (v) => context.read<ThemeProvider>().toggleDarkMode(),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ── شاشات فرعية للإعدادات ─────────────────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

/// إعدادات الفواتير
class _NotificationsScreen extends StatefulWidget {
  const _NotificationsScreen();
  @override
  State<_NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<_NotificationsScreen> {
  bool _lowStock = true;
  bool _negStockSale = true;
  bool _financedSale = true;
  bool _expiry = true;
  bool _installment = true;
  bool _customerDebt = true;
  bool _returns = true;
  bool _dailyReport = false;
  bool _shiftLifecycle = true;
  bool _prefsLoaded = false;
  final TextEditingController _expiryDefaultDaysCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _expiryDefaultDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final defDays = (p.getInt(NotificationPrefs.defaultExpiryAlertDays) ?? 14)
        .clamp(1, 365);
    _expiryDefaultDaysCtrl.text = '$defDays';
    setState(() {
      _lowStock = p.getBool(NotificationPrefs.lowStock) ?? true;
      _negStockSale = p.getBool(NotificationPrefs.negativeStockSale) ?? true;
      _financedSale = p.getBool(NotificationPrefs.financedSale) ?? true;
      _expiry = p.getBool(NotificationPrefs.expiry) ?? true;
      _installment = p.getBool(NotificationPrefs.installment) ?? true;
      _customerDebt = p.getBool(NotificationPrefs.customerDebt) ?? true;
      _returns = p.getBool(NotificationPrefs.returns) ?? true;
      _dailyReport = p.getBool(NotificationPrefs.dailySummary) ?? false;
      _shiftLifecycle = p.getBool(NotificationPrefs.shiftLifecycle) ?? true;
      _prefsLoaded = true;
    });
  }

  Future<void> _saveExpiryDefaultDays() async {
    final v = int.tryParse(_expiryDefaultDaysCtrl.text.trim());
    if (v == null || v < 1 || v > 365) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt(NotificationPrefs.defaultExpiryAlertDays, v);
    if (mounted) {
      await context.read<NotificationProvider>().refresh();
    }
  }

  Future<void> _setPref(String key, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, value);
    if (mounted) {
      await context.read<NotificationProvider>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: _settingsAppBar(context, 'الإشعارات'),
        body: !_prefsLoaded
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: ScreenLayout.of(context).pageHorizontalGap,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'تُبنى التنبيهات من قاعدة البيانات عند فتح لوحة الإشعارات من الشاشة الرئيسية.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const OwnerPhoneBanner(margin: EdgeInsets.only(bottom: 8)),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: Icon(Icons.phone_iphone_rounded, color: cs.primary),
                        title: const Text(
                          'إشعارات المحل على الهاتف',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text(
                          'هاتف المالك، ما يصلك، ساعات الهدوء، الملخص، وإشعار تجريبي',
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PushSettingsScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'تنبيهات داخل التطبيق على هذا الجهاز',
                      style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurface),
                    ),
                    const SizedBox(height: 6),
                    _SwitchTile(
                      title: 'تنبيه نقص المخزون',
                      subtitle:
                          'منتجات وصلت للحد الأدنى أو نفدت (مع تتبع مخزون)',
                      value: _lowStock,
                      onChange: (v) {
                        setState(() => _lowStock = v);
                        _setPref(NotificationPrefs.lowStock, v);
                      },
                      isDark: isDark,
                    ),
                    _SwitchTile(
                      title: 'إشعار بيع أدى لرصيد سالب',
                      subtitle:
                          'بعد حفظ فاتورة البيع: رقم الفاتورة، البائع، العميل، والأصناف والكميات قبل/بعد الرصيد',
                      value: _negStockSale,
                      onChange: (v) {
                        setState(() => _negStockSale = v);
                        _setPref(NotificationPrefs.negativeStockSale, v);
                      },
                      isDark: isDark,
                    ),
                    _SwitchTile(
                      title: 'إشعار بيع بالدين أو التقسيط',
                      subtitle:
                          'عند حفظ فاتورة «آجل» أو «تقسيط» من شاشة البيع: رقم الفاتورة، البائع، العميل، المبالغ، الأسطر، وخطة التقسيط إن وُجدت',
                      value: _financedSale,
                      onChange: (v) {
                        setState(() => _financedSale = v);
                        _setPref(NotificationPrefs.financedSale, v);
                      },
                      isDark: isDark,
                    ),
                    _SwitchTile(
                      title: 'تنبيه صلاحية المنتجات',
                      subtitle:
                          'منتهية، أو تدخل ضمن «نافذة التنبيه» قبل التاريخ (حسب كل منتج أو الافتراضي أدناه)',
                      value: _expiry,
                      onChange: (v) {
                        setState(() => _expiry = v);
                        _setPref(NotificationPrefs.expiry, v);
                      },
                      isDark: isDark,
                    ),
                    if (_expiry) ...[
                      const SizedBox(height: 10),
                      Text(
                        'الأيام الافتراضية قبل تاريخ الانتهاء لإظهار تنبيه «قرب الصلاحية» (يُستعمل عند إضافة منتج إن لم تُضبط للصنف، و1–365).',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _expiryDefaultDaysCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          labelText: 'أيام التنبيه الافتراضية',
                          hintText: 'مثال: 14',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _saveExpiryDefaultDays(),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _saveExpiryDefaultDays,
                          child: const Text('حفظ الرقم الافتراضي'),
                        ),
                      ),
                    ],
                    _SwitchTile(
                      title: 'أقساط التقسيط',
                      subtitle: 'متأخرة أو مستحقة خلال 14 يوماً',
                      value: _installment,
                      onChange: (v) {
                        setState(() => _installment = v);
                        _setPref(NotificationPrefs.installment, v);
                      },
                      isDark: isDark,
                    ),
                    _SwitchTile(
                      title: 'ديون العملاء (آجل)',
                      subtitle:
                          'رصيد مدين في بطاقة العميل، وفق إعدادات الدين: عمر الفاتورة، سقف المجموع لكل عميل، وسقف الفاتورة الواحدة',
                      value: _customerDebt,
                      onChange: (v) {
                        setState(() => _customerDebt = v);
                        _setPref(NotificationPrefs.customerDebt, v);
                      },
                      isDark: isDark,
                    ),
                    _SwitchTile(
                      title: 'تسجيل المرتجعات',
                      subtitle: 'آخر مرتجعات مسجّلة (21 يوماً)',
                      value: _returns,
                      onChange: (v) {
                        setState(() => _returns = v);
                        _setPref(NotificationPrefs.returns, v);
                      },
                      isDark: isDark,
                    ),
                    _SwitchTile(
                      title: 'ملخص مبيعات اليوم',
                      subtitle: 'إجمالي فواتير البيع لهذا اليوم (بدون مرتجعات)',
                      value: _dailyReport,
                      onChange: (v) {
                        setState(() => _dailyReport = v);
                        _setPref(NotificationPrefs.dailySummary, v);
                      },
                      isDark: isDark,
                    ),
                    _SwitchTile(
                      title: 'فتح وإغلاق الوردية',
                      subtitle:
                          'إشعار بموظف الوردية والمبالغ (رصيد النظام، الجرد، المضاف، المسحوب، المتبقي)',
                      value: _shiftLifecycle,
                      onChange: (v) {
                        setState(() => _shiftLifecycle = v);
                        _setPref(NotificationPrefs.shiftLifecycle, v);
                      },
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ── مساعدات UI ────────────────────────────────────────────────────────────────
class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChange;
  final bool isDark;
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChange,
    required this.isDark,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: ac.md,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
            blurRadius: ac.isRounded ? 8 : 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        value: value,
        onChanged: onChange,
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: cs.onSurface,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              )
            : null,
        shape: RoundedRectangleBorder(borderRadius: ac.md),
      ),
    );
  }
}
