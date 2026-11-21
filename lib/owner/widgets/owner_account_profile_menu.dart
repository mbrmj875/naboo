import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../providers/owner_command_center_provider.dart';
import '../../screens/license/subscription_plans_screen.dart';
import '../../screens/settings/account_subscription_screen.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/license_service.dart';
import '../../services/print_settings_repository.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_logger.dart';

const _kTeal = Color(0xFF0D9488);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);

/// قائمة حساب المالك في أعلى لوحة القيادة — بريد Gmail، المتجر، الاشتراك، الأجهزة.
class OwnerAccountProfileMenu extends StatefulWidget {
  const OwnerAccountProfileMenu({
    super.key,
    this.iconColor = Colors.white70,
    this.chromeAvatarTrigger = false,
    this.onAfterCloudSync,
    this.onDashboardSyncBusy,
  });

  final Color iconColor;

  /// زر دائري فقط (بدون سهم) — شريط لوحة المالك العلوي.
  final bool chromeAvatarTrigger;

  /// بعد مزامنة السحاب — تحديث KPIs لوحة المالك (بدون زر مكرر في الشريط).
  final Future<void> Function()? onAfterCloudSync;

  /// يُبلّغ اللوحة الأم بحالة المزامنة (شريط الاتصال / banner).
  final void Function(bool busy)? onDashboardSyncBusy;

  @override
  State<OwnerAccountProfileMenu> createState() => _OwnerAccountProfileMenuState();
}

class _OwnerAccountProfileMenuState extends State<OwnerAccountProfileMenu> {
  String _storeTitle = '';
  bool _loadingMeta = false;
  bool _syncBusy = false;
  String? _currentDeviceId;
  Timer? _menuRefreshTimer;

  @override
  void dispose() {
    _menuRefreshTimer?.cancel();
    super.dispose();
  }

  void _stopMenuRefreshTimer() {
    _menuRefreshTimer?.cancel();
    _menuRefreshTimer = null;
  }

