import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/idle_timeout_provider.dart';
import '../../providers/ui_feedback_settings_provider.dart';
import '../../screens/license/subscription_plans_screen.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/license_service.dart';
import '../../services/mac_style_settings_prefs.dart';
import '../../widgets/mac_style_settings_panel.dart';
import '../../navigation/content_navigation.dart';
import '../../theme/app_corner_style.dart';
import '../../utils/screen_layout.dart';
import '../invoices/sale_pos_settings_screen.dart';
import '../printing/printing_screen.dart';
import 'dashboard_layout_settings_screen.dart';

const _kTeal = Color(0xFF0D9488);
const _kGreen = Color(0xFF22C55E);
const _kAmber = Color(0xFFF59E0B);
const _kRed = Color(0xFFEF4444);

/// شريط عنوان إعدادات يتبع [ColorScheme.primary] — نفس هوية الثيم في باقي التطبيق.
AppBar _settingsAppBar(
  BuildContext context,
  String title, {
  List<Widget>? actions,
}) {
  final cs = Theme.of(context).colorScheme;
  return AppBar(
    backgroundColor: cs.primary,
    foregroundColor: cs.onPrimary,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 18,
        color: cs.onPrimary,
      ),
    ),
    iconTheme: IconThemeData(color: cs.onPrimary),
    actionsIconTheme: IconThemeData(color: cs.onPrimary),
    actions: actions,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.showAppBar = true});

  /// عند `false` يُعرض المحتوى فقط (مثلاً داخل نافذة منبثقة بشريط عنوان خارجي).
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: showAppBar ? _settingsAppBar(context, 'الإعدادات') : null,
        body: LayoutBuilder(
          builder: (context, constraints) {
            /// يمنع كسر [ListTile] عند عرض أقل من ~72 (مثلاً أثناء أنيميشن التصغير).
            final minW = math.max(constraints.maxWidth, 300.0);
            return Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: SizedBox(
                    width: minW,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // ── بطاقة الشركة ─────────────────────────────────────────────
                          _CompanyCard(),
                          const SizedBox(height: 16),
                          // ── المجموعات ────────────────────────────────────────────────
                          _SettingsGroup(
                            title: 'المتجر والحساب',
                            isDark: isDark,
                            items: [
                              _SettingItem(
                                icon: Icons.store_rounded,
                                iconColor: cs.primary,
                                title: 'بيانات المتجر',
                                subtitle: 'الاسم، العنوان، الشعار، الفرع',
                                onTap: () => _goTo(
                                  context,
                                  const _StoreInfoScreen(),
                                  routeId: AppContentRoutes.settingsStoreInfo,
                                  breadcrumbTitle: 'بيانات المتجر',
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
                                icon: Icons.inventory_2_rounded,
                                iconColor: _kAmber,
                                title: 'إعدادات المخزون',
                                subtitle: 'التنبيهات، الوحدات، الباركود',
                                onTap: () {},
                              ),
                              _SettingItem(
                                icon: Icons.local_offer_rounded,
                                iconColor: _kGreen,
                                title: 'العملات والأسعار',
                                subtitle: 'عملة العرض، صيغة الأرقام',
                                onTap: () {},
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _SettingsGroup(
                            title: 'المستخدمون والصلاحيات',
                            isDark: isDark,
                            items: [
                              _SettingItem(
                                icon: Icons.group_rounded,
                                iconColor: _kBlue,
                                title: 'المستخدمون',
                                subtitle: 'إدارة الموظفين وصلاحياتهم',
                                onTap: () {},
                              ),
                              _SettingItem(
                                icon: Icons.admin_panel_settings_rounded,
                                iconColor: cs.primary,
                                title: 'الأدوار والصلاحيات',
                                subtitle: 'تخصيص الوصول لكل دور',
                                onTap: () {},
                              ),
                              _SettingItem(
                                icon: Icons.lock_rounded,
                                iconColor: _kRed,
                                title: 'كلمة المرور والأمان',
                                subtitle:
                                    'تغيير كلمة المرور والمصادقة الثنائية',
                                onTap: () {},
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
                                  routeId:
                                      AppContentRoutes.settingsSalePosAppearance,
                                  breadcrumbTitle: 'ألوان وهوية التطبيق',
                                ),
                              ),
                              _CompactSnackNotificationsTile(isDark: isDark),
                              _ThemeToggleTile(isDark: isDark),
                              if (!context.screenLayout.isHandsetForLayout)
                                _MacStyleSettingsPanelTile(isDark: isDark),
                              _IdleTimeoutTile(isDark: isDark),
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
                                icon: Icons.backup_rounded,
                                iconColor: _kGreen,
                                title: 'النسخ الاحتياطي',
                                subtitle: 'آخر نسخة: لم يتم بعد',
                                onTap: () {},
                              ),
                              _SettingItem(
                                icon: Icons.restore_rounded,
                                iconColor: _kBlue,
                                title: 'استعادة البيانات',
                                subtitle: 'من ملف أو سحابة',
                                onTap: () {},
                              ),
                              _SettingItem(
                                icon: Icons.download_rounded,
                                iconColor: _kTeal,
                                title: 'تصدير البيانات',
                                subtitle: 'Excel، CSV، PDF',
                                onTap: () {},
                              ),
                              _SettingItem(
                                icon: Icons.delete_outline_rounded,
                                iconColor: _kRed,
                                title: 'مسح بيانات المعاينة',
                                subtitle: 'حذف البيانات التجريبية',
                                onTap: () => _confirmDelete(context),
                                isDestructive: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _SettingsGroup(
                            title: 'الاشتراك والدعم',
                            isDark: isDark,
                            items: [
                              _SettingItem(
                                icon: Icons.star_rounded,
                                iconColor: _kAmber,
                                title: 'خطة الاشتراك',
                                subtitle:
                                    'الحساب، الأجهزة، والمزامنة التلقائية',
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.tertiary.withValues(alpha: 0.22),
                                    borderRadius: context.appCorners.sm,
                                  ),
                                  child: Text(
                                    'تجريبية',
                                    style: TextStyle(
                                      color: cs.tertiary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                onTap: () => _goTo(
                                  context,
                                  const _AccountSubscriptionScreen(),
                                  routeId: AppContentRoutes
                                      .settingsSubscriptionAccount,
                                  breadcrumbTitle: 'خطة الاشتراك والحساب',
                                ),
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

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text(
          'هل أنت متأكد من حذف بيانات المعاينة؟ لا يمكن التراجع عن هذا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'NaBoo Store Manager',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2026 NaBoo. جميع الحقوق محفوظة.',
    );
  }
}

// ── بطاقة الشركة ──────────────────────────────────────────────────────────────
class _CompanyCard extends StatelessWidget {
  const _CompanyCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    return GestureDetector(
      onLongPress: () {
        // مدخل مخفي لأدوات الاختبار (Dev only screen will block in release anyway).
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فتح أدوات الاختبار…'),
            duration: Duration(milliseconds: 900),
          ),
        );
        Navigator.of(context, rootNavigator: true).pushNamed('/dev/stress');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
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
          // الشعار
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: cs.onPrimary.withValues(alpha: 0.18),
              borderRadius: ac.md,
            ),
            child: Icon(
              Icons.store_rounded,
              color: cs.onPrimary,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          // بيانات الشركة
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'متجر البصرة',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'البصرة، العراق',
                  style: TextStyle(
                    color: cs.onPrimary.withValues(alpha: 0.82),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.onPrimary.withValues(alpha: 0.18),
                    borderRadius: ac.sm,
                  ),
                  child: Text(
                    'نسخة تجريبية',
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_rounded, color: cs.onPrimary),
            onPressed: () {},
          ),
          ],
        ),
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

// ── عنصر الإعداد ──────────────────────────────────────────────────────────────
class _SettingItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool isDestructive;

  const _SettingItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final titleColor = isDestructive ? cs.error : null;
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
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: titleColor ?? cs.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing:
          trailing ??
          Icon(Icons.chevron_left_rounded,
              color: cs.onSurfaceVariant, size: 20),
      onTap: onTap,
    );
  }
}

// ── مدة وضع السكون ────────────────────────────────────────────────────────────
class _IdleTimeoutTile extends StatelessWidget {
  final bool isDark;
  const _IdleTimeoutTile({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Consumer<IdleTimeoutProvider>(
      builder: (context, idle, _) {
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
              Icons.nights_stay_rounded,
              color: _kTeal,
              size: 20,
            ),
          ),
          title: const Text(
            'وضع السكون',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            'بعد عدم النشاط: ${idle.currentLabel}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          trailing: PopupMenuButton<int>(
            initialValue: idle.minutes,
            onSelected: (m) =>
                context.read<IdleTimeoutProvider>().setMinutes(m),
            itemBuilder: (ctx) => IdleTimeoutProvider.options
                .map(
                  (m) => PopupMenuItem<int>(
                    value: m,
                    child: Text(IdleTimeoutProvider.labelForMinutes(m)),
                  ),
                )
                .toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    idle.currentLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    color: Colors.grey.shade600,
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
            child: Icon(Icons.view_sidebar_outlined, color: _kTeal, size: 20),
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

class _MacStyleSettingsPanelTile extends StatefulWidget {
  final bool isDark;
  const _MacStyleSettingsPanelTile({required this.isDark});

  @override
  State<_MacStyleSettingsPanelTile> createState() =>
      _MacStyleSettingsPanelTileState();
}

class _MacStyleSettingsPanelTileState
    extends State<_MacStyleSettingsPanelTile> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    MacStyleSettingsPrefs.isMacStylePanelEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    if (_enabled == null) {
      return const SizedBox(height: 52);
    }
    final on = _enabled!;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.12),
          borderRadius: ac.sm,
        ),
        child: Icon(
          on ? Icons.picture_in_picture_alt_rounded : Icons.view_agenda_rounded,
          color: cs.primary,
          size: 20,
        ),
      ),
      title: const Text(
        'النافذة العائمة (macOS)',
        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        on
            ? 'يمكن فتح عدة نوافذ معاً؛ التصغير الأصفر يضع بلاطة أسفل الشاشة بأيقونة كل صفحة — عطّلها لفتحها داخل المحتوى'
            : 'تُفتح هذه الشاشات داخل المحتوى. فعّل الخيار لاستخدام النوافذ العائمة والبلاطات',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white70 : Colors.grey.shade700,
          height: 1.35,
        ),
      ),
      trailing: Switch(
        value: on,
        onChanged: (v) async {
          setState(() => _enabled = v);
          await MacStyleSettingsPrefs.setMacStylePanelEnabled(v);
          if (!v && context.mounted) {
            dismissMacFloatingOverlayIfAny();
          }
        },
      ),
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
// ── الحساب والاشتراك ─────────────────────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

class _AccountSubscriptionScreen extends StatefulWidget {
  const _AccountSubscriptionScreen();

  @override
  State<_AccountSubscriptionScreen> createState() =>
      _AccountSubscriptionScreenState();
}

class _AccountSubscriptionScreenState
    extends State<_AccountSubscriptionScreen> {
  bool _busy = false;
  String? _message;
  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    LicenseService.instance.getDeviceId().then((id) {
      if (!mounted) return;
      setState(() => _currentDeviceId = id);
    });
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await CloudSyncService.instance.refreshDevices();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    await CloudSyncService.instance.syncNow();
    final err = CloudSyncService.instance.lastError.value;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = err ?? 'تمت المزامنة بنجاح';
    });
  }

  Future<void> _approveDevice(AccountDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('السماح بالعودة'),
          content: Text(
            'هل تسمح لجهاز «${d.deviceName}» بتسجيل الدخول مرة أخرى؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('موافقة'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final err = await CloudSyncService.instance.approveDeviceAccess(d.deviceId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = err ?? 'تم السماح للجهاز بالعودة';
    });
  }

  Future<void> _removeDevice(AccountDevice d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('فصل الجهاز'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'الجهاز: ${d.deviceName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  'سيتم إنهاء الجلسة على ذلك الجهاز فورًا (إن كان متصلاً)، ولن يستطيع '
                  'تسجيل الدخول حتى تضغط «السماح بالعودة» من هنا.',
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: _kRed,
              ),
              child: const Text('فصل الآن'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    final err = await CloudSyncService.instance.removeDevice(d.deviceId);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = err ?? 'تم فصل الجهاز بنجاح';
    });
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final plan = LicenseService.instance.state.plan ?? SubscriptionPlan.basic;
    final auth = context.watch<AuthProvider>();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: _settingsAppBar(context, 'الحساب والاشتراك'),
        body: ListenableBuilder(
          listenable: LicenseService.instance,
          builder: (context, _) {
            final lic = LicenseService.instance.state;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
            _SectionCard(
              isDark: Theme.of(context).brightness == Brightness.dark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'بيانات الحساب',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text('المستخدم: ${auth.displayName}'),
                  const SizedBox(height: 6),
                  Text('البريد: ${auth.email.isEmpty ? '—' : auth.email}'),
                  const SizedBox(height: 6),
                  Text('الخطة الحالية: ${plan.nameAr}'),
                  const SizedBox(height: 6),
                  Text('حد الأجهزة: ${plan.devicesLabel}'),
                ],
              ),
            ),
            if (lic.status == LicenseStatus.trial &&
                lic.trialEndsAt != null) ...[
              const SizedBox(height: 12),
              _SectionCard(
                isDark: Theme.of(context).brightness == Brightness.dark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'التجربة المجانية',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'الأيام المتبقية: ${lic.daysLeft ?? 0} من 15',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'تنتهي في: ${_fmtDate(lic.trialEndsAt)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _SectionCard(
              isDark: Theme.of(context).brightness == Brightness.dark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'الأجهزة المرتبطة بالحساب',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _busy ? null : _refresh,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'تحديث',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<List<AccountDevice>>(
                    valueListenable: CloudSyncService.instance.devices,
                    builder: (context, list, _) {
                      if (_busy && list.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (list.isEmpty) {
                        return const Text('لا توجد أجهزة مسجّلة بعد.');
                      }
                      return Column(
                        children: list.map((d) {
                          final isCurrent = d.deviceId == _currentDeviceId;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.devices_other_outlined),
                            title: Text(d.deviceName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${d.platform} • آخر نشاط: ${_fmtDate(d.lastSeenAt)}',
                                ),
                                if (d.isRevoked)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'مفصول — لا يمكنه الدخول حتى الموافقة',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _kRed.withValues(alpha: 0.9),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: isCurrent
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _kTeal.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'هذا الجهاز',
                                      style: TextStyle(
                                        color: _kTeal,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                : d.isRevoked
                                    ? TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _approveDevice(d),
                                        child: const Text('سماح بالعودة'),
                                      )
                                    : IconButton(
                                        tooltip: 'فصل الجهاز',
                                        onPressed: _busy
                                            ? null
                                            : () => _removeDevice(d),
                                        icon: const Icon(
                                          Icons.link_off_rounded,
                                          color: _kRed,
                                        ),
                                      ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              isDark: Theme.of(context).brightness == Brightness.dark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'المزامنة التلقائية',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تُرفع من كل جهاز نسخة كاملة من قاعدة البيانات؛ الأحدث في السحابة هي التي تُستورد على الجهاز الآخر بعد «مزامنة الآن» أو خلال نحو دقيقة. ليست لحظية لكل إدخال. يجب تنفيذ ملف SQL للمزامنة في Supabase، والإنترنت مفعّل.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String?>(
                    valueListenable: CloudSyncService.instance.lastError,
                    builder: (context, err, _) {
                      if (err == null || err.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          err,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: _kRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _syncNow,
                      icon: const Icon(Icons.sync),
                      label: const Text('مزامنة الآن'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.primary,
                        foregroundColor:
                            Theme.of(context).colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'آخر مزامنة: ${_fmtDate(CloudSyncService.instance.lastSyncAt.value)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _message!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _message == 'تمت المزامنة بنجاح'
                            ? Colors.green
                            : _kRed,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push<void>(
                    context,
                    FastContentPageRoute(
                      settings: const RouteSettings(
                        name: AppContentRoutes.subscriptionPlans,
                        arguments: BreadcrumbMeta('خطط الاشتراك'),
                      ),
                      builder: (_) =>
                          SubscriptionPlansScreen(currentPlan: plan),
                    ),
                  );
                },
                icon: const Icon(Icons.upgrade_outlined),
                label: const Text('عرض خطط الاشتراك'),
              ),
            ),
          ],
            );
          },
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ── شاشات فرعية للإعدادات ─────────────────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════

/// إعدادات المتجر
class _StoreInfoScreen extends StatefulWidget {
  const _StoreInfoScreen();
  @override
  State<_StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends State<_StoreInfoScreen> {
  final _name = TextEditingController(text: 'متجر البصرة');
  final _address = TextEditingController(text: 'البصرة، العراق');
  final _phone = TextEditingController(text: '07xxxxxxxxx');
  final _taxNo = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: _settingsAppBar(
          context,
          'بيانات المتجر',
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: cs.onPrimary),
              child: const Text(
                'حفظ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // شعار المتجر
              Center(
                child: Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.store_rounded,
                        size: 44,
                        color: cs.primary,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.camera_alt_rounded,
                          size: 16,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _Field(
                controller: _name,
                label: 'اسم المتجر',
                icon: Icons.store_rounded,
              ),
              const SizedBox(height: 14),
              _Field(
                controller: _address,
                label: 'العنوان',
                icon: Icons.location_on_rounded,
              ),
              const SizedBox(height: 14),
              _Field(
                controller: _phone,
                label: 'رقم الهاتف',
                icon: Icons.phone_rounded,
                keyboard: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              _Field(
                controller: _taxNo,
                label: 'الرقم الضريبي',
                icon: Icons.numbers_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
              style: TextButton.styleFrom(foregroundColor: cs.onPrimary),
              child: const Text(
                'حفظ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
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
                        inactiveTrackColor:
                            cs.surfaceContainerHighest,
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
    final defDays =
        (p.getInt(NotificationPrefs.defaultExpiryAlertDays) ?? 14).clamp(1, 365);
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
                padding: const EdgeInsets.all(16),
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
                        decoration: InputDecoration(
                          labelText: 'أيام التنبيه الافتراضية',
                          hintText: 'مثال: 14',
                          border: const OutlineInputBorder(),
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
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
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
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
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
