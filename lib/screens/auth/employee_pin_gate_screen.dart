import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../services/auth/pin_attempt_guard.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../services/session_resume_context.dart';
import '../../theme/design_tokens.dart';
import '../../utils/auth_validators.dart';
import '../../utils/pin_input_constraints.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/double_back_to_exit_scope.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/secure_screen.dart';
import '../settings/sync_queue_health_screen.dart';
import '../users/user_form_screen.dart';

class EmployeePinGateScreen extends StatefulWidget {
  const EmployeePinGateScreen({super.key});

  @override
  State<EmployeePinGateScreen> createState() => _EmployeePinGateScreenState();
}

class _EmployeePinGateScreenState extends State<EmployeePinGateScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  bool _loading = true;
  bool _cloudHydrating = false;
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _selectedUser;

  String _pin = '';
  bool _verifying = false;
  bool _obscureOwnerPin = true;
  Timer? _usersReloadDebounce;
  bool _bootstrapDone = false;
  bool _signOutBusy = false;

  /// قفل حارس المحاولات للمستخدم المحدّد حالياً (null = غير مقفول).
  Duration? _lockRemaining;
  Timer? _lockTicker;

  @override
  void initState() {
    super.initState();
    CloudSyncService.instance.remoteImportGeneration.addListener(_onCloudImport);
    unawaited(_bootstrapUsers());
  }

  @override
  void dispose() {
    _usersReloadDebounce?.cancel();
    _lockTicker?.cancel();
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onCloudImport,
    );
    super.dispose();
  }

  /// يقرأ حالة قفل الحارس للمستخدم المحدّد ويشغّل عدّاداً تنازلياً حياً.
  Future<void> _refreshGuardLock() async {
    final user = _selectedUser;
    if (user == null) return;
    final userId = (user['id'] as num).toInt();
    final remaining =
        await PinAttemptGuard.remainingLock(PinAttemptGuard.userScope(userId));
    if (!mounted) return;
    setState(() => _lockRemaining = remaining);
    _lockTicker?.cancel();
    if (remaining == null) return;
    _lockTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final current = _lockRemaining;
      if (current == null || current <= const Duration(seconds: 1)) {
        timer.cancel();
        setState(() => _lockRemaining = null);
      } else {
        setState(() => _lockRemaining = current - const Duration(seconds: 1));
      }
    });
  }

  void _onCloudImport() {
    if (!_bootstrapDone) return;
    _usersReloadDebounce?.cancel();
    _usersReloadDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(_reloadUsersAfterCloudImport());
    });
  }

  Future<void> _reloadUsersAfterCloudImport() async {
    await _db.reconcileUserDirectoryAfterCloudImport(
      preferSupabaseUid: Supabase.instance.client.auth.currentUser?.id,
    );
    if (!mounted) return;
    await _loadUsers(showLoading: false);
  }

  Future<void> _bootstrapUsers() async {
    // نتجنّب ترطيباً مزدوجاً: إذا سبق أن سُحبت بيانات السحابة للتوّ (مثلاً بعد
    // تسجيل دخول Google مباشرةً) لا نُعيد الترطيب الكامل هنا (GAP-2 / S7).
    if (Supabase.instance.client.auth.currentUser != null &&
        !CloudSyncService.instance.hasFreshCloudPull()) {
      if (!mounted) return;
      setState(() => _cloudHydrating = true);
      try {
      await context.read<AuthProvider>().hydrateCloudAccountData(
        timeout: const Duration(seconds: 15),
        forcePull: true,
        forceImportOnPull: true,
      );
      } finally {
        if (mounted) setState(() => _cloudHydrating = false);
      }
    }
    if (!mounted) return;
    _bootstrapDone = true;
    await _db.reconcileUserDirectoryAfterCloudImport(
      preferSupabaseUid: Supabase.instance.client.auth.currentUser?.id,
    );
    await _loadUsers();
    await _maybeRedirectOwnerPinRestore();
  }

  Future<void> _maybeRedirectOwnerPinRestore() async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final auth = context.read<AuthProvider>();
    final row = await auth.getLocalOwnerRow();
    if (row == null) return;
    final localId = (row['id'] as num).toInt();
    if (!await auth.cloudHasSecretButLocalEmpty(localId)) return;
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushReplacementNamed('/owner-pin-restore-otp'),
    );
  }

  Future<void> _openOwnerPinRestore() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سجّل الدخول بحساب Google أولاً لاستعادة رمز PIN'),
        ),
      );
      return;
    }
    unawaited(
      Navigator.of(context).pushNamed('/owner-pin-restore-otp'),
    );
  }

  Future<void> _loadUsers({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    final list = await _db.listActiveUsersForEmployeeGate();
    final hintId = await SessionResumeContext.lastUserIdHint();
    Map<String, dynamic>? preselect;
    if (hintId != null) {
      for (final u in list) {
        if ((u['id'] as num).toInt() == hintId) {
          preselect = u;
          break;
        }
      }
    }
    if (kDebugMode) {
      debugPrint('[EmployeePinGate] loaded ${list.length} active users');
    }
    if (!mounted) return;
    setState(() {
      _users = list;
      _loading = false;
      if (preselect != null) {
        _selectedUser = preselect;
        _pin = '';
      }
    });
    if (preselect != null) {
      unawaited(_refreshGuardLock());
    }
  }

  void _onUserTap(Map<String, dynamic> user) {
    setState(() {
      _selectedUser = user;
      _pin = '';
      _lockRemaining = null;
    });
    unawaited(_refreshGuardLock());
  }

  void _onPinDigit(String digit) {
    if (_verifying || _lockRemaining != null || _pin.length >= 4) return;
    setState(() {
      _pin += digit;
    });
    if (_pin.length == 4) {
      unawaited(_verifyPin());
    }
  }

  void _onPinDelete() {
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  Future<void> _verifyPin() async {
    final role = _selectedUser!['role'] as String? ?? 'staff';
    if (_pin.length < 4) return;

    final userId = (_selectedUser!['id'] as num).toInt();
    final guardScope = PinAttemptGuard.userScope(userId);

    final locked = await PinAttemptGuard.remainingLock(guardScope);
    if (locked != null) {
      if (!mounted) return;
      setState(() => _pin = '');
      await _refreshGuardLock();
      return;
    }

    setState(() => _verifying = true);

    final isValid = await _db.verifyPinForUser(userId, _pin);

    if (!mounted) return;

    if (isValid) {
      await PinAttemptGuard.recordSuccess(guardScope);
      await _activateUser(userId);
      return;
    }

    // للمالك: إذا PIN على السحابة ولم يُستورد محلياً (ويب/جهاز جديد) → OTP
    if (role == 'owner') {
      final auth = context.read<AuthProvider>();
      if (await auth.cloudHasSecretButLocalEmpty(userId)) {
        if (!mounted) return;
        setState(() => _verifying = false);
        unawaited(
          Navigator.of(context).pushNamed('/owner-pin-restore-otp'),
        );
        return;
      }
      final supabaseOk = await auth.signInOwnerFromEmployeeGate(
        _selectedUser!,
        _pin,
      );
      if (!mounted) return;
      if (supabaseOk) {
        await PinAttemptGuard.recordSuccess(guardScope);
        if (!mounted) return;
        unawaited(Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false));
        return;
      }
    }

    // فشل كل الطرق — تسجيل المحاولة لدى الحارس
    final newLock = await PinAttemptGuard.recordFailure(
      guardScope,
      userId: userId,
      username: _selectedUser?['username'] as String?,
    );
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _pin = '';
    });
    if (newLock != null) {
      await _refreshGuardLock();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('رمز PIN غير صحيح، يرجى المحاولة مرة أخرى'),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  Future<void> _activateUser(int userId) async {
    final auth = context.read<AuthProvider>();
    final activated = await auth.setLocalAuthUser(userId);
    if (!mounted) return;
    if (!activated) {
      setState(() {
        _verifying = false;
        _pin = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تفعيل الجلسة، حاول مرة أخرى')),
      );
      return;
    }
    final role = (_selectedUser?['role'] as String?) ?? 'staff';
    final target = await SessionResumeContext.resolveRootRouteAfterPin(
      userId: userId,
      role: role,
    );
    unawaited(
      Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false),
    );
  }

  Future<void> _ownerLogout() async {
    final auth = context.read<AuthProvider>();
    // نستخدم lockSession بدلاً من logout الكامل حتى لا تُمسح قاعدة البيانات
    await auth.lockSession();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Map<String, dynamic>? _ownerUserRow() {
    for (final u in _users) {
      if ((u['role'] as String?) == 'owner') return u;
    }
    return null;
  }

  Future<void> _confirmPermanentAccountSignOut() async {
    if (_signOutBusy) return;

    final ownerUser = _ownerUserRow();
    if (ownerUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر العثور على حساب المالك للتحقق'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PermanentSignOutConfirmDialog(ownerUser: ownerUser),
    );
    if (verified != true || !mounted) return;

    final ownerId = (ownerUser['id'] as num?)?.toInt();
    final ownerName = (ownerUser['displayName'] as String?)?.trim().isNotEmpty ==
            true
        ? (ownerUser['displayName'] as String).trim()
        : (ownerUser['username'] as String?)?.trim();

    await _attemptPermanentSignOut(
      allowOwnerEmergencyOpenShiftLogout: false,
      allowUnsyncedDataLoss: false,
      ownerVerified: true,
      ownerUserId: ownerId,
      ownerUsername: ownerName,
    );
  }

  /// محاولة فعلية للخروج النهائي. تلتقط StateError من حراس
  /// `_assertNoOpenShiftForLogout` / `_assertNoBlockingSyncQueue` وتعرض
  /// خياراً للمالك بتجاوز الحارس مع تسجيل audit (عبر PR-3).
  ///
  /// [ownerVerified]: true بعد التحقق من رمز المالك على شاشة البوابة — لأن
  /// `lockSession()` يُصفّر `auth.isOwner` بينما الجهاز ما زال مربوطاً بالمالك.
  Future<void> _attemptPermanentSignOut({
    required bool allowOwnerEmergencyOpenShiftLogout,
    required bool allowUnsyncedDataLoss,
    bool ownerVerified = false,
    int? ownerUserId,
    String? ownerUsername,
  }) async {
    if (!mounted) return;
    setState(() => _signOutBusy = true);
    try {
      final auth = context.read<AuthProvider>();
      final serverError = await auth.signOutPermanentlyFromDevice(
        allowOwnerEmergencyOpenShiftLogout: allowOwnerEmergencyOpenShiftLogout,
        allowUnsyncedDataLoss: allowUnsyncedDataLoss,
        ownerEmergencyVerified: ownerVerified,
        ownerEmergencyUserId: ownerUserId,
        ownerEmergencyUsername: ownerUsername,
      );
      if (!mounted) return;
      if (serverError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(serverError),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final canEmergencyOverride = auth.isOwner || ownerVerified;
      final message = e.message;
      final wantsOverride = await _askOverrideDialog(
        message: message,
        canEmergencyOverride: canEmergencyOverride,
        onOpenSyncQueue: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SyncQueueHealthScreen(),
            ),
          );
        },
      );
      if (!mounted) return;
      if (wantsOverride == null || wantsOverride == _SignOutOverride.cancel) {
        return;
      }
      await _attemptPermanentSignOut(
        allowOwnerEmergencyOpenShiftLogout:
            wantsOverride == _SignOutOverride.openShift ||
            wantsOverride == _SignOutOverride.both,
        allowUnsyncedDataLoss:
            wantsOverride == _SignOutOverride.unsynced ||
            wantsOverride == _SignOutOverride.both,
        ownerVerified: ownerVerified,
        ownerUserId: ownerUserId,
        ownerUsername: ownerUsername,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إكمال تسجيل الخروج: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _signOutBusy = false);
    }
  }

  Future<_SignOutOverride?> _askOverrideDialog({
    required String message,
    required bool canEmergencyOverride,
    VoidCallback? onOpenSyncQueue,
  }) async {
    final hasOpenShift = message.contains('وردية مفتوحة');
    final hasUnsynced = message.contains('عمليات مزامنة غير مكتملة');
    final isTenantContextBlock =
        message.contains('TenantContext') || message.contains('غير مضبوط');
    return showDialog<_SignOutOverride>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text(
              'تعذر تسجيل الخروج',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                  if (canEmergencyOverride) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'بصفتك صاحب العمل (تم التحقق)، يمكنك تجاوز هذا الحارس في حالات الطوارئ. '
                      'سيُسجَّل التجاوز في سجل العمليات الحسّاسة.',
                      style: TextStyle(
                        color: Colors.amberAccent,
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                  ] else if (hasUnsynced) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'افتح قائمة المزامنة لمعرفة المهام العالقة (pending/dead) '
                      'وإعادة إرسالها قبل الخروج.',
                      style: TextStyle(
                        color: Colors.white54,
                        height: 1.4,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(_SignOutOverride.cancel),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              if (hasUnsynced && onOpenSyncQueue != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop(_SignOutOverride.cancel);
                    onOpenSyncQueue();
                  },
                  icon: const Icon(Icons.sync_problem_rounded, size: 18),
                  label: const Text('فتح قائمة المزامنة'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentGold,
                  ),
                ),
              if (canEmergencyOverride && hasOpenShift && !hasUnsynced)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      Navigator.of(ctx).pop(_SignOutOverride.openShift),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('خروج طارئ رغم الوردية'),
                ),
              if (canEmergencyOverride && hasUnsynced && !hasOpenShift)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      Navigator.of(ctx).pop(_SignOutOverride.unsynced),
                  icon: const Icon(Icons.cloud_off_rounded),
                  label: const Text('خروج مع فقدان غير المزامن'),
                ),
              if (canEmergencyOverride && hasOpenShift && hasUnsynced)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade900,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      Navigator.of(ctx).pop(_SignOutOverride.both),
                  icon: const Icon(Icons.dangerous_rounded),
                  label: const Text('خروج طارئ كامل'),
                ),
              if (canEmergencyOverride &&
                  isTenantContextBlock &&
                  !hasOpenShift &&
                  !hasUnsynced)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () =>
                      Navigator.of(ctx).pop(_SignOutOverride.both),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('إكمال الخروج الآن'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildManagementEntryBadge() {
    return Semantics(
      label: 'دخول الإدارة',
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.admin_panel_settings, color: Colors.white70, size: 22),
            SizedBox(width: 6),
            Text(
              'دخول الإدارة',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermanentSignOutButton() {
    return PositionedDirectional(
      top: 16,
      end: 16,
      child: Tooltip(
        message: 'خروج نهائي من الحساب',
        child: IconButton.filledTonal(
          style: IconButton.styleFrom(
            backgroundColor: Colors.black.withValues(alpha: 0.35),
            foregroundColor: Colors.white70,
          ),
          onPressed: _signOutBusy ? null : _confirmPermanentAccountSignOut,
          icon: const Icon(Icons.logout_rounded),
        ),
      ),
    );
  }

  Future<void> _onAddUserTap() async {
    // Find the owner account in _users
    final ownerUser = _users.firstWhere(
      (u) => u['role'] == 'owner',
      orElse: () => <String, dynamic>{},
    );

    if (ownerUser.isEmpty) {
      // If no owner found in list, fallback to standard login
      _ownerLogout();
      return;
    }

    final verified = await showDialog<bool>(
      context: context,
      builder: (ctx) => _OwnerPinAuthDialog(
        ownerUser: ownerUser,
        db: _db,
      ),
    );

    if (verified == true) {
      final userId = (ownerUser['id'] as num).toInt();
      final auth = context.read<AuthProvider>();
      await auth.setLocalAuthUser(userId);
      if (!mounted) return;
      // Navigate directly to UserFormScreen
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UserFormScreen()),
      );
      // Reload users after form is popped
      _loadUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHandset = context.screenLayout.isHandsetForLayout;
    return SecureScreen(
      child: DoubleBackToExitScope(
        enabled: isHandset,
        onBackPressed: () {
          if (_selectedUser != null) {
            setState(() {
              _selectedUser = null;
              _pin = '';
            });
            return true;
          }
          return false;
        },
        child: Directionality(
      textDirection: TextDirection.rtl,
      child: GlassBackground(
        backgroundImage: const AssetImage('assets/images/splash_bg.png'),
        overlayOpacity: 0.5,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.accentGold),
                    )
                  : _users.isEmpty
                      ? _buildEmptyState()
                      : SafeArea(
                          child: Stack(
                            children: [
                              PositionedDirectional(
                                top: 16,
                                start: 16,
                                child: _buildManagementEntryBadge(),
                              ),
                              _buildPermanentSignOutButton(),
                              Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 350),
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: ScaleTransition(
                                        scale: Tween<double>(begin: 0.95, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _selectedUser == null
                                      ? _buildNetflixProfileSelection()
                                      : _buildNetflixPinEntry(),
                                ),
                              ),
                            ],
                          ),
                        ),
              if (_signOutBusy)
                const ColoredBox(
                  color: Color(0x99000000),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.accentGold),
                        SizedBox(height: 16),
                        Text(
                          'جارٍ المزامنة وفصل الجهاز…',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Stack(
      children: [
        _buildPermanentSignOutButton(),
        Center(
          child: GlassSurface(
            padding: const EdgeInsets.all(32),
            borderRadius: BorderRadius.circular(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_outline, size: 64, color: Colors.white70),
                const SizedBox(height: 16),
                const Text(
                  'لا يوجد موظفون حالياً',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'يرجى إعداد النظام وإضافة موظفين من حساب المالك.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _ownerLogout,
                  icon: const Icon(Icons.login),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGold,
                    foregroundColor: Colors.black,
                  ),
                  label: const Text('تسجيل الدخول'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetflixProfileSelection() {
    return SingleChildScrollView(
      key: const ValueKey('selection'),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'من سيبدأ العمل؟',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_cloudHydrating) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'جارٍ جلب الحسابات من السحابة…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 48),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 32,
            runSpacing: 40,
            children: [
              ..._users.map((user) => _buildUserCard(user)),
              _buildAddUserCard(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddUserCard() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _onAddUserTap,
        child: SizedBox(
          width: 140,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.add, size: 48, color: Colors.white54),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'مستخدم جديد',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final name = (user['displayName'] as String?)?.trim().isNotEmpty == true
        ? user['displayName'] as String
        : (user['username'] as String? ?? '—');
    final role = user['role'] as String? ?? 'staff';
    
    // Assign a consistent color based on user ID or name for the avatar background
    final colors = [
      Colors.blueGrey[700]!,
      Colors.teal[700]!,
      Colors.indigo[700]!,
      Colors.purple[700]!,
      Colors.brown[700]!,
      Colors.deepOrange[700]!,
    ];
    final hash = name.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    final color = role == 'owner' ? AppColors.accentGold : colors[hash % colors.length];

    String getInitials(String n) {
      final parts = n.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        return '${parts[0].characters.first}${parts[1].characters.first}'.toUpperCase();
      }
      final chars = n.characters;
      return chars.take(chars.length >= 2 ? 2 : 1).toString().toUpperCase();
    }
    final initials = getInitials(name);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _onUserTap(user),
        child: SizedBox(
          width: 140,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: role == 'owner' ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: initials.length > 1 ? 38 : 48,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                ),
              ),
              if (role == 'owner' || role == 'admin') ...[
                const SizedBox(height: 4),
                Text(
                  role == 'owner' ? 'صاحب العمل' : 'مدير',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetflixPinEntry() {
    final name = (_selectedUser!['displayName'] as String?)?.trim().isNotEmpty == true
        ? _selectedUser!['displayName'] as String
        : (_selectedUser!['username'] as String? ?? '—');
    final role = _selectedUser!['role'] as String? ?? 'staff';

    final colors = [
      Colors.blueGrey[700]!,
      Colors.teal[700]!,
      Colors.indigo[700]!,
      Colors.purple[700]!,
      Colors.brown[700]!,
      Colors.deepOrange[700]!,
    ];
    final color = role == 'owner' ? AppColors.accentGold : colors[name.codeUnitAt(0) % colors.length];

    Widget entryArea = Column(
      children: [
        // PIN Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            4,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index < _pin.length ? AppColors.accentGold : Colors.white24,
              ),
            ),
          ),
        ),
        if (_lockRemaining != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_clock_rounded,
                    color: Colors.redAccent, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'تم إيقاف الإدخال مؤقتاً بعد محاولات خاطئة متكررة. '
                    'حاول بعد ${PinAttemptGuard.formatRemaining(_lockRemaining!)}',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ] else
          const SizedBox(height: 48),
        // Numpad
        SizedBox(
          width: 280,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var j = 1; j <= 3; j++)
                      _buildNumpadButton('${i * 3 + j}'),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNumpadButton('X', isAction: true, onTap: _onPinDelete),
                  _buildNumpadButton('0'),
                  _buildNumpadButton('OK', isAction: true, onTap: _verifyPin),
                ],
              ),
            ],
          ),
        ),
        if (role == 'owner') ...[
          const SizedBox(height: 24),
          TextButton(
            onPressed: _verifying ? null : _openOwnerPinRestore,
            child: const Text(
              'نسيت رمز PIN؟ استعادة من السحابة',
              style: TextStyle(color: AppColors.accentGold),
            ),
          ),
        ],
      ],
    );

    return KeyedSubtree(
      key: const ValueKey('pin_entry'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = MediaQuery.sizeOf(context).height *
              (MediaQuery.viewInsetsOf(context).bottom > 0 ? 0.55 : 0.85);
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedUser = null;
                              _pin = '';
                            });
                          },
                        ),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12, width: 1),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            name.characters.first.toUpperCase(),
                            style: TextStyle(
                              color: role == 'owner' ? Colors.black : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'أدخل رمز PIN (4 أرقام)',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  entryArea,
                  if (_verifying)
                    const Padding(
                      padding: EdgeInsets.only(top: 24),
                      child: CircularProgressIndicator(
                        color: AppColors.accentGold,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNumpadButton(String label, {bool isAction = false, VoidCallback? onTap}) {
    final lockedOut = _lockRemaining != null;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: InkWell(
        onTap: lockedOut ? null : (onTap ?? () => _onPinDigit(label)),
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isAction ? Colors.white12 : Colors.black.withValues(alpha: 0.3),
            border: Border.all(color: Colors.white12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: lockedOut
                  ? Colors.white24
                  : (isAction && label == 'OK'
                      ? AppColors.accentGold
                      : Colors.white),
              fontSize: isAction ? 20 : 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// خيارات تجاوز حراس تسجيل الخروج. تُستخدم في dialog الطوارئ.
enum _SignOutOverride {
  cancel,
  openShift,
  unsynced,
  both,
}

class _PermanentSignOutConfirmDialog extends StatefulWidget {
  const _PermanentSignOutConfirmDialog({required this.ownerUser});

  final Map<String, dynamic> ownerUser;

  @override
  State<_PermanentSignOutConfirmDialog> createState() =>
      _PermanentSignOutConfirmDialogState();
}

class _PermanentSignOutConfirmDialogState
    extends State<_PermanentSignOutConfirmDialog> {
  String _pin = '';
  bool _verifying = false;

  void _onPinDigit(String digit) {
    if (_verifying || _pin.length >= 4) return;
    setState(() => _pin += digit);
  }

  void _onPinDelete() {
    if (_verifying || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    if (!AuthValidators.isValidPin(_pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رمز PIN (4 أرقام)')),
      );
      return;
    }

    setState(() => _verifying = true);
    final auth = context.read<AuthProvider>();
    final userId = (widget.ownerUser['id'] as num?)?.toInt();
    if (userId != null && await auth.cloudHasSecretButLocalEmpty(userId)) {
      if (!mounted) return;
      setState(() => _verifying = false);
      Navigator.of(context).pop();
      unawaited(
        Navigator.of(context).pushNamed('/owner-pin-restore-otp'),
      );
      return;
    }
    final ok = await auth.verifyOwnerConfirmationCredential(
      ownerRow: widget.ownerUser,
      credential: _pin,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _verifying = false;
      _pin = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('رمز PIN غير صحيح'),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _openPinRestore() async {
    Navigator.of(context).pop(false);
    unawaited(
      Navigator.of(context).pushNamed('/owner-pin-restore-otp'),
    );
  }

  Future<void> _webBrowserSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'خروج من هذا المتصفح',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'سيتم تسجيل خروجك من NABOO على هذا المتصفح وفك ربط الحساب محلياً '
            'دون الحاجة لرمز PIN.\n\n'
            'لن يُحذف حسابك من السحابة — يمكنك تسجيل الدخول لاحقاً عبر Google.',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('خروج'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<AuthProvider>().signOutWebBrowserOnly();
    if (!mounted) return;
    Navigator.of(context).pop(false);
    unawaited(
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false),
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        4,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index < _pin.length ? AppColors.accentGold : Colors.white24,
          ),
        ),
      ),
    );
  }

  Widget _buildNumpadButton(
    String label, {
    bool isAction = false,
    VoidCallback? onTap,
  }) {
    final disabled = _verifying;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: InkWell(
        onTap: disabled
            ? null
            : (onTap ?? () => _onPinDigit(label)),
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isAction ? Colors.white12 : Colors.black26,
            border: Border.all(color: Colors.white12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isAction && label == 'OK'
                  ? AppColors.accentGold
                  : Colors.white,
              fontSize: isAction ? 18 : 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinNumpad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'رمز PIN',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        _buildPinDots(),
        const SizedBox(height: 20),
        SizedBox(
          width: 240,
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var j = 1; j <= 3; j++)
                      _buildNumpadButton('${i * 3 + j}'),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNumpadButton('X', isAction: true, onTap: _onPinDelete),
                  _buildNumpadButton('0'),
                  _buildNumpadButton('OK', isAction: true, onTap: () => unawaited(_submit())),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'خروج نهائي من الحساب',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'سيتم دفع التغييرات إلى السيرفر وفصل هذا الجهاز من الحساب. '
                'للمتابعة أدخل رمز PIN لصاحب العمل.',
                style: TextStyle(color: Colors.white70, height: 1.45),
              ),
              const SizedBox(height: 20),
              _buildPinNumpad(),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _verifying ? null : _openPinRestore,
                child: const Text(
                  'نسيت رمز PIN؟ استعادة من السحابة',
                  style: TextStyle(color: AppColors.accentGold),
                ),
              ),
              if (kIsWeb)
                TextButton(
                  onPressed: _verifying ? null : () => unawaited(_webBrowserSignOut()),
                  child: const Text(
                    'خروج من هذا المتصفح فقط (بدون PIN)',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              if (_verifying)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accentGold),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _verifying ? null : () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            onPressed: _verifying ? null : () => unawaited(_submit()),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد الخروج'),
          ),
        ],
      ),
    );
  }
}

/// حوار مصادقة المالك قبل إنشاء مستخدم — لوحة أرقام مخصّصة (بدون لوحة النظام)
/// لتجنب overflow الشاشة الخلفية، ويملك حالته داخلياً بدون TextEditingController خارجي.
class _OwnerPinAuthDialog extends StatefulWidget {
  const _OwnerPinAuthDialog({
    required this.ownerUser,
    required this.db,
  });

  final Map<String, dynamic> ownerUser;
  final DatabaseHelper db;

  @override
  State<_OwnerPinAuthDialog> createState() => _OwnerPinAuthDialogState();
}

class _OwnerPinAuthDialogState extends State<_OwnerPinAuthDialog> {
  String _pin = '';
  bool _verifying = false;

  void _onDigit(String digit) {
    if (_verifying || _pin.length >= PinInputConstraints.length) return;
    setState(() => _pin += digit);
    if (_pin.length == PinInputConstraints.length) {
      unawaited(_verify());
    }
  }

  void _onDelete() {
    if (_verifying || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    final pin = _pin.trim();
    if (!AuthValidators.isValidPin(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(PinInputConstraints.invalidMessage),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _verifying = true);
    final userId = (widget.ownerUser['id'] as num).toInt();
    final guardScope = PinAttemptGuard.userScope(userId);
    final locked = await PinAttemptGuard.remainingLock(guardScope);
    if (!mounted) return;

    if (locked != null) {
      setState(() {
        _verifying = false;
        _pin = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إيقاف الإدخال مؤقتاً. حاول بعد '
            '${PinAttemptGuard.formatRemaining(locked)}',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final isValid = await widget.db.verifyPinForUser(userId, pin);
    if (!mounted) return;

    if (isValid) {
      await PinAttemptGuard.recordSuccess(guardScope);
      if (mounted) Navigator.pop(context, true);
      return;
    }

    final newLock = await PinAttemptGuard.recordFailure(
      guardScope,
      userId: userId,
      username: widget.ownerUser['username'] as String?,
    );
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _pin = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newLock != null
              ? 'تم إيقاف الإدخال مؤقتاً بعد محاولات '
                  'خاطئة متكررة. حاول بعد '
                  '${PinAttemptGuard.formatRemaining(newLock)}'
              : 'رمز PIN غير صحيح',
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  Widget _dot(int index) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: index < _pin.length ? AppColors.accentGold : Colors.white24,
      ),
    );
  }

  Widget _key(String label, {bool isAction = false, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: InkWell(
        onTap: _verifying ? null : (onTap ?? () => _onDigit(label)),
        borderRadius: BorderRadius.circular(40),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isAction ? Colors.white12 : Colors.black26,
            border: Border.all(color: Colors.white12),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isAction && label == 'OK'
                  ? AppColors.accentGold
                  : Colors.white,
              fontSize: isAction ? 16 : 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.75;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: const Text(
          'مصادقة المالك',
          style: TextStyle(color: Colors.white),
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH, maxWidth: 340),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'الرجاء إدخال رمز PIN لصاحب العمل لإنشاء مستخدم جديد.',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.start,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, _dot),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 220,
                  child: Column(
                    children: [
                      for (var i = 0; i < 3; i++)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (var j = 1; j <= 3; j++)
                              _key('${i * 3 + j}'),
                          ],
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _key('X', isAction: true, onTap: _onDelete),
                          _key('0'),
                          _key(
                            'OK',
                            isAction: true,
                            onTap: () => unawaited(_verify()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_verifying)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: CircularProgressIndicator(
                      color: AppColors.accentGold,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _verifying ? null : () => Navigator.pop(context, false),
            child: const Text(
              'إلغاء',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          FilledButton(
            onPressed: _verifying ? null : () => unawaited(_verify()),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentGold,
              foregroundColor: Colors.black,
            ),
            child: const Text('تحقق'),
          ),
        ],
      ),
    );
  }
}
