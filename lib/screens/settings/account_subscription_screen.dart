import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../navigation/content_navigation.dart';
import '../../providers/auth_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/license_service.dart';
import '../../theme/app_corner_style.dart';
import '../../utils/screen_layout.dart';
import '../license/subscription_plans_screen.dart';

const _kTeal = Color(0xFF0D9488);
const _kRed = Color(0xFFEF4444);

/// يفتح شاشة الحساب والاشتراك — من الإعدادات أو لوحة المالك.
void openAccountSubscriptionScreen(BuildContext context) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(
        name: AppContentRoutes.settingsSubscriptionAccount,
      ),
      builder: (_) => const AccountSubscriptionScreen(),
    ),
  );
}

/// الحساب، الأجهزة، المزامنة، وخطط الاشتراك.
class AccountSubscriptionScreen extends StatefulWidget {
  const AccountSubscriptionScreen({super.key});

  @override
  State<AccountSubscriptionScreen> createState() =>
      _AccountSubscriptionScreenState();
}

class _AccountSubscriptionScreenState extends State<AccountSubscriptionScreen> {
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LicenseService.instance.checkLicense(forceRemote: true);
    });
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await LicenseService.instance.checkLicense(forceRemote: true);
      await CloudSyncService.instance.registerCurrentDevice();
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
    await CloudSyncService.instance.syncNow(
      forcePull: true,
      forcePush: true,
      forceImportOnPull: true,
    );
    await LicenseService.instance.checkLicense(forceRemote: true);
    await CloudSyncService.instance.refreshDevices();
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
                  style: TextStyle(color: Colors.grey.shade800, height: 1.45),
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
              style: FilledButton.styleFrom(backgroundColor: _kRed),
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

  String _cloudEmail(AuthProvider auth) {
    final supa = Supabase.instance.client.auth.currentUser?.email?.trim();
    if (supa != null && supa.isNotEmpty) return supa;
    return auth.email.trim();
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _effectiveDeviceCapLabel(LicenseState lic) {
    switch (lic.status) {
      case LicenseStatus.none:
      case LicenseStatus.checking:
        return '—';
      default:
        break;
    }
    if (lic.maxDevices == 0) return 'غير محدود';
    return '${lic.maxDevices} أجهزة';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final email = _cloudEmail(auth);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: _accountAppBar(context),
        body: ListenableBuilder(
          listenable: LicenseService.instance,
          builder: (context, _) {
            final lic = LicenseService.instance.state;
            final displayPlan = lic.plan;
            final gap = ScreenLayout.of(context).pageHorizontalGap;
            return ListView(
              padding: EdgeInsets.symmetric(horizontal: gap, vertical: 16),
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
                      Text('البريد: ${email.isEmpty ? '—' : email}'),
                      const SizedBox(height: 6),
                      Text('الخطة الحالية: ${displayPlan?.nameAr ?? '—'}'),
                      const SizedBox(height: 6),
                      Text('حد الأجهزة: ${_effectiveDeviceCapLabel(lic)}'),
                      if (lic.status == LicenseStatus.active ||
                          lic.status == LicenseStatus.trial) ...[
                        const SizedBox(height: 6),
                        Text(
                          'الأجهزة المسجّلة: ${lic.devicesInfo}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
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
                if (lic.status == LicenseStatus.active) ...[
                  const SizedBox(height: 12),
                  _SectionCard(
                    isDark: Theme.of(context).brightness == Brightness.dark,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الاشتراك',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        if (lic.expiresAt != null) ...[
                          Text(
                            'ينتهي الاشتراك في: ${_fmtDate(lic.expiresAt)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (lic.daysLeft != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'متبقٍ تقريباً: ${lic.daysLeft} يوماً',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ] else
                          const Text(
                            'اشتراك مفعّل بلا تاريخ انتهاء محدد في السحابة.',
                            style: TextStyle(fontSize: 14),
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
                                leading: const Icon(
                                  Icons.devices_other_outlined,
                                ),
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                              style: const TextStyle(
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
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'آخر مزامنة: ${_fmtDate(CloudSyncService.instance.lastSyncAt.value)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
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
                              SubscriptionPlansScreen(currentPlan: displayPlan),
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

AppBar _accountAppBar(BuildContext context) {
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
      'الحساب والاشتراك',
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
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, required this.isDark});

  final Widget child;
  final bool isDark;

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