  void _startMenuRefreshTimer() {
    _stopMenuRefreshTimer();
    _menuRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_refreshAccountSnapshot());
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadStoreTitle());
    unawaited(_loadCurrentDeviceId());
  }

  Future<void> _loadCurrentDeviceId() async {
    try {
      final id = await LicenseService.instance.getDeviceId();
      if (!mounted) return;
      setState(() => _currentDeviceId = id);
    } catch (e) {
      AppLogger.warn('OwnerAccountProfileMenu', 'getDeviceId failed: $e');
    }
  }

  Future<void> _loadStoreTitle() async {
    try {
      final p = await PrintSettingsRepository.instance.load();
      final title = p.storeTitleLine.trim();
      if (!mounted) return;
      setState(() => _storeTitle = title);
    } catch (e, st) {
      AppLogger.error(
        'OwnerAccountProfileMenu',
        'تعذر تحميل اسم المتجر من إعدادات الطباعة',
        e,
        st,
      );
    }
  }

  Future<void> _refreshAccountSnapshot() async {
    if (_loadingMeta) return;
    setState(() => _loadingMeta = true);
    try {
      final restored =
          await context.read<AuthProvider>().ensureCloudSessionActive();
      if (restored && Supabase.instance.client.auth.currentUser != null) {
        await CloudSyncService.instance.bootstrapForSignedInUser();
        await CloudSyncService.instance.cloudSessionHeartbeat();
      }
      await LicenseService.instance.checkLicense(forceRemote: true);
      if (Supabase.instance.client.auth.currentUser != null) {
        await CloudSyncService.instance.refreshDevices();
      }
      await Future.wait<void>([
        _loadStoreTitle(),
        _loadCurrentDeviceId(),
      ]);
    } catch (e, st) {
      AppLogger.error(
        'OwnerAccountProfileMenu',
        'تعذر تحديث بيانات الحساب',
        e,
        st,
      );
    } finally {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _syncNow(BuildContext context) async {
    if (_syncBusy) return;
    setState(() => _syncBusy = true);
    widget.onDashboardSyncBusy?.call(true);
    try {
      final restored = await context.read<AuthProvider>().ensureCloudSessionActive();
      if (!restored) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذّر استعادة جلسة السحابة تلقائياً. تحقق من الإنترنت ثم أعد المحاولة.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await CloudSyncService.instance.syncNowDetailed(
        forcePull: true,
        forcePush: true,
        forceImportOnPull: true,
      );
      await LicenseService.instance.checkLicense(forceRemote: true);
      await CloudSyncService.instance.refreshDevices();
      if (widget.onAfterCloudSync != null) {
        await widget.onAfterCloudSync!();
      } else if (context.mounted) {
        await context.read<OwnerCommandCenterProvider>().refreshAll(force: true);
      }
      if (!context.mounted) return;
      final err = CloudSyncService.instance.lastError.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err ?? 'تمت المزامنة بنجاح'),
          backgroundColor: err != null ? Colors.red.shade700 : _kTeal,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      widget.onDashboardSyncBusy?.call(false);
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  List<AccountDevice> _sortedDevices(List<AccountDevice> devices) {
    final copy = List<AccountDevice>.from(devices);
    copy.sort((a, b) {
      if (a.isRevoked != b.isRevoked) return a.isRevoked ? 1 : -1;
      final aSeen = a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bSeen = b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bSeen.compareTo(aSeen);
    });
    return copy;
  }

  String? _deviceLimitMessageAr({
    required int activeDevices,
    required int effectiveMax,
  }) {
    if (effectiveMax <= 0 || activeDevices <= effectiveMax) return null;
    return 'لديك $activeDevices أجهزة نشطة بينما حد خطتك $effectiveMax. '
        'افصل جهازاً غير مستخدم من «الحساب والاشتراك»، أو رقِّ الخطة.';
  }

  void _openSubscriptionPlans(BuildContext context) {
    final plan = LicenseService.instance.state.plan;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionPlansScreen(currentPlan: plan),
      ),
    );
  }

  String _cloudEmail(AuthProvider auth) {
    final supa = Supabase.instance.client.auth.currentUser?.email?.trim();
    if (supa != null && supa.isNotEmpty) return supa;
    return auth.email.trim();
  }

  String _primaryTitle(AuthProvider auth, LicenseState lic) {
    if (_storeTitle.isNotEmpty) return _storeTitle;
    final biz = (lic.businessName ?? '').trim();
    if (biz.isNotEmpty) return biz;
    return auth.displayName.trim();
  }

  String _statusLabelAr(LicenseState lic) {
    return switch (lic.status) {
      LicenseStatus.trial => 'تجربة مجانية',
      LicenseStatus.active => 'اشتراك نشط',
      LicenseStatus.expired => 'اشتراك منتهٍ',
      LicenseStatus.suspended => 'موقوف',
      LicenseStatus.restricted => 'مقيّد',
      LicenseStatus.pendingLock => 'بانتظار التفعيل',
      LicenseStatus.offline => 'غير متصل — آخر حالة محفوظة',
      LicenseStatus.checking => 'جاري التحقق…',
      LicenseStatus.none => 'غير مفعّل',
    };
  }

  bool _showUpgradeAction(LicenseState lic) {
    return lic.status == LicenseStatus.trial ||
        lic.status == LicenseStatus.none ||
        lic.status == LicenseStatus.expired ||
        lic.status == LicenseStatus.suspended ||
        lic.status == LicenseStatus.restricted ||
        lic.status == LicenseStatus.pendingLock;
  }

  String? _subscriptionStartLabel(LicenseState lic) {
    if (lic.status == LicenseStatus.trial && lic.trialEndsAt != null) {
      final end = lic.trialEndsAt!;
      final start = end.subtract(const Duration(days: 15));
      return _fmtDate(start);
    }
    return null;
  }

  String? _subscriptionEndLabel(LicenseState lic) {
    if (lic.status == LicenseStatus.trial) {
      return _fmtDate(lic.trialEndsAt);
    }
    if (lic.status == LicenseStatus.active) {
      return _fmtDate(lic.expiresAt);
    }
    if (lic.status == LicenseStatus.expired) {
      return _fmtDate(lic.expiresAt);
    }
    return null;
  }

  int _activeDeviceCount(List<AccountDevice> devices, LicenseState lic) {
    if (devices.isNotEmpty) {
      return devices.where((d) => !d.isRevoked).length;
    }
    return lic.registeredDeviceCount;
  }

  String _formatSyncAgeAr(DateTime? dt) {
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return _fmtDate(dt);
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')}';
  }

  Future<void> _reactivateDevice(BuildContext context, String deviceId) async {
    final err =
        await CloudSyncService.instance.approveDeviceAccess(deviceId);
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await CloudSyncService.instance.refreshDevices();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم السماح بعودة الجهاز'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _initial(String title, String email) {
    final t = title.trim();
    if (t.isNotEmpty) return t.substring(0, 1);
    final e = email.trim();
    if (e.isNotEmpty) return e.substring(0, 1).toUpperCase();
    return '؟';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return ListenableBuilder(
      listenable: LicenseService.instance,
      builder: (context, _) {
        final lic = LicenseService.instance.state;
        final planName = lic.plan?.nameAr ?? '—';
        final email = _cloudEmail(auth);
        final title = _primaryTitle(auth, lic);
        final showUpgrade = _showUpgradeAction(lic);
        final start = _subscriptionStartLabel(lic);
        final end = _subscriptionEndLabel(lic);

        return ValueListenableBuilder<List<AccountDevice>>(
          valueListenable: CloudSyncService.instance.devices,
          builder: (context, deviceList, _) {
            return ValueListenableBuilder<DateTime?>(
              valueListenable: CloudSyncService.instance.lastSyncAt,
              builder: (context, lastSync, _) {
                return ValueListenableBuilder<String?>(
                  valueListenable: CloudSyncService.instance.lastError,
                  builder: (context, syncErr, _) {
                final activeDevices = _activeDeviceCount(deviceList, lic);
                final effectiveMax = lic.effectiveMaxDevices;
                final hasCloudSession =
                    Supabase.instance.client.auth.currentUser != null;
                final overLimit = hasCloudSession &&
                    effectiveMax > 0 &&
                    activeDevices > effectiveMax;
                final revokedCount =
                    deviceList.where((d) => d.isRevoked).length;
                final maxLabel = !hasCloudSession
                    ? '— (جلسة السحابة منتهية)'
                    : effectiveMax == 0
                        ? '$activeDevices نشط (غير محدود)'
                        : '$activeDevices نشط / $effectiveMax';
                final limitMsg = hasCloudSession
                    ? _deviceLimitMessageAr(
                        activeDevices: activeDevices,
                        effectiveMax: effectiveMax,
                      )
                    : 'التطبيق يعمل محلياً فقط. لتسجيل هذا الجهاز والمزامنة: '
                        'سجّل خروج المالك ثم ادخل بالبريد أو Google.';
                final sortedDevices = _sortedDevices(deviceList);

                return PopupMenuButton<_OwnerAccountMenuAction>(
                  tooltip: 'حساب الاشتراك',
                  offset: const Offset(0, 44),
                  constraints: const BoxConstraints(minWidth: 300, maxWidth: 360),
                  color: const Color(0xFF1E293B),
                  surfaceTintColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: AppColors.accentGold.withValues(alpha: 0.45),
                    ),
                  ),
                  onOpened: () {
                    unawaited(_refreshAccountSnapshot());
                    _startMenuRefreshTimer();
                  },
                  onCanceled: _stopMenuRefreshTimer,
                  onSelected: (action) {
                    _stopMenuRefreshTimer();
                    switch (action) {
                      case _OwnerAccountMenuAction.openAccount:
                        openAccountSubscriptionScreen(context);
                      case _OwnerAccountMenuAction.syncNow:
                        unawaited(_syncNow(context));
                      case _OwnerAccountMenuAction.openPlans:
                        _openSubscriptionPlans(context);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<_OwnerAccountMenuAction>(
                      enabled: false,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              _Avatar(initial: _initial(title, email)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title.isNotEmpty ? title : 'حساب المالك',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFF8FAFC),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      email.isNotEmpty ? email : '—',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_loadingMeta)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1, color: Color(0xFF334155)),
                          const SizedBox(height: 10),
                          _InfoRow(
                            label: 'الخطة',
                            value: planName,
                          ),
                          const SizedBox(height: 6),
                          _InfoRow(
                            label: 'الحالة',
                            value: _statusLabelAr(lic),
                          ),
                          if (start != null) ...[
                            const SizedBox(height: 6),
                            _InfoRow(label: 'تاريخ البداية', value: start),
                          ],
                          if (end != null) ...[
                            const SizedBox(height: 6),
                            _InfoRow(label: 'تاريخ الانتهاء', value: end),
                          ],
                          if (lic.daysLeft != null &&
                              (lic.status == LicenseStatus.trial ||
                                  lic.status == LicenseStatus.active)) ...[
                            const SizedBox(height: 6),
                            _InfoRow(
                              label: 'المتبقي',
                              value: '${lic.daysLeft} يوماً',
                            ),
                          ],
                          const SizedBox(height: 6),
                          _InfoRow(
                            label: 'الأجهزة النشطة',
                            value: maxLabel,
                            valueColor: !hasCloudSession
                                ? _kAmber
                                : (overLimit ? _kRed : null),
                          ),
                          if (revokedCount > 0) ...[
                            const SizedBox(height: 6),
                            _InfoRow(
                              label: 'أجهزة مفصولة',
                              value: '$revokedCount',
                              valueColor: const Color(0xFFFCA5A5),
                            ),
                          ],
                          if (limitMsg != null) ...[
                            const SizedBox(height: 8),
                            _LimitBanner(message: limitMsg),
                          ],
                          const SizedBox(height: 6),
                          _InfoRow(
                            label: 'آخر مزامنة',
                            value: _formatSyncAgeAr(lastSync),
                          ),
                          if (syncErr != null && syncErr.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              syncErr,
                              style: const TextStyle(
                                color: Color(0xFFFCA5A5),
                                fontSize: 11,
                                height: 1.35,
                              ),
                            ),
                          ],
                          if (sortedDevices.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'قائمة الأجهزة',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 168),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: sortedDevices.map(
                                    (d) => _DeviceListTile(
                                      device: d,
                                      isCurrent: d.deviceId == _currentDeviceId,
                                      lastSeenLabel:
                                          _formatSyncAgeAr(d.lastSeenAt),
                                      onReactivate: d.isRevoked &&
                                              d.deviceId != _currentDeviceId
                                          ? () => unawaited(
                                                _reactivateDevice(
                                                  context,
                                                  d.deviceId,
                                                ),
                                              )
                                          : null,
                                    ),
                                  ).toList(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    PopupMenuItem<_OwnerAccountMenuAction>(
                      value: _OwnerAccountMenuAction.openAccount,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.manage_accounts_outlined,
                          color: AppColors.accentGold,
                        ),
                        title: const Text(
                          'الحساب والاشتراك',
                          style: TextStyle(
                            color: Color(0xFFF8FAFC),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text(
                          'الأجهزة، المزامنة، وفصل/إعادة السماح',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    PopupMenuItem<_OwnerAccountMenuAction>(
                      value: _OwnerAccountMenuAction.syncNow,
                      enabled: !_syncBusy,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _syncBusy
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(
                                Icons.cloud_sync_outlined,
                                color: _kTeal,
                              ),
                        title: const Text(
                          'مزامنة الآن',
                          style: TextStyle(
                            color: Color(0xFFF8FAFC),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          _syncBusy
                              ? 'جاري السحب والرفع…'
                              : 'سحب آخر لقطة ورفع بيانات هذا الجهاز',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    PopupMenuItem<_OwnerAccountMenuAction>(
                      value: _OwnerAccountMenuAction.openPlans,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          showUpgrade
                              ? Icons.rocket_launch_rounded
                              : Icons.card_membership_outlined,
                          color: showUpgrade
                              ? AppColors.accentGold
                              : const Color(0xFF93C5FD),
                        ),
                        title: Text(
                          showUpgrade ? 'ترقية الاشتراك' : 'تفاصيل الاشتراك',
                          style: const TextStyle(
                            color: Color(0xFFF8FAFC),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          showUpgrade
                              ? 'اختر خطة مدفوعة وفعّل المفتاح'
                              : 'الخطط، التفعيل، والأجهزة',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                  child: widget.chromeAvatarTrigger
                      ? _ChromeAvatarTrigger(initial: _initial(title, email))
                      : _ProfileTrigger(
                          initial: _initial(title, email),
                          iconColor: widget.iconColor,
                        ),
                );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

enum _OwnerAccountMenuAction { openAccount, syncNow, openPlans }

/// زر الحساب في الشريط العلوي — دائرة كحلية بالحرف الأول.
class _ChromeAvatarTrigger extends StatelessWidget {
  const _ChromeAvatarTrigger({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.primary,
        ),
        child: Text(
          initial,
          style: TextStyle(
            color: cs.onPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _ProfileTrigger extends StatelessWidget {
  const _ProfileTrigger({
    required this.initial,
    required this.iconColor,
  });

  final String initial;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.all(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 8, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Avatar(initial: initial, compact: true, borderColor: iconColor),
              Icon(Icons.expand_more, color: iconColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initial,
    this.compact = false,
    this.borderColor,
  });

  final String initial;
  final bool compact;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 28.0 : 40.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.accentGold.withValues(alpha: 0.2),
        border: Border.all(
          color: borderColor ?? AppColors.accentGold.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: AppColors.accentGold,
          fontWeight: FontWeight.w800,
          fontSize: compact ? 13 : 16,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? const Color(0xFFE2E8F0),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _LimitBanner extends StatelessWidget {
  const _LimitBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kAmber.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: _kAmber, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFFDE68A),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  const _DeviceListTile({
    required this.device,
    required this.isCurrent,
    required this.lastSeenLabel,
    this.onReactivate,
  });

  final AccountDevice device;
  final bool isCurrent;
  final String lastSeenLabel;
  final VoidCallback? onReactivate;

  @override
  Widget build(BuildContext context) {
    final statusLabel = device.isRevoked
        ? 'مفصول'
        : (isCurrent ? 'هذا الجهاز' : 'نشط');
    final statusColor = device.isRevoked
        ? _kRed
        : (isCurrent ? _kTeal : const Color(0xFF86EFAC));

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.devices_other_outlined,
            size: 16,
            color: device.isRevoked
                ? const Color(0xFFFCA5A5)
                : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: device.isRevoked
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFE2E8F0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${device.platform.isNotEmpty ? device.platform : '—'} • $lastSeenLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                  ),
                ),
                if (onReactivate != null) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: onReactivate,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'السماح بالعودة',
                      style: TextStyle(fontSize: 10, color: _kTeal),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
