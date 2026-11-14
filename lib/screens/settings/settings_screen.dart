import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'sync_queue_health_screen.dart';

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
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final isOwner = auth.isOwner;

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
                      child: Column(
                        children: [
                          // ── بطاقة الشركة ─────────────────────────────────────────────
                          const _CompanyCard(),
                          const SizedBox(height: 16),
                          // ── المجموعات ────────────────────────────────────────────────
                          _SettingsGroup(
                            title: 'المتجر والحساب',
                            isDark: isDark,
                            items: [
                              if (kIsWeb && WebPwaInstall.isWebSupported)
                                _SettingItem(
                                  icon: Icons.add_to_home_screen_rounded,
                                  iconColor: const Color(0xFF071A36),
                                  title: 'تثبيت نابو على الشاشة الرئيسية',
                                  subtitle: WebPwaInstall.isStandalone()
                                      ? 'التطبيق مثبّت — يفتح بدون شريط المتصفح'
                                      : 'أيقونة مثل التطبيق على هاتفك أو جهازك',
                                  onTap: () {
                                    if (WebPwaInstall.isStandalone()) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'نابو مثبّت مسبقاً على هذا الجهاز.',
                                          ),
                                        ),
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
                                            margin: EdgeInsetsDirectional.all(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              if (isOwner)
                                _SettingItem(
                                  icon: Icons.store_rounded,
                                  iconColor: cs.primary,
                                  title: 'بيانات المتجر',
                                  subtitle:
                                      'الاسم، العنوان، وأرقام الهاتف للإيصال',
                                  onTap: () => _goTo(
                                    context,
                                    const StoreInfoScreen(),
                                    routeId: AppContentRoutes.settingsStoreInfo,
                                    breadcrumbTitle: 'بيانات المتجر',
                                  ),
                                )
                              else
                                _SettingItem(
                                  icon: Icons.storefront_rounded,
                                  iconColor: cs.primary,
                                  title: 'بيانات فرعي',
                                  subtitle:
                                      'اسم فرعك وشعارك وهاتفك — لواتساب والإيصال',
                                  onTap: () => _goTo(
                                    context,
                                    const StoreInfoScreen(
                                      scope: StoreInfoScope.myBranch,
                                    ),
                                    routeId:
                                        AppContentRoutes.settingsMyBranchInfo,
                                    breadcrumbTitle: 'بيانات فرعي',
                                  ),
                                ),
                              _SettingItem(
                                icon: Icons.receipt_long_rounded,
                                iconColor: _kTeal,
                                title: 'إعدادات الفواتير',
                                subtitle:
                                    'رقم البداية، التذييل، الضريبة، الخصم',
                                onTap: () => _goTo(
                                  context,
                                  const _InvoiceSettingsScreen(),
                                  routeId: AppContentRoutes.settingsInvoice,
                                  breadcrumbTitle: 'إعدادات الفواتير',
                                ),
                              ),
                              _SettingItem(
                                icon: Icons.tune_rounded,
                                iconColor: _kAmber,
                                title: 'ميزات المتجر',
                                subtitle:
                                    'العملاء، الولاء، الضريبة، الخصم، الديون، التقسيط، الوزن، الملابس، والخدمات',
                                onTap: () => _goTo(
                                  context,
                                  const BusinessSetupWizardScreen(
                                    openedFromSettings: true,
                                  ),
                                  routeId:
                                      AppContentRoutes.settingsBusinessFeatures,
                                  breadcrumbTitle: 'ميزات المتجر',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _SettingsGroup(
                            title: 'المظهر والإشعارات',
                            isDark: isDark,
                            items: [
                              _SettingItem(
                                icon: Icons.dashboard_customize_rounded,
                                iconColor: _kBlue,
                                title: 'تخصيص الشاشة الرئيسية',
                                subtitle:
                                    'إظهار أو إخفاء أقسام لوحة التحكم وترتيبها بالسحب',
                                onTap: () => _goTo(
                                  context,
                                  const DashboardLayoutSettingsScreen(),
                                  routeId:
                                      AppContentRoutes.settingsDashboardLayout,
                                  breadcrumbTitle: 'تخصيص الشاشة الرئيسية',
                                ),
                              ),
                              _SettingItem(
                                icon: Icons.palette_outlined,
                                iconColor: cs.primary,
                                title: 'ألوان وهوية التطبيق',
                                subtitle:
                                    'مخططات جاهزة، مخصص، وزوايا البطاقات — تُطبَّق على كل الشاشات',
                                onTap: () => _goTo(
                                  context,
                                  const SalePosSettingsScreen(
                                    appearanceOnly: true,
                                  ),
                                  routeId: AppContentRoutes
                                      .settingsSalePosAppearance,
                                  breadcrumbTitle: 'ألوان وهوية التطبيق',
                                ),
                              ),
                              _CompactSnackNotificationsTile(isDark: isDark),
                              _ThemeToggleTile(isDark: isDark),
                              _SettingItem(
                                icon: Icons.language_rounded,
                                iconColor: _kTeal,
                                title: 'اللغة',
                                subtitle: 'العربية',
                                trailing: Text(
                                  'العربية',
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                                onTap: () {},
                              ),
                              _SettingItem(
                                icon: Icons.notifications_rounded,
                                iconColor: _kAmber,
                                title: 'الإشعارات',
                                subtitle: 'تنبيهات المخزون، الفواتير، الأقساط',
                                onTap: () => _goTo(
                                  context,
                                  const _NotificationsScreen(),
                                  routeId:
                                      AppContentRoutes.settingsNotifications,
                                  breadcrumbTitle: 'الإشعارات',
                                ),
                              ),
                              _SettingItem(
                                icon: Icons.print_rounded,
                                iconColor: cs.primary,
                                title: 'إعدادات الطباعة',
                                subtitle: 'حجم الورق، الطابعة الافتراضية',
                                onTap: () => _goTo(
                                  context,
                                  const PrintingScreen(),
                                  routeId:
                                      AppContentRoutes.settingsPrintingInline,
                                  breadcrumbTitle: 'إعدادات الطباعة',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _SettingsGroup(
                            title: 'البيانات والنسخ الاحتياطي',
                            isDark: isDark,
                            items: [
                              _SettingItem(
                                icon: Icons.restore_rounded,
                                iconColor: _kBlue,
                                title: 'استعادة البيانات',
                                subtitle: 'من ملف أو سحابة',
                                onTap: () => _goTo(
                                  context,
                                  const MarketPosImportScreen(),
                                  routeId: AppContentRoutes.settingsRestore,
                                  breadcrumbTitle: 'استيراد مواد وأسعار',
                                ),
                              ),
                              _SettingItem(
                                icon: Icons.sync_problem_rounded,
                                iconColor: _kRed,
                                title: 'حالة المزامنة والعمليات العالقة',
                                subtitle:
                                    'مراقبة pending/failed/dead وإعادة المحاولة',
                                onTap: () => _goTo(
                                  context,
                                  const SyncQueueHealthScreen(),
                                  routeId:
                                      AppContentRoutes.settingsSyncQueueHealth,
                                  breadcrumbTitle:
                                      'حالة المزامنة والعمليات العالقة',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _SettingsGroup(
                            title: 'الاشتراك والدعم',
                            isDark: isDark,
                            items: [
                              ListenableBuilder(
                                listenable: LicenseService.instance,
                                builder: (context, _) {
                                  return _SettingItem(
                                    icon: Icons.star_rounded,
                                    iconColor: _kAmber,
                                    title: 'خطة الاشتراك',
                                    subtitle: _subscriptionRowSubtitle(
                                      LicenseService.instance.state,
                                    ),
                                    onTap: () => _goTo(
                                      context,
                                      const AccountSubscriptionScreen(),
                                      routeId: AppContentRoutes
                                          .settingsSubscriptionAccount,
                                      breadcrumbTitle: 'خطة الاشتراك والحساب',
                                    ),
                                  );
                                },
                              ),
                              _SettingItem(
                                icon: Icons.help_rounded,
                                iconColor: _kBlue,
                                title: 'المساعدة والدعم',
                                subtitle: 'الأسئلة الشائعة والتواصل مع الدعم',
                                onTap: () {},
                              ),
                              _SettingItem(
                                icon: Icons.info_rounded,
                                iconColor: Colors.grey,
                                title: 'عن التطبيق',
                                subtitle: 'الإصدار 1.0.0 · NaBoo Store Manager',
                                onTap: () => _showAbout(context),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
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

  /// يمرّ عبر نفس [Navigator] الرئيسي مع [RouteSettings.name] حتى يحدّث [NavigatorObserver] فتات الخبز.
  void _goTo(
    BuildContext context,
    Widget screen, {
    required String routeId,
    required String breadcrumbTitle,
  }) {
    Navigator.push<void>(
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

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'نابو لإدارة المتاجر',
      applicationVersion: 'الإصدار 1.0.0',
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
          arguments: BreadcrumbMeta(
            isOwner ? 'بيانات المتجر' : 'بيانات فرعي',
          ),
        ),
        builder: (_) => StoreInfoScreen(
          scope: isOwner
              ? StoreInfoScope.workspace
              : StoreInfoScope.myBranch,
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
    final store = _effective ??
        context.watch<PrintSettingsProvider>().data;
    final name = _loading
        ? '…'
        : _storeName(store, isOwner: isOwner);
    final subtitle = _loading
        ? ''
        : _storeSubtitle(store, isOwner: isOwner);

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
              tooltip: isOwner
                  ? 'تعديل بيانات المتجر'
                  : 'تعديل بيانات فرعي',
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
  final VoidCallback onTap;

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
            child: const Icon(Icons.view_sidebar_outlined, color: _kTeal, size: 20),
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
class _InvoiceSettingsScreen extends StatefulWidget {
  const _InvoiceSettingsScreen();
  @override
  State<_InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<_InvoiceSettingsScreen> {
  bool _showTax = true;
  bool _showDiscount = true;
  bool _showLogo = true;
  bool _showFooter = true;
  double _taxRate = 0.0;
  final _startNum = TextEditingController(text: '1');
  final _footer = TextEditingController(text: 'شكراً لتعاملكم معنا');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: _settingsAppBar(
          context,
          'إعدادات الفواتير',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD4AF37),
              ),
              child: const Text(
                'حفظ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: ScreenLayout.of(context).pageHorizontalGap,
            vertical: 16,
          ),
          child: Column(
            children: [
              _SwitchTile(
                title: 'إظهار الضريبة',
                value: _showTax,
                onChange: (v) => setState(() => _showTax = v),
                isDark: isDark,
              ),
              _SwitchTile(
                title: 'إظهار الخصم',
                value: _showDiscount,
                onChange: (v) => setState(() => _showDiscount = v),
                isDark: isDark,
              ),
              _SwitchTile(
                title: 'إظهار الشعار',
                value: _showLogo,
                onChange: (v) => setState(() => _showLogo = v),
                isDark: isDark,
              ),
              _SwitchTile(
                title: 'إظهار التذييل',
                value: _showFooter,
                onChange: (v) => setState(() => _showFooter = v),
                isDark: isDark,
              ),
              const SizedBox(height: 16),
              // نسبة الضريبة
              _SectionCard(
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'نسبة الضريبة',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: cs.primary,
                        inactiveTrackColor: cs.surfaceContainerHighest,
                        thumbColor: cs.primary,
                        overlayColor: cs.primary.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        value: _taxRate,
                        min: 0,
                        max: 25,
                        divisions: 25,
                        label: '${_taxRate.round()}%',
                        onChanged: (v) => setState(() => _taxRate = v),
                      ),
                    ),
                    Text(
                      '${_taxRate.round()}%',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Field(
                controller: _startNum,
                label: 'رقم بداية الفواتير',
                icon: Icons.tag_rounded,
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: 12),
              _Field(
                controller: _footer,
                label: 'نص التذييل',
                icon: Icons.notes_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// إعدادات الإشعارات
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
                    const SizedBox(height: 14),
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
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboard;
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: ac.sm),
        enabledBorder: OutlineInputBorder(
          borderRadius: ac.sm,
          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.65)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: ac.sm,
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

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

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _SectionCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: ac.md,
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.05),
            blurRadius: ac.isRounded ? 8 : 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: cs.onSurface),
        child: child,
      ),
    );
  }
}
