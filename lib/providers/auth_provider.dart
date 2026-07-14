import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/database_helper.dart';
import '../services/app_settings_repository.dart';
import '../services/business_setup_settings.dart';
import '../services/cloud_sync_service.dart'
    show
        CloudBootstrapResult,
        CloudSyncService,
        DeviceAccessResult,
        kDeviceAccessRevokedCode;
import '../services/cloud_sync_run_result.dart';
import '../services/license_service.dart';
import '../services/password_hashing.dart';
import '../services/tenant_context.dart';
import '../services/tenant_context_service.dart';
import '../services/supabase_config.dart';
import '../services/app_session_lifecycle.dart';
import '../services/session_resume_context.dart';
import '../services/auth/pin_attempt_guard.dart';
import '../services/auth/secure_session_storage.dart';
import '../services/auth/registration_session_store.dart';
import '../services/auth/owner_auth_cloud_service.dart';
import '../services/auth/ensure_fresh_session.dart' as session_freshness;
import '../services/sync_queue_service.dart';
import '../models/google_sign_in_intent.dart';
import '../models/google_auth_result.dart';
import '../models/google_owner_profile_gate.dart';
import '../models/tenant_cloud_status.dart';
import '../config/google_oauth_config.dart';
import '../config/otp_config.dart';
import '../services/auth/owner_business_vertical_cloud_service.dart';
import '../services/auth/owner_supabase_credential_store.dart';
import '../services/auth/native_google_id_token_sign_in.dart';
import '../services/auth/auth_network_guard.dart';
import '../services/auth/auth_user_messages.dart';
import '../services/auth/native_google_id_token_sign_in_result.dart';
import '../services/auth/web_app_origin.dart';
import '../services/auth/web_google_id_token_sign_in.dart';
import '../services/auth/web_oauth_redirect.dart';
import '../utils/app_logger.dart';
import '../utils/auth_validators.dart';
import '../owner/services/business_audit_log_service.dart';
import '../owner/services/owner_alert_cloud_sync_service.dart';
import '../owner/services/owner_fcm_listener_service.dart';
import '../services/marketplace/marketplace_merchant_bootstrap_service.dart';

/// عند true: غياب RPC `assert_identity_link_allowed` يوقف Google sign-in.
/// للتطوير المحلي فقط: `--dart-define=STRICT_RPC=false`
const bool kStrictRpcEnforcement =
    bool.fromEnvironment('STRICT_RPC', defaultValue: true);

enum _SupabaseSignInOutcome {
  success,
  invalidCredentials,
  networkError,
}

/// جلسة محلية فقط (SharedPreferences + SQLite). بدون سحابة أو اشتراك.
class AuthProvider extends ChangeNotifier {
  static const _prefUserId = 'local_auth_user_id';
  static const _prefDeviceOwnerBound = 'auth.device_owner_bound';
  static const _prefDeviceOwnerSupabaseUid = 'auth.device_owner_supabase_uid';
  static const _prefDeviceBoundAt = 'auth.device_bound_at';

  /// يحدّد آخر «مالك بيانات» على الجهاز — لا يُحذف عند الخروج لاكتشاف تبديل الحساب.
  static const _prefActiveDataOwner = 'auth.active_data_owner';
  static const _prefPendingGoogleOAuthIntent = 'auth.pending_google_oauth_intent';

  /// يُعاد من [signInWithGoogle] عندما يلزم إكمال جوال + PIN قبل bootstrap.
  static const String kGoogleOwnerProfileRequired =
      '__google_owner_profile_required__';

  /// يُعاد من [signInWithGoogle] عند وجود سر PIN على السحابة — يلزم OTP قبل الاستعادة.
  static const String kGoogleOwnerPinRestoreOtpRequired =
      '__google_owner_pin_restore_otp_required__';

  /// يُعاد على الويب عند بدء إعادة التوجيه لـ Google (الصفحة ستُعاد تحميلها).
  static const String kWebGoogleOAuthRedirectStarted =
      '__web_google_oauth_redirect_started__';

  /// Android/iOS: منتقي حسابات Google الأصلي — لا نُسقط للمتصفح الخارجي.
  static bool get _prefersNativeGoogleAccountPicker =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// يُعاد من [_finalizeGoogleOAuthSession] عندما ينوي المستخدم «إنشاء حساب»
  /// لكن الحساب مكتمل مسبقاً على السحابة — يُوجَّه لتسجيل الدخول.
  static const String kGoogleAccountAlreadyExists =
      'حسابك موجود — اضغط تسجيل الدخول';

  /// يُعاد من [_finalizeGoogleOAuthSession] عندما ينوي المستخدم «تسجيل الدخول»
  /// لكن لا يوجد حساب مكتمل على السحابة — يُوجَّه لإنشاء حساب.
  static const String kGoogleNoAccountFound =
      'لا يوجد حساب — أنشئ حساباً جديداً';

  /// يُعاد عند فشل الوصول للسحابة أثناء فحص اكتمال الحساب — أعد المحاولة
  /// (لا يُفكّ ربط الجهاز).
  static const String kGoogleNetworkError = '__google_network_error__';

  /// لا صف محلي ولا جلسة سحابية صالحة — الحساب غير موجود أو حُذف من السيرفر.
  static const String kLoginNoCloudAccountMessage =
      AuthUserMessages.accountNotFound;

  static const String kAuthNetworkUnavailableMessage =
      AuthUserMessages.networkUnavailable;

  static const String kAuthServerUnreachableMessage =
      AuthUserMessages.serverUnreachable;

  final DatabaseHelper _db = DatabaseHelper();

  bool _isLoggedIn = false;
  int? _userId;
  String _username = '';
  String _displayName = '';
  String _role = '';
  String _roleKey = 'staff';
  String _email = '';
  String _phone = '';
  bool _googleSignInRunning = false;
  bool _ownerPinRestoreOtpVerified = false;
  bool _deviceOwnerBound = false;
  /// true بعد مسح SQLite لحساب سحابي — يُلزم نجاح سحب اللقطة قبل متابعة الواجهة.
  bool _pendingCloudWorkspaceRestore = false;
  bool _deviceAccessRevokedPending = false;
  String? _lastLoginErrorMessage;

  bool get isLoggedIn => _isLoggedIn;
  /// آخر سبب فشل [login] — للعرض بدل رسالة «كلمة مرور خاطئة» العامة.
  String? get lastLoginErrorMessage => _lastLoginErrorMessage;

  bool get deviceOwnerBound => _deviceOwnerBound;
  /// true عندما السيرفر يعتبر هذا الجهاز `revoked` — يُوجَّه لشاشة طلب السماح.
  bool get deviceAccessRevokedPending => _deviceAccessRevokedPending;
  String get roleKey => _roleKey;
  bool get isAdmin => _roleKey == 'admin';
  bool get isOwner => _roleKey == 'owner';
  int? get userId => _userId;
  String get username => _username;
  String get displayName => _displayName.isNotEmpty ? _displayName : _username;
  String get role => _role;
  String get email => _email;
  String get phone => _phone;

  void _setFromRow(Map<String, dynamic> row) {
    _isLoggedIn = true;
    _userId = row['id'] as int?;
    _username = row['username'] as String? ?? '';
    _displayName = row['displayName'] as String? ?? '';
    _email = row['email'] as String? ?? '';
    _phone = row['phone'] as String? ?? '';
    final r = row['role'] as String? ?? 'staff';
    _roleKey = r;
    switch (r) {
      case 'owner':
        _role = 'صاحب العمل';
      case 'admin':
        _role = 'مدير النظام';
      default:
        _role = 'موظف';
    }

    // اضبط tenant_id بعد كل تسجيل دخول ناجح. للحسابات السحابية نستخدم
    // Supabase UID؛ للحسابات المحلية فقط نستخدم مفتاحاً مستقرّاً مبنيّاً
    // على معرّف المستخدم المحلي حتى يُفرض العزل أيضاً في الوضع المحلي.
    final supabaseUid = (row['supabaseUid'] as String?)?.trim() ?? '';
    final localId = (row['id'] as int?) ?? 0;
    final tenantKey = supabaseUid.isNotEmpty ? supabaseUid : 'local-$localId';
    if (tenantKey.isNotEmpty && tenantKey != 'local-0') {
      TenantContext.instance.set(tenantKey);
    }
    if (_roleKey == 'owner') {
      _scheduleOwnerPushBridge();
    }
  }

  void _scheduleOwnerPushBridge() {
    OwnerFcmListenerService.instance.refreshTokenRegistration();
    OwnerAlertCloudSyncService.scheduleResyncActiveTenantPreferences();
  }

  /// مفتاح يميّز بيانات الجهاز: حساب سحابي `cloud:<supabaseUid>` أو محلي `local:<userId>`.
  String _dataOwnerKeyForRow(Map<String, dynamic> row) {
    final su = (row['supabaseUid'] as String?)?.trim();
    if (su != null && su.isNotEmpty) return 'cloud:$su';
    final id = row['id'] as int? ?? 0;
    return 'local:$id';
  }

  Future<void> _clearAccountUiPreferences(SharedPreferences prefs) async {
    await prefs.remove('modules_order');
    await prefs.remove('quick_actions_labels');
  }

  Future<void> _assertNoBlockingSyncQueue({
    required String actionLabel,
    bool allowUnsyncedDataLoss = false,
  }) async {
    if (allowUnsyncedDataLoss) return;
    final hasBlocking = await SyncQueueService.instance.hasBlockingMutations();
    if (!hasBlocking) return;
    final stats = await SyncQueueService.instance.getQueueStats();
    final pending = stats['pending'] ?? 0;
    final failed = stats['failed'] ?? 0;
    final dead = stats['dead'] ?? 0;
    throw StateError(
      'تعذر $actionLabel: توجد عمليات مزامنة غير مكتملة '
      '(pending: $pending, failed: $failed, dead: $dead). '
      'يرجى مزامنة البيانات أولاً ثم إعادة المحاولة.',
    );
  }

  Future<void> _assertNoOpenShiftForLogout({
    bool allowOwnerEmergencyOverride = false,
    bool ownerEmergencyVerified = false,
    int? ownerEmergencyUserId,
    String? ownerEmergencyUsername,
  }) async {
    await _assertNoOpenShiftBlockingAction(
      actionLabel: 'تسجيل الخروج',
      allowOwnerEmergencyOverride: allowOwnerEmergencyOverride,
      ownerEmergencyVerified: ownerEmergencyVerified,
      ownerEmergencyUserId: ownerEmergencyUserId,
      ownerEmergencyUsername: ownerEmergencyUsername,
      ownerHintOnBlock: 'يمكنك كمالك تنفيذ خروج طارئ فقط عبر مسار إداري موثّق.',
      nonOwnerHintOnBlock: 'اطلب من المدير أو المالك إغلاق الوردية أولاً.',
      ownerEmergencyLogLabel: 'Owner emergency logout with open shift',
    );
  }

  Future<void> _assertNoOpenShiftForAccountSwitch() async {
    await _assertNoOpenShiftBlockingAction(
      actionLabel: 'تبديل الحساب',
      allowOwnerEmergencyOverride: false,
      ownerHintOnBlock: 'أغلق الوردية الحالية أولاً ثم أعد محاولة تبديل الحساب.',
      nonOwnerHintOnBlock: 'اطلب من المدير أو المالك إغلاق الوردية أولاً.',
      ownerEmergencyLogLabel: 'Owner emergency account-switch with open shift',
    );
  }

  Future<void> _assertNoOpenShiftBlockingAction({
    required String actionLabel,
    required bool allowOwnerEmergencyOverride,
    bool ownerEmergencyVerified = false,
    int? ownerEmergencyUserId,
    String? ownerEmergencyUsername,
    required String ownerHintOnBlock,
    required String nonOwnerHintOnBlock,
    required String ownerEmergencyLogLabel,
  }) async {
    final openShift = await _db.getOpenWorkShift();
    if (openShift == null) return;

    final shiftId = (openShift['id'] as num?)?.toInt() ?? 0;
    final shiftStaffName = (openShift['shiftStaffName'] as String?)?.trim();
    final staffLabel = (shiftStaffName == null || shiftStaffName.isEmpty)
        ? 'الموظف'
        : shiftStaffName;

    final canOwnerEmergencyBypass = allowOwnerEmergencyOverride &&
        (_roleKey == 'owner' || ownerEmergencyVerified);

    if (canOwnerEmergencyBypass) {
      AppLogger.warn(
        'AuthProvider',
        '$ownerEmergencyLogLabel: shiftId=$shiftId',
      );
      // PR-3 (roadmap_phase2_execution_v1 §4): تسجيل audit دائم لاستثناء المالك.
      // AppLogger.warn يضيع عند إغلاق التطبيق — هذا السجل يبقى في
      // business_audit_events ويظهر في owner_sensitive_actions_panel.
      final auditUserId = _userId ?? ownerEmergencyUserId;
      final auditUsername = _username.isNotEmpty
          ? _username
          : (ownerEmergencyUsername?.trim().isNotEmpty == true
              ? ownerEmergencyUsername!.trim()
              : null);
      unawaited(
        BusinessAuditLogService.instance.record(
          eventType: 'owner_emergency_shift_bypass',
          entityType: 'work_shift',
          entityId: '$shiftId',
          userId: auditUserId,
          username: auditUsername,
          newValueJson: jsonEncode({
            'action': actionLabel,
            'shiftStaffName': shiftStaffName ?? '',
            'logLabel': ownerEmergencyLogLabel,
            'ownerEmergencyVerified': ownerEmergencyVerified,
          }),
        ),
      );
      return;
    }

    final ownerHint = _roleKey == 'owner'
        ? ownerHintOnBlock
        : nonOwnerHintOnBlock;
    throw StateError(
      'تعذر $actionLabel: توجد وردية مفتوحة (#$shiftId) باسم $staffLabel. '
      'يجب إغلاق الوردية قبل إنهاء الجلسة. $ownerHint',
    );
  }

  /// عند تسجيل الدخول بحساب مختلف: مسح محلي يمنع خلط فواتير/مخزون؛ مع السحابة يُسترد من الخادم.
  Future<void> _bindAccountDataScope(
    String newOwnerKey, {
    bool allowUnsyncedDataLoss = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(_prefActiveDataOwner);
    if (previous == newOwnerKey) return;

    // حماية: إذا كان المفتاح غير موجود (مثلاً بعد تحديث/ترحيل/إعادة تثبيت جزئية)،
    // اعتبره "تبديل" حتى لا تُعرض بيانات حساب سابق بالخطأ.
    final switching = previous == null || previous != newOwnerKey;
    if (switching) {
      final cloudFullWipe = newOwnerKey.startsWith('cloud:');
      // مسح SQLite كامل للحساب السحابي — الوردية/queue القديمة ستُحذف؛ لا نمنع التسجيل.
      if (!cloudFullWipe) {
        await _assertNoOpenShiftForAccountSwitch();
      }
      await _assertNoBlockingSyncQueue(
        actionLabel: 'تبديل الحساب',
        allowUnsyncedDataLoss: allowUnsyncedDataLoss || cloudFullWipe,
      );
      await CloudSyncService.instance.stopForSignOut();
      if (newOwnerKey.startsWith('cloud:')) {
        // حساب سحابي: من الآمن حذف الملف بالكامل لأن المصدر الحقيقي سيُسترد من السحابة.
        await _db.closeAndDeleteDatabaseFile();
        _pendingCloudWorkspaceRestore = true;
      } else {
        // حساب محلي: امسح بيانات العمل وابقِ المستخدمين المحليين فقط.
        await _db.wipeBusinessDataKeepUsers();
      }
      await CloudSyncService.instance.clearSyncPreferences();
      await _clearAccountUiPreferences(prefs);
      await LicenseService.instance.resetLicenseStateForDataScopeChange();
    }
    await prefs.setString(_prefActiveDataOwner, newOwnerKey);
    await TenantContextService.instance.load();
  }

  Future<void> _refreshTenantContextSilently() async {
    try {
      await TenantContextService.instance.load();
    } catch (e, st) {
      // المستودعات تستدعي load() عند أول حاجة؛ لا نقطع الجلسة هنا.
      AppLogger.warn(
        'AuthProvider',
        'TenantContext load failed silently: $e',
      );
      if (kDebugMode) {
        AppLogger.error('AuthProvider', 'TenantContext load stack', e, st);
      }
    }
  }

  void _clear({bool preserveTenant = false}) {
    _isLoggedIn = false;
    _userId = null;
    _username = '';
    _displayName = '';
    _role = '';
    _roleKey = 'staff';
    _email = '';
    _phone = '';
    if (!preserveTenant) {
      TenantContext.instance.clear();
    }
  }

  Future<void> _bindDeviceToOwner(Map<String, dynamic> row) async {
    final role = (row['role'] as String? ?? 'staff').trim();
    if (role != 'owner') return;
    final prefs = await SharedPreferences.getInstance();
    final supabaseUidFromRow = (row['supabaseUid'] as String?)?.trim() ?? '';
    final supabaseUidFromSession =
        Supabase.instance.client.auth.currentUser?.id.trim() ?? '';
    final ownerUid = supabaseUidFromRow.isNotEmpty
        ? supabaseUidFromRow
        : supabaseUidFromSession;
    await prefs.setBool(_prefDeviceOwnerBound, true);
    if (ownerUid.isNotEmpty) {
      await prefs.setString(_prefDeviceOwnerSupabaseUid, ownerUid);
    }
    if ((prefs.getString(_prefDeviceBoundAt) ?? '').isEmpty) {
      await prefs.setString(_prefDeviceBoundAt, DateTime.now().toIso8601String());
    }
    _deviceOwnerBound = true;
  }

  Future<void> clearDeviceOwnerBinding() async {
    final emails = await _collectKnownAuthEmails();
    for (final mail in emails) {
      await _clearSecureAuthCredentialsForEmail(mail);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefDeviceOwnerBound);
    await prefs.remove(_prefDeviceOwnerSupabaseUid);
    await prefs.remove(_prefDeviceBoundAt);
    await prefs.remove(_prefActiveDataOwner);
    _deviceOwnerBound = false;
    notifyListeners();
  }

  /// يحفظ كلمة Supabase الداخلية لاستعادة الجلسة بصمت على نفس الجهاز.
  Future<void> _persistOwnerSupabaseCredential(String mail, String password) async {
    final normalized = _normalizeAuthEmail(mail);
    if (normalized.isEmpty) return;
    try {
      await OwnerSupabaseCredentialStore.instance.save(normalized, password);
    } catch (e) {
      AppLogger.warn('AuthProvider', 'persist owner supabase credential: $e');
    }
  }

  /// يمسح كلمات Supabase الداخلية المخزّنة لبريد (بعد حذف حساب أو إعادة تسجيل).
  Future<void> _clearSecureAuthCredentialsForEmail(String? email) async {
    final mail = (email ?? '').trim().toLowerCase();
    if (mail.isEmpty || !mail.contains('@')) return;
    try {
      await OwnerSupabaseCredentialStore.instance.clear(mail);
      await RegistrationSessionStore.instance.clearPendingSupabasePassword(mail);
    } catch (e) {
      AppLogger.warn('AuthProvider', 'clear secure auth credentials: $e');
    }
  }

  /// يجمع عناوين البريد المعروفة على الجهاز لتنظيف secure storage.
  Future<Set<String>> _collectKnownAuthEmails() async {
    final emails = <String>{};
    void add(String? value) {
      final s = (value ?? '').trim().toLowerCase();
      if (_looksLikeEmail(s)) emails.add(s);
    }

    add(_email);
    try {
      add(Supabase.instance.client.auth.currentUser?.email);
    } catch (e) {
      AppLogger.warn('AuthProvider', 'collect auth emails session read: $e');
    }
    try {
      final owner = await getLocalOwnerRow();
      add(owner?['email'] as String?);
      add(owner?['username'] as String?);
    } catch (e) {
      AppLogger.warn('AuthProvider', 'collect auth emails owner row: $e');
    }
    return emails;
  }

  /// استعادة الجلسة بعد إعادة تشغيل التطبيق.
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceOwnerBound = prefs.getBool(_prefDeviceOwnerBound) ?? false;
    final deviceOwnerUid = (prefs.getString(_prefDeviceOwnerSupabaseUid) ?? '').trim();
    if (_deviceOwnerBound && deviceOwnerUid.isNotEmpty) {
      await _db.ensureDeviceOwnerRole(deviceOwnerUid);
      await _db.pruneCloudStaffShadowUsers();
      final cloudKey = 'cloud:$deviceOwnerUid';
      if (prefs.getString(_prefActiveDataOwner) != cloudKey) {
        await prefs.setString(_prefActiveDataOwner, cloudKey);
      }
      try {
        final sessionEmail =
            Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';
        if (sessionEmail.isNotEmpty) {
          await _db.repairOwnerRowIfMissing(
            supabaseUid: deviceOwnerUid,
            email: sessionEmail,
          );
        }
      } catch (e) {
        AppLogger.warn('AuthProvider', 'repairOwnerRowIfMissing failed: $e');
      }
    }
    final id = prefs.getInt(_prefUserId);
    final activeDataOwner = prefs.getString(_prefActiveDataOwner);

    AppLogger.info(
      'AuthProvider',
      'restoreSession deviceOwnerBound=$_deviceOwnerBound userId=$id',
    );

    // إذا لم توجد جلسة محلية (المستخدم سجّل خروج) لكن توجد جلسة Supabase
    // متبقية (ghost session بسبب فشل Keychain)، نُنظّفها بصمت ونتابع لشاشة الدخول.
    // لا نُعيد ربط الحساب تلقائياً لأن المستخدم قرر الخروج صراحةً.
    // ⚠️ لكن إذا كان الجهاز مربوطاً بمالك (deviceOwnerBound) فالمستخدم قام فقط بـ lockSession
    // ولم يسجل خروج كامل — لا نمسح جلسة Supabase.
    if (id == null && !_deviceOwnerBound && !_googleSignInRunning) {
      final pendingGoogleOAuth =
          (prefs.getString(_prefPendingGoogleOAuthIntent) ?? '').isNotEmpty;
      if (!pendingGoogleOAuth) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          AppLogger.info(
            'AuthProvider',
            'restoreSession clearing ghost Supabase session (device NOT bound)',
          );
          // تنظيف الجلسة الشبحية بصمت
          try {
            await Supabase.instance.client.auth.signOut();
          } catch (e) {
            AppLogger.warn('AuthProvider', 'ghost Supabase signOut failed: $e');
          }
          await _clearSupabaseFallbackSession();
        }
      } catch (e) {
        AppLogger.warn('AuthProvider', 'ghost session cleanup failed: $e');
      }
      }
    }

    if (id == null) {
      AppLogger.info(
        'AuthProvider',
        'restoreSession no userId — clearing preserveTenant=$_deviceOwnerBound',
      );
      _clear(preserveTenant: _deviceOwnerBound);
      if (_deviceOwnerBound) {
        final ownerUid =
            prefs.getString(_prefDeviceOwnerSupabaseUid)?.trim() ?? '';
        if (ownerUid.isNotEmpty) {
          TenantContext.instance.set(ownerUid);
        }
        await _refreshTenantContextSilently();
        // جلسة Supabase قد تنتهي بعد خمول طويل — نُعيدها تلقائياً قبل المزامنة.
        await ensureCloudSessionActive();
        if (Supabase.instance.client.auth.currentUser != null) {
          unawaited(
            hydrateCloudAccountData(
              forcePull: false,
              forceImportOnPull: false,
              maxAttempts: 1,
            ),
          );
        }
      }
      notifyListeners();
      return;
    }
    final row = await _db.getUserById(id);
    if (row == null || (row['isActive'] != 1)) {
      await prefs.remove(_prefUserId);
      _clear(preserveTenant: _deviceOwnerBound);
      if (_deviceOwnerBound) {
        await _refreshTenantContextSilently();
      }
      notifyListeners();
      return;
    }
    // جهاز مربوط: لا نُعيد تسجيل الدخول المحلي تلقائياً — نحفظ تلميح
    // الاستئناف ونطلب PIN عبر بوابة «من سيبدأ العمل؟».
    if (_deviceOwnerBound) {
      final role = (row['role'] as String?)?.trim() ?? 'staff';
      await SessionResumeContext.captureBeforeSessionLock(
        userId: id,
        role: role,
      );
      await prefs.remove(_prefUserId);
      _clear(preserveTenant: true);
      await _refreshTenantContextSilently();
      await ensureCloudSessionActive();
      if (Supabase.instance.client.auth.currentUser != null) {
        unawaited(
          hydrateCloudAccountData(
            forcePull: false,
            forceImportOnPull: false,
            maxAttempts: 1,
          ),
        );
      }
      notifyListeners();
      return;
    }
    _setFromRow(row);
    await _bindDeviceToOwner(row);
    if (prefs.getString(_prefActiveDataOwner) == null) {
      await prefs.setString(_prefActiveDataOwner, _dataOwnerKeyForRow(row));
    }
    await _refreshTenantContextSilently();
    if (_deviceOwnerBound) {
      await ensureCloudSessionActive();
      if (Supabase.instance.client.auth.currentUser != null) {
        unawaited(
          hydrateCloudAccountData(
            forcePull: false,
            forceImportOnPull: false,
            maxAttempts: 1,
          ),
        );
      }
    }
    notifyListeners();
  }

  /// سحب لقطة السحابة (مستخدمون، تخصص العمل، …) بعد ربط الجهاز — للإقلاع والبوابة.
  Future<void>? _hydrateInFlight;

  Future<void> hydrateCloudAccountData({
    Duration timeout = const Duration(seconds: 15),
    bool forcePull = true,
    bool forceImportOnPull = false,
    int maxAttempts = 1,
  }) async {
    if (_hydrateInFlight != null) {
      return _hydrateInFlight!;
    }
    final pending = _runHydrateCloudAccountData(
      timeout: timeout,
      forcePull: forcePull,
      forceImportOnPull: forceImportOnPull,
      maxAttempts: maxAttempts,
    );
    _hydrateInFlight = pending;
    try {
      await pending;
    } finally {
      if (identical(_hydrateInFlight, pending)) {
        _hydrateInFlight = null;
      }
    }
  }

  Future<void> _runHydrateCloudAccountData({
    required Duration timeout,
    bool forcePull = true,
    bool forceImportOnPull = false,
    int maxAttempts = 1,
  }) async {
    final attempts = maxAttempts.clamp(1, 6);
    var importOnPull = forceImportOnPull;
    if (!importOnPull) {
      try {
        importOnPull = !(await BusinessSetupSettingsData.isCompleted(
          AppSettingsRepository.instance,
        ));
      } catch (e) {
        AppLogger.warn('AuthProvider', 'business setup completion read failed: $e');
      }
    }

    for (var attempt = 0; attempt < attempts; attempt++) {
      if (_deviceOwnerBound) {
        await ensureCloudSessionActive();
      }
      if (Supabase.instance.client.auth.currentUser == null) return;
      if (!forcePull &&
          attempt == 0 &&
          CloudSyncService.instance.hasFreshCloudPull()) {
        return;
      }

      CloudBootstrapResult bootstrap = CloudBootstrapResult.ok;
      CloudSyncRunResult syncResult = const CloudSyncRunResult();

      try {
        bootstrap = await CloudSyncService.instance
            .bootstrapForSignedInUser()
            .timeout(timeout, onTimeout: () => CloudBootstrapResult.ok);

        if (bootstrap == CloudBootstrapResult.deviceRevoked) {
          _deviceAccessRevokedPending = true;
          notifyListeners();
          return;
        }
        if (!bootstrap.isOk) {
          AppLogger.warn(
            'AuthProvider',
            'hydrate bootstrap not ok (attempt ${attempt + 1}/$attempts)',
          );
        } else {
          syncResult = await _syncNowDetailedWithRetry(
            forcePull: forcePull,
            forceImportOnPull: importOnPull,
            forcePush: false,
            maxAttempts: 2,
          ).timeout(
            timeout,
            onTimeout: () => const CloudSyncRunResult(
              pullStatus: CloudSyncPullStatus.failed,
              pullAttempted: true,
              errorMessage: 'انتهت مهلة المزامنة أثناء تهيئة الحساب.',
            ),
          );
          await _finalizeHydrateAfterSync();
        }
      } catch (e, st) {
        AppLogger.warn(
          'AuthProvider',
          'hydrate attempt ${attempt + 1}/$attempts failed: $e',
        );
        AppLogger.error('AuthProvider', 'hydrate stack', e, st);
      }

      if (_hydrateAttemptTerminal(bootstrap: bootstrap, syncResult: syncResult)) {
        return;
      }

      if (attempt < attempts - 1) {
        final delayMs = 800 + (attempt * 1200);
        AppLogger.info(
          'AuthProvider',
          'hydrate retry in ${delayMs}ms (${attempt + 2}/$attempts)',
        );
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  Future<void> _finalizeHydrateAfterSync() async {
    await _reconcileUserDirectoryWithAudit(source: 'hydrate');
    await OwnerBusinessVerticalCloudService.applyToLocalIfNeeded();
    await OwnerBusinessVerticalCloudService.syncLocalVerticalToCloudIfMissing();
    CloudSyncService.instance.scheduleUserDirectoryPushSoon(
      delay: const Duration(milliseconds: 800),
    );
    unawaited(
      MarketplaceMerchantBootstrapService.instance.ensureStoreAndSyncCatalog(),
    );
  }

  bool _hydrateAttemptTerminal({
    required CloudBootstrapResult bootstrap,
    required CloudSyncRunResult syncResult,
  }) {
    if (bootstrap == CloudBootstrapResult.deviceRevoked) return true;
    if (CloudSyncService.instance.hasFreshCloudPull()) return true;
    if (syncResult.pulledCloudData) return true;
    if (syncResult.pullStatus == CloudSyncPullStatus.noRemoteSnapshot) {
      return true;
    }
    return _hydratePullBlockedPermanently(syncResult.pullStatus);
  }

  bool _hydratePullBlockedPermanently(CloudSyncPullStatus status) {
    return status == CloudSyncPullStatus.blockedSchema ||
        status == CloudSyncPullStatus.blockedPayload ||
        status == CloudSyncPullStatus.blockedChunks;
  }

  /// يُعيد null عند النجاح، أو رسالة خطأ عربية عند فشل استعادة مساحة العمل.
  Future<String?> _completeCloudBootstrapAfterRestore(
    int localUserId, {
    bool? requireMandatoryRestore,
  }) async {
    final mandatory = requireMandatoryRestore ?? _pendingCloudWorkspaceRestore;
    try {
      final bootstrap = await CloudSyncService.instance
          .bootstrapForSignedInUser();
      if (bootstrap == CloudBootstrapResult.deviceRevoked) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefUserId);
        _clear(preserveTenant: true);
        _deviceAccessRevokedPending = true;
        _pendingCloudWorkspaceRestore = false;
        unawaited(
          BusinessAuditLogService.instance.record(
            eventType: 'device_access_revoked_at_login',
            entityType: 'account_device',
            entityId: Supabase.instance.client.auth.currentUser?.id ?? '',
            userId: localUserId,
            username: _username.isNotEmpty ? _username : null,
          ),
        );
        notifyListeners();
        return kDeviceAccessRevokedCode;
      }
      if (!bootstrap.isOk) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefUserId);
        await CloudSyncService.instance.stopForSignOut();
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (e) {
          AppLogger.warn(
            'AuthProvider',
            'signOut after bootstrap revoke failed: $e',
          );
        }
        _clear();
        _pendingCloudWorkspaceRestore = false;
        notifyListeners();
        return 'تعذّر تفعيل الجلسة السحابية. سجّل الدخول مرة أخرى.';
      }
      await LicenseService.instance.applyTrialFromSupabaseProfile();
      final maxDevices =
          LicenseService.instance.state.plan?.maxDevices ??
          SubscriptionPlan.monthly.maxDevices;
      final limitError = await CloudSyncService.instance.enforcePlanDeviceLimit(
        maxDevices: maxDevices,
      );
      if (limitError != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefUserId);
        await CloudSyncService.instance.stopForSignOut();
        _clear();
        _pendingCloudWorkspaceRestore = false;
        notifyListeners();
        return limitError;
      }
      // سحب اللقطة قبل أي قرار تنقل — جهاز جديد يكون محلياً فارغاً.
      var importOnPull = mandatory;
      if (!importOnPull) {
        try {
          importOnPull = !(await BusinessSetupSettingsData.isCompleted(
            AppSettingsRepository.instance,
          ));
        } catch (e) {
          AppLogger.warn(
            'AuthProvider',
            'business setup read before bootstrap sync failed: $e',
          );
        }
      }
      final syncResult = await _syncNowDetailedWithRetry(
        forcePull: true,
        forceImportOnPull: importOnPull,
        forcePush: false,
        maxAttempts: 3,
      );
      try {
        await _reconcileUserDirectoryWithAudit(source: 'bootstrap_restore');
      } catch (e) {
        AppLogger.warn(
          'AuthProvider',
          'reconcileUserDirectoryAfterCloudImport failed: $e',
        );
      }

      if (mandatory) {
        final hasRemote =
            await CloudSyncService.instance.hasRemoteSnapshotForCurrentUser();
        if (!syncResult.isMandatoryRestoreOk(remoteSnapshotExists: hasRemote)) {
          final msg = syncResult.userMessageAr ??
              'تعذّر استرجاع بيانات النشاط من السحابة. تحقق من الإنترنت ثم أعد المحاولة.';
          unawaited(
            BusinessAuditLogService.instance.record(
              eventType: 'cloud_workspace_restore_failed',
              entityType: 'auth_session',
              entityId: '$localUserId',
              userId: localUserId,
              username: _username.isNotEmpty ? _username : null,
              newValueJson: jsonEncode({
                'pullStatus': syncResult.pullStatus.name,
                'remoteSnapshotExists': hasRemote,
                'error': syncResult.errorMessage ?? msg,
              }),
            ),
          );
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_prefUserId);
          await CloudSyncService.instance.stopForSignOut();
          try {
            await Supabase.instance.client.auth.signOut();
          } catch (e) {
            AppLogger.warn('AuthProvider', 'signOut after restore fail: $e');
          }
          _clear();
          _pendingCloudWorkspaceRestore = false;
          notifyListeners();
          return msg;
        }
      }
      _pendingCloudWorkspaceRestore = false;
      return null;
    } catch (e) {
      AppLogger.warn('AuthProvider', 'complete bootstrap after restore failed: $e');
      if (mandatory) {
        _pendingCloudWorkspaceRestore = false;
        return 'تعذّر استرجاع بيانات النشاط. تحقق من الاتصال ثم أعد المحاولة.';
      }
      return null;
    }
  }

  /// ينتظر انتهاء hydrate الجاري ويُعيد محاولات لاستعادة جلسة Supabase.
  Future<bool> _awaitOwnerProfileCompletionPrerequisites() async {
    if (_hydrateInFlight != null) {
      try {
        await _hydrateInFlight!.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        AppLogger.warn(
          'AuthProvider',
          'profile completion: hydrate wait timed out',
        );
      } catch (e) {
        AppLogger.warn('AuthProvider', 'profile completion: hydrate wait: $e');
      }
    }
    for (var attempt = 0; attempt < 4; attempt++) {
      if (await ensureSupabaseSessionForOwnerProfileCompletion()) {
        return true;
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    return Supabase.instance.client.auth.currentUser != null;
  }

  Future<CloudSyncRunResult> _syncNowDetailedWithRetry({
    bool forcePull = true,
    bool forcePush = false,
    bool forceImportOnPull = false,
    int maxAttempts = 3,
  }) async {
    CloudSyncRunResult result = const CloudSyncRunResult(
      pullStatus: CloudSyncPullStatus.failed,
      errorMessage: 'تعذّر إتمام المزامنة.',
    );
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (_hydrateInFlight != null && attempt > 0) {
        try {
          await _hydrateInFlight!.timeout(const Duration(seconds: 20));
        } catch (_) {}
      }
      result = await CloudSyncService.instance.syncNowDetailed(
        forcePull: forcePull,
        forcePush: forcePush,
        forceImportOnPull: forceImportOnPull,
      );
      final err = (result.errorMessage ?? '').trim();
      final inProgress = err.contains('قيد التشغيل');
      if (!inProgress) return result;
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    return result;
  }

  /// مسار التنقل بعد إكمال جوال+PIN — بدون hydrate ثانٍ (تم للتو في bootstrap).
  Future<String> resolveRouteAfterOwnerProfileCompletion() async {
    if (_deviceAccessRevokedPending) return '/device-access-revoked';
    try {
      if (!(await _shouldSkipInitialOnboarding())) return '/onboarding';
    } catch (e) {
      AppLogger.warn('AuthProvider', 'resolveRouteAfterOwnerProfileCompletion: $e');
    }
    return '/employee-gate';
  }

  /// هل يحتاج الجهاز استيراداً كاملاً من السحابة (جهاز جديد / إعداد غير مكتمل)؟
  Future<bool> _needsFullCloudImportOnHydrate() async {
    try {
      if (await BusinessSetupSettingsData.isCompleted(
        AppSettingsRepository.instance,
      )) {
        return false;
      }
      if (await BusinessSetupSettingsData.isVerticalLocked(
        AppSettingsRepository.instance,
      )) {
        return false;
      }
    } catch (e) {
      AppLogger.warn('AuthProvider', '_needsFullCloudImportOnHydrate: $e');
    }
    return true;
  }

  /// مسار إلزامي قبل بوابة PIN عندما PIN على السحابة ولم يُستورد محلياً (ويب/جهاز جديد).
  Future<String?> googleOwnerProfileRouteIfNeeded() async {
    if (Supabase.instance.client.auth.currentUser == null) return null;
    final row = await getLocalOwnerRow();
    if (row == null) return '/complete-google-profile';
    final localId = (row['id'] as num).toInt();
    final gate = await resolveGoogleOwnerProfileGate(localId);
    switch (gate) {
      case GoogleOwnerProfileGate.cloudHasSecretButLocalEmpty:
        return '/owner-pin-restore-otp';
      case GoogleOwnerProfileGate.needsCompleteProfile:
        return '/complete-google-profile';
      case GoogleOwnerProfileGate.complete:
        return null;
    }
  }

  /// بعد تسجيل الدخول/OTP: اسحب لقطة السحابة ثم حدّد المسار (إعداد / الرئيسية).
  ///
  /// على جهاز ثانٍ القاعدة المحلية فارغة حتى يُستورد `app_settings` والمستخدمون
  /// من اللقطة — بدون هذا يُعاد «إعداد سريع» رغم اكتمال الحساب على جهاز آخر.
  Future<String> resolveRouteAfterAuthenticatedSession() async {
    if (_deviceAccessRevokedPending) return '/device-access-revoked';
    if (_deviceOwnerBound) {
      await ensureCloudSessionActive();
    }
    if (Supabase.instance.client.auth.currentUser != null) {
      final needsFullImport = await _needsFullCloudImportOnHydrate();
      final freshPull = CloudSyncService.instance.hasFreshCloudPull(
        maxAge: const Duration(minutes: 10),
      );
      await hydrateCloudAccountData(
        timeout: const Duration(seconds: 25),
        forcePull: needsFullImport || !freshPull,
        forceImportOnPull: needsFullImport,
        maxAttempts: needsFullImport ? 2 : 1,
      );
    }
    var skipOnboarding = await _shouldSkipInitialOnboarding();
    if (!skipOnboarding &&
        Supabase.instance.client.auth.currentUser != null &&
        !CloudSyncService.instance.hasFreshCloudPull(
          maxAge: const Duration(minutes: 10),
        )) {
      final hasRemote =
          await CloudSyncService.instance.hasRemoteSnapshotForCurrentUser();
      if (hasRemote) {
        await CloudSyncService.instance.syncNowDetailed(
          forcePull: true,
          forceImportOnPull: true,
          forcePush: false,
        );
        await _reconcileUserDirectoryWithAudit(source: 'resolve_route_retry');
        skipOnboarding = await _shouldSkipInitialOnboarding();
      }
    }
    if (!skipOnboarding) return '/onboarding';

    final ownerProfileRoute = await googleOwnerProfileRouteIfNeeded();
    if (ownerProfileRoute != null) return ownerProfileRoute;

    // جهاز مربوط بمالك بلا جلسة محلية → «من سيبدأ العمل؟» (بعد قفل/فصل/عودة).
    if (!isLoggedIn && deviceOwnerBound) return '/employee-gate';
    // جهاز ثانٍ: بعد سحب staff من السحابة — البوابة أولاً لا /home مباشرة.
    if (isOwner && deviceOwnerBound) return '/employee-gate';
    return isOwner ? '/home' : '/open-shift';
  }

  /// جهاز أول: إعداد سريع. جهاز ثانٍ: تخطّي إن اكتمل الإعداد أو (لقطة + تخصص + موظف).
  Future<bool> _shouldSkipInitialOnboarding() async {
    try {
      if (await BusinessSetupSettingsData.isCompleted(
        AppSettingsRepository.instance,
      )) {
        return true;
      }
      if (await BusinessSetupSettingsData.isVerticalLocked(
        AppSettingsRepository.instance,
      )) {
        return true;
      }
    } catch (e) {
      AppLogger.warn('AuthProvider', 'onboarding completed check failed: $e');
    }

    if (Supabase.instance.client.auth.currentUser == null) {
      try {
        final repo = AppSettingsRepository.instance;
        if (await BusinessSetupSettingsData.hasKnownVerticalSaved(repo)) {
          return true;
        }
      } catch (e) {
        AppLogger.warn(
          'AuthProvider',
          'onboarding skip without cloud session: $e',
        );
      }
      return false;
    }

    try {
      await OwnerBusinessVerticalCloudService.applyToLocalIfNeeded();
      if (await BusinessSetupSettingsData.isCompleted(
        AppSettingsRepository.instance,
      )) {
        return true;
      }
      if (await BusinessSetupSettingsData.isVerticalLocked(
        AppSettingsRepository.instance,
      )) {
        return true;
      }

      final hasRemote =
          await CloudSyncService.instance.hasRemoteSnapshotForCurrentUser();
      if (!hasRemote) {
        final cloudV =
            await OwnerBusinessVerticalCloudService.fetchForCurrentUser();
        return cloudV != null;
      }

      await _db.reconcileUserDirectoryAfterCloudImport();

      final setup = await BusinessSetupSettingsData.load(
        AppSettingsRepository.instance,
      );
      if (!BusinessVertical.isKnown(setup.businessVertical)) return false;

      if (await BusinessSetupSettingsData.isVerticalLocked(
        AppSettingsRepository.instance,
      )) {
        return true;
      }

      return await _db.hasAtLeastOneActiveStaffWithPin();
    } catch (e) {
      AppLogger.warn('AuthProvider', 'cloud onboarding skip probe failed: $e');
    }
    return false;
  }

  Future<void> _reconcileUserDirectoryWithAudit({required String source}) async {
    await _db.reconcileUserDirectoryAfterCloudImport();
    try {
      final gateUsers = await _db.listActiveUsersForEmployeeGate();
      unawaited(
        BusinessAuditLogService.instance.record(
          eventType: 'user_directory_reconciled',
          entityType: 'cloud_sync',
          entityId: source,
          userId: _userId,
          username: _username.isNotEmpty ? _username : null,
          newValueJson: jsonEncode({
            'source': source,
            'gateUserCount': gateUsers.length,
          }),
        ),
      );
    } catch (e) {
      AppLogger.warn('AuthProvider', 'reconcile audit record failed: $e');
    }
  }

  Future<bool> login(String login, String password) async {
    _lastLoginErrorMessage = null;
    final guardScope = 'login_${login.trim().toLowerCase()}';
    final locked = await PinAttemptGuard.remainingLock(guardScope);
    if (locked != null) {
      _lastLoginErrorMessage =
          'تم إيقاف المحاولات مؤقتاً بعد إدخالات خاطئة متكررة. '
          'حاول بعد ${PinAttemptGuard.formatRemaining(locked)}';
      return false;
    }
    final ok = await _loginInternal(login, password);
    if (ok) {
      await PinAttemptGuard.recordSuccess(guardScope);
    } else if (_lastLoginErrorMessage != null) {
      // فشل تحقّق فعلي (وليس خطأ شبكة/سحابة صامت) → يُحتسب لدى الحارس.
      final newLock = await PinAttemptGuard.recordFailure(guardScope);
      if (newLock != null) {
        _lastLoginErrorMessage =
            'تم إيقاف المحاولات مؤقتاً بعد إدخالات خاطئة متكررة. '
            'حاول بعد ${PinAttemptGuard.formatRemaining(newLock)}';
      }
    }
    return ok;
  }

  Future<bool> _loginInternal(String login, String password) async {
    final row = await _db.getUserByLogin(login);
    if (row == null) {
      return _loginViaSupabaseFallback(login, password);
    }
    final salt = row['passwordSalt'] as String?;
    final hash = row['passwordHash'] as String?;
    if (salt == null || hash == null || salt.isEmpty || hash.isEmpty) {
      // الحساب موجود محلياً لكن بدون كلمة مرور (أُنشئ عبر Google أو fallback سابق)
      // نحاول Supabase وإذا نجح نحفظ الـ hash محلياً
      return _loginViaSupabaseFallback(login, password);
    }
    if (!await PasswordHashing.verifyPin(password, salt, hash)) {
      // جهاز ثانٍ: قد يوجد صف محلي قديم/ناقص — جرّب السحابة قبل الرفض.
      if (_looksLikeEmail(login)) {
        return _loginViaSupabaseFallback(login, password);
      }
      _lastLoginErrorMessage = AuthUserMessages.wrongCredentials;
      return false;
    }

    // ترقية انتهازية للتجزئة القديمة (SHA-256) إلى PBKDF2 بنفس الملح.
    if (PasswordHashing.needsRehash(hash)) {
      final modern = await PasswordHashing.hashPin(password, salt);
      unawaited(_db.updateUserPasswordByLogin(
        login: login,
        passwordHash: modern,
        passwordSalt: salt,
      ));
    }

    // صف محلي قديم بعد حذف الحساب من لوحة الإدارة — UID/JWT لا يطابقان.
    final linkedUid = (row['supabaseUid'] as String?)?.trim() ?? '';
    if (linkedUid.isNotEmpty) {
      final sessionUid =
          Supabase.instance.client.auth.currentUser?.id.trim() ?? '';
      if (sessionUid.isEmpty || sessionUid != linkedUid) {
        AppLogger.info(
          'AuthProvider',
          'login: local row cloud uid mismatch — trying supabase fallback',
        );
        final mail = _cloudLoginEmailForRow(row, login);
        if (mail == null) {
          _lastLoginErrorMessage =
              'تعذّر التحقق من الحساب السحابي. استخدم البريد الإلكتروني لتسجيل الدخول.';
          return false;
        }
        return _loginViaSupabaseFallback(mail, password);
      }
    }

    final ghostBlock = await _blockGhostLoginIfCloudDead(row: row, login: login);
    if (ghostBlock != null) {
      _lastLoginErrorMessage = ghostBlock;
      return false;
    }

    await _bindAccountDataScope(_dataOwnerKeyForRow(row));
    final rowAfter = await _db.getUserByLogin(login);
    if (rowAfter == null) return false;

    _setFromRow(rowAfter);
    await _bindDeviceToOwner(rowAfter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefUserId, rowAfter['id'] as int);
    await LicenseService.instance.ensureLocalTrialStarted();
    // حاول تفعيل جلسة Supabase تلقائياً للحسابات البريدية (إن كانت سحابية) دون كسر الدخول المحلي.
    await _tryEnableCloudSessionAfterLocalLogin(
      row: rowAfter,
      login: login,
      password: password,
    );
    await _refreshTenantContextSilently();
    notifyListeners();
    return true;
  }
  Future<bool> setLocalAuthUser(int userId) async {
    final row = await _db.getUserById(userId);
    if (row == null) return false;
    if (((row['isActive'] as num?)?.toInt() ?? 0) != 1) return false;
    final prefs = await SharedPreferences.getInstance();
    final deviceBound = prefs.getBool(_prefDeviceOwnerBound) ?? false;
    if (!deviceBound) {
      await _bindAccountDataScope(_dataOwnerKeyForRow(row));
    } else {
      // جهاز مربوط بمالك: جلسة الموظف لا تغيّر نطاق البيانات (cloud:uid).
      final ownerUid =
          (prefs.getString(_prefDeviceOwnerSupabaseUid) ?? '').trim();
      if (ownerUid.isNotEmpty) {
        await prefs.setString(_prefActiveDataOwner, 'cloud:$ownerUid');
      }
    }
    final rowAfter = await _db.getUserById(userId);
    if (rowAfter == null) return false;
    _setFromRow(rowAfter);
    await _bindDeviceToOwner(rowAfter);
    await prefs.setInt(_prefUserId, userId);
    final role = (rowAfter['role'] as String?)?.trim() ?? 'staff';
    await SessionResumeContext.recordActiveSession(
      userId: userId,
      rootRoute: role == 'owner' ? '/home' : '/open-shift',
    );
    await _refreshTenantContextSilently();
    if (deviceBound) {
      await ensureCloudSessionActive();
      if (Supabase.instance.client.auth.currentUser != null) {
        unawaited(hydrateCloudAccountData(forcePull: false));
      }
    }
    notifyListeners();
    return true;
  }

  String _normalizeAuthEmail(String raw) {
    var s = raw.trim().toLowerCase();
    while (s.contains('@@')) {
      s = s.replaceAll('@@', '@');
    }
    return s;
  }

  bool _looksLikeEmail(String value) {
    final s = _normalizeAuthEmail(value);
    if (s.isEmpty || !s.contains('@')) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }

  bool _isCloudLinkedOwnerRow(Map<String, dynamic> row) {
    final role = (row['role'] as String? ?? 'staff').trim();
    if (role != 'owner') return false;
    final supabaseUid = (row['supabaseUid'] as String?)?.trim() ?? '';
    if (supabaseUid.isNotEmpty) return true;
    return _looksLikeEmail((row['email'] as String?) ?? '');
  }

  String? _cloudLoginEmailForRow(Map<String, dynamic> row, String login) {
    final email = ((row['email'] as String?) ?? '').trim().toLowerCase();
    if (_looksLikeEmail(email)) return email;
    final loginKey = login.trim().toLowerCase();
    if (_looksLikeEmail(loginKey)) return loginKey;
    return null;
  }

  Future<void> _rejectStaleCloudLocalLogin(
    Map<String, dynamic> row, {
    String? email,
  }) async {
    final mail = email ?? _cloudLoginEmailForRow(row, '');
    await _clearSecureAuthCredentialsForEmail(mail);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      AppLogger.warn('AuthProvider', 'reject stale cloud login signOut: $e');
    }
    if ((row['role'] as String?) == 'owner') {
      await clearDeviceOwnerBinding();
    }
  }

  /// يمنع دخول «شبح» بـ PIN محلي بعد حذف الحساب من السحابة (عند توفر شبكة).
  Future<String?> _blockGhostLoginIfCloudDead({
    required Map<String, dynamic> row,
    required String login,
  }) async {
    if (!_isCloudLinkedOwnerRow(row)) return null;

    final linkedUid = (row['supabaseUid'] as String?)?.trim() ?? '';
    final mail = _cloudLoginEmailForRow(row, login);

    try {
      await session_freshness.ensureFreshSession();
    } on session_freshness.SessionExpiredException {
      // انتهت الجلسة — نُعيد المحاولة أدناه.
    } catch (e) {
      if (_isLikelyNetworkError(e)) return null;
    }

    var session = Supabase.instance.client.auth.currentUser;

    if (session == null && mail != null) {
      final storedPwd = await OwnerSupabaseCredentialStore.instance.read(mail);
      if (storedPwd != null && storedPwd.isNotEmpty) {
        final outcome = await _attemptSupabasePasswordSignIn(
          mail: mail,
          password: storedPwd,
        );
        if (outcome == _SupabaseSignInOutcome.success) {
          session = Supabase.instance.client.auth.currentUser;
        } else if (outcome == _SupabaseSignInOutcome.invalidCredentials) {
          await _rejectStaleCloudLocalLogin(row, email: mail);
          return kLoginNoCloudAccountMessage;
        } else {
          return null;
        }
      }
    }

    if (session == null) return null;

    if (linkedUid.isNotEmpty && session.id != linkedUid) {
      await _rejectStaleCloudLocalLogin(row, email: mail);
      return 'الحساب على هذا الجهاز لم يعد متاحاً. '
          'سجّل الدخول عبر Google أو أنشئ حساباً جديداً.';
    }

    final status = await _resolveTenantCloudStatus().timeout(
      const Duration(seconds: 12),
      onTimeout: () => TenantCloudStatus.networkError,
    );
    if (status == TenantCloudStatus.networkError) return null;
    if (status == TenantCloudStatus.incomplete) {
      await _rejectStaleCloudLocalLogin(row, email: mail);
      return kLoginNoCloudAccountMessage;
    }
    return null;
  }

  /// دخول المالك من بوابة الموظفين عبر Supabase — بدون مطابقة محلية خاطئة.
  ///
  /// يعتمد على [username] + uid المالك المربوط بالجهاز — لا يستخدم email الثانوي.
  Future<bool> signInOwnerFromEmployeeGate(
    Map<String, dynamic> row,
    String password,
  ) async {
    Map<String, dynamic> ownerRow = row;
    try {
      final prefs = await SharedPreferences.getInstance();
      final boundUid =
          (prefs.getString(_prefDeviceOwnerSupabaseUid) ?? '').trim();
      if (boundUid.isNotEmpty) {
        final byUid = await _db.getUserBySupabaseUid(boundUid);
        if (byUid != null) ownerRow = byUid;
      }
    } catch (e) {
      AppLogger.warn('AuthProvider', 'owner gate read bound uid failed: $e');
    }

    final candidates = <String>[];
    void addCandidate(String? value) {
      if (!_looksLikeEmail(value ?? '')) return;
      final s = _normalizeAuthEmail(value!);
      if (candidates.any((c) => c == s)) return;
      candidates.add(s);
    }

    addCandidate(ownerRow['username'] as String?);
    try {
      addCandidate(Supabase.instance.client.auth.currentUser?.email);
    } catch (e) {
      AppLogger.warn('AuthProvider', 'owner gate current session email read failed: $e');
    }

    AppLogger.info(
      'AuthProvider',
      'signInOwnerFromEmployeeGate candidates count=${candidates.length}',
    );

    for (final login in candidates) {
      if (await _loginViaSupabaseFallback(login, password)) return true;
    }
    return false;
  }

  String _mapSignInPasswordError(AuthException e) {
    final lower = e.message.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid email or password') ||
        lower.contains('invalid credentials')) {
      return 'البريد أو كلمة المرور غير صحيحة. تحقق من الحساب على supabase أو أعد تعيين كلمة المرور.';
    }
    if (lower.contains('email not confirmed')) {
      return 'البريد غير مُفعَّل بعد. أكمل التحقق من الرمز المرسل إلى بريدك.';
    }
    if (lower.contains('banned')) {
      return 'تعذّر الدخول بهذا الحساب. تواصل مع الدعم.';
    }
    return 'تعذّر تسجيل الدخول عبر السحابة. تحقق من الاتصال ثم أعد المحاولة.';
  }

  String _userFacingLocalSetupError({required bool emailAlreadyVerified}) {
    if (emailAlreadyVerified) {
      return 'تعذّر إكمال إنشاء الحساب على الجهاز. '
          'أغلِق التطبيق تماماً ثم جرّب «تسجيل الدخول» بنفس البريد وكلمة السر.';
    }
    return 'تعذّر تسجيل الدخول على هذا الجهاز. '
        'تحقق من الإنترنت، أغلِق التطبيق تماماً، ثم أعد المحاولة.';
  }

  /// دخول سحابي عندما لا يكفي الصف المحلي (جهاز جديد / hash فارغ / PIN مختلف).
  ///
  /// الترتيب:
  /// 1. جلسة Supabase حالية بنفس البريد → تحقق PIN مقابل `owner_auth_secrets`.
  /// 2. كلمة سر Supabase داخلية محفوظة على الجهاز → `signInWithPassword`.
  /// 3. لا شيء مما سبق → رسالة للمستخدم (Google أو حساب جديد).
  Future<bool> _loginViaSupabaseFallback(String login, String password) async {
    final mail = _normalizeAuthEmail(login);
    AppLogger.info('AuthProvider', '_loginViaSupabaseFallback start');
    if (mail.isEmpty || !mail.contains('@')) {
      _lastLoginErrorMessage = 'استخدم البريد الإلكتروني لتسجيل الدخول السحابي.';
      return false;
    }

    final pin = password.trim();
    if (!AuthValidators.isValidPin(pin)) {
      _lastLoginErrorMessage =
          'رمز الدخول يجب أن يكون 4 أرقام.';
      return false;
    }

    try {
      final offline = await _networkBlockMessageIfOffline();
      if (offline != null) {
        _lastLoginErrorMessage = offline;
        return false;
      }

      final existingUser = Supabase.instance.client.auth.currentUser;
      if (existingUser != null &&
          existingUser.email?.toLowerCase() == mail) {
        return _completeCloudLoginAfterSession(mail: mail, pin: pin);
      }

      final storedPwd = await OwnerSupabaseCredentialStore.instance.read(mail);
      if (storedPwd != null && storedPwd.isNotEmpty) {
        final outcome = await _attemptSupabasePasswordSignIn(
          mail: mail,
          password: storedPwd,
        );
        if (outcome == _SupabaseSignInOutcome.success) {
          return _completeCloudLoginAfterSession(mail: mail, pin: pin);
        }
        if (outcome == _SupabaseSignInOutcome.networkError) {
          _lastLoginErrorMessage = kAuthServerUnreachableMessage;
          return false;
        }
        // كلمة محفوظة من حساب محذوف/مُعاد تسجيله — لا تُعيق مسار OTP.
        AppLogger.info(
          'AuthProvider',
          '_loginViaSupabaseFallback: clearing stale stored supabase password',
        );
        await _clearSecureAuthCredentialsForEmail(mail);
        _lastLoginErrorMessage = kLoginNoCloudAccountMessage;
        return false;
      }

      _lastLoginErrorMessage = kLoginNoCloudAccountMessage;
      return false;
    } on session_freshness.SessionExpiredException {
      AppLogger.info('AuthProvider', '_loginViaSupabaseFallback: session expired');
      _lastLoginErrorMessage =
          'انتهت الجلسة السحابية. سجّل الدخول عبر Google أو أنشئ حساباً جديداً.';
      return false;
    } catch (e, st) {
      AppLogger.warn('AuthProvider', 'cloud login local setup failed: $e');
      if (kDebugMode) {
        AppLogger.error('AuthProvider', 'cloud login local setup stack', e, st);
      }
      if (e is StateError && e.message.trim().isNotEmpty) {
        _lastLoginErrorMessage = e.message.trim();
      } else if (_isLikelyNetworkError(e)) {
        _lastLoginErrorMessage = kAuthServerUnreachableMessage;
      } else {
        _lastLoginErrorMessage =
            _userFacingLocalSetupError(emailAlreadyVerified: false);
      }
      return false;
    }
  }

  Future<bool> _signInWithSupabasePassword({
    required String mail,
    required String password,
  }) async {
    final outcome = await _attemptSupabasePasswordSignIn(
      mail: mail,
      password: password,
    );
    if (outcome == _SupabaseSignInOutcome.networkError) {
      _lastLoginErrorMessage = kAuthServerUnreachableMessage;
    }
    return outcome == _SupabaseSignInOutcome.success;
  }

  Future<_SupabaseSignInOutcome> _attemptSupabasePasswordSignIn({
    required String mail,
    required String password,
    bool persistCredentialOnSuccess = true,
  }) async {
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: mail,
        password: password,
      );
      if (res.user != null) {
        if (persistCredentialOnSuccess) {
          await _persistOwnerSupabaseCredential(mail, password);
        }
        return _SupabaseSignInOutcome.success;
      }
      return _SupabaseSignInOutcome.invalidCredentials;
    } on AuthException catch (e) {
      if (_isLikelyNetworkErrorMessage(e.message)) {
        return _SupabaseSignInOutcome.networkError;
      }
      AppLogger.warn('AuthProvider', 'signInWithPassword failed: ${e.message}');
      return _SupabaseSignInOutcome.invalidCredentials;
    } catch (e) {
      if (_isLikelyNetworkError(e)) {
        return _SupabaseSignInOutcome.networkError;
      }
      AppLogger.warn('AuthProvider', 'signInWithPassword unexpected: $e');
      return _SupabaseSignInOutcome.invalidCredentials;
    }
  }

  /// بعد توفر جلسة Supabase بنفس البريد: تحقق PIN مقابل السحابة ثم أكمل الدخول.
  Future<bool> _completeCloudLoginAfterSession({
    required String mail,
    required String pin,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.email?.toLowerCase() != mail) {
      _lastLoginErrorMessage =
          'لا توجد جلسة سحابية مطابقة. سجّل الدخول عبر Google.';
      return false;
    }

    final tenantStatus = await _resolveTenantCloudStatus().timeout(
      const Duration(seconds: 15),
      onTimeout: () => TenantCloudStatus.networkError,
    );
    if (tenantStatus == TenantCloudStatus.networkError) {
      _lastLoginErrorMessage = kAuthServerUnreachableMessage;
      await _signOutSupabaseAfterFailedGoogleLink();
      return false;
    }
    if (tenantStatus == TenantCloudStatus.incomplete) {
      _lastLoginErrorMessage =
          'لا يوجد حساب مكتمل بهذا البريد. أنشئ حساباً جديداً أولاً.';
      await _signOutSupabaseAfterFailedGoogleLink();
      return false;
    }

    final secret = await OwnerAuthCloudService.instance.fetch();
    if (secret == null || !secret.isComplete) {
      _lastLoginErrorMessage =
          'تعذر التحقق من بيانات الحساب على السحابة. حاول مرة أخرى.';
      await _signOutSupabaseAfterFailedGoogleLink();
      return false;
    }
    if (!await PasswordHashing.verifyPin(pin, secret.pinSalt, secret.pinHash)) {
      _lastLoginErrorMessage = AuthUserMessages.wrongPin;
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        AppLogger.warn('AuthProvider', 'signOut after bad PIN: $e');
      }
      return false;
    }

    final email = (user.email ?? mail).trim();
    final displayName =
        (user.userMetadata?['full_name'] as String?) ??
        (user.userMetadata?['name'] as String?) ??
        email.split('@').first;

    await _bindAccountDataScope(
      'cloud:${user.id}',
      allowUnsyncedDataLoss: true,
    );
    final localId = await _db.upsertGoogleUser(
      supabaseUid: user.id,
      email: email,
      displayName: displayName,
      asDeviceOwner: true,
    );
    AppLogger.info('AuthProvider', '_loginViaSupabaseFallback: local row ready');

    final newSalt = PasswordHashing.generateSalt();
    final newHash = await PasswordHashing.hashPin(pin, newSalt);
    await _db.updateUserPasswordByLogin(
      login: email,
      passwordHash: newHash,
      passwordSalt: newSalt,
    );
    await _db.reconcileCloudOwnerLoginIdentity(
      localId: localId,
      canonicalEmail: email,
    );

    final localRow = await _db.getUserById(localId);
    if (localRow == null) {
      _lastLoginErrorMessage =
          _userFacingLocalSetupError(emailAlreadyVerified: false);
      return false;
    }

    _setFromRow(localRow);
    await _bindDeviceToOwner(localRow);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefUserId, localId);
    final bootstrapErr = await _completeCloudBootstrapAfterRestore(localId);
    if (bootstrapErr != null) {
      _lastLoginErrorMessage = bootstrapErr;
      return false;
    }
    await _refreshTenantContextSilently();
    notifyListeners();
    return true;
  }

  bool _isLikelyNetworkError(Object e) {
    if (e is TimeoutException) return true;
    final type = e.runtimeType.toString();
    if (type == 'SocketException' || type == 'ClientException') return true;
    return _isLikelyNetworkErrorMessage(e.toString());
  }

  bool _isLikelyNetworkErrorMessage(String message) {
    if (AuthUserMessages.isNetworkRelated(message)) return true;
    final s = message.toLowerCase();
    return s.contains('socket') ||
        s.contains('network') ||
        s.contains('connection') ||
        s.contains('host lookup') ||
        s.contains('failed host lookup') ||
        s.contains('timed out') ||
        s.contains('timeout');
  }

  Future<String?> _networkBlockMessageIfOffline() async {
    if (await AuthNetworkGuard.hasNetworkLink()) return null;
    return kAuthNetworkUnavailableMessage;
  }

  bool _isGooglePlatformNetworkIssue(PlatformException e) {
    final code = e.code.toLowerCase();
    final msg = (e.message ?? '').toLowerCase();
    if (_isLikelyNetworkErrorMessage('$code $msg')) return true;
    return code.contains('network') ||
        (code == 'sign_in_failed' &&
            (msg.contains('network') || msg.contains('connection')));
  }

  Future<bool> _ensureSupabaseSessionForLocalCloudAccount({
    required Map<String, dynamic> row,
    required String login,
    required String password,
  }) async {
    final email =
        ((row['email'] as String?)?.trim().toLowerCase().isNotEmpty ?? false)
        ? (row['email'] as String).trim().toLowerCase()
        : login.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) return false;
    try {
      await session_freshness.ensureFreshSession();
      final localId = row['id'] as int?;
      if (localId == null || localId <= 0) return false;
      await _completeCloudBootstrapAfterRestore(localId);
      return true;
    } on session_freshness.SessionExpiredException {
      return false;
    } catch (e) {
      AppLogger.warn('AuthProvider', 'ensure supabase session for local account failed: $e');
      return false;
    }
  }

  Future<void> _tryEnableCloudSessionAfterLocalLogin({
    required Map<String, dynamic> row,
    required String login,
    required String password,
  }) async {
    final supabaseUid = (row['supabaseUid'] as String?)?.trim() ?? '';
    final email = ((row['email'] as String?) ?? '').trim().toLowerCase();
    final loginKey = login.trim().toLowerCase();
    final looksLikeEmail =
        (email.contains('@') && email.isNotEmpty) ||
        (loginKey.contains('@') && loginKey.isNotEmpty);
    if (supabaseUid.isEmpty && !looksLikeEmail) return;

    final localId = row['id'] as int?;
    if (localId == null || localId <= 0) return;

    // لا نُفشل تسجيل الدخول المحلي إذا فشل الربط السحابي (انقطاع شبكة/حساب محلي فقط).
    try {
      if (Supabase.instance.client.auth.currentUser != null) {
        await session_freshness.ensureFreshSession();
      } else {
        await ensureCloudSessionActive();
      }
      if (Supabase.instance.client.auth.currentUser != null) {
        await _completeCloudBootstrapAfterRestore(localId);
      }
    } catch (e) {
      AppLogger.warn('AuthProvider', 'cloud session enable after local login failed: $e');
    }
  }

  /// يعيد null عند النجاح، أو رسالة خطأ عربية.
  Future<String?> register({
    required String displayName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final mail = email.trim().toLowerCase();
    if (mail.isEmpty) return 'البريد مطلوب';
    if (await _db.signupEmailTaken(mail)) {
      return 'هذا البريد مسجّل مسبقاً — سجّل الدخول أو استخدم بريداً آخر';
    }

    final n = await _db.countActiveUsers();
    final role = n == 0 ? 'owner' : 'staff';

    final salt = PasswordHashing.generateSalt();
    final hash = await PasswordHashing.hashPin(password, salt);

    try {
      final id = await _db.insertLocalUser(
        username: mail,
        passwordHash: hash,
        passwordSalt: salt,
        role: role,
        email: email.trim(),
        phone: phone.trim(),
        displayName: displayName.trim(),
      );
      final row = await _db.getUserById(id);
      if (row == null) return 'تعذر قراءة الحساب بعد الإنشاء';
      await _bindAccountDataScope(_dataOwnerKeyForRow(row));
      final rowAfter = await _db.getUserById(id);
      if (rowAfter == null) return 'تعذر قراءة الحساب بعد عزل البيانات';
      _setFromRow(rowAfter);
      await _bindDeviceToOwner(rowAfter);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefUserId, id);
      await LicenseService.instance.ensureLocalTrialStarted();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر إنشاء الحساب. حاول مرة أخرى.';
    }
  }

  // ── OTP عبر البريد الإلكتروني ────────────────────────────────────────────

  String? _mapEmailOtpSendError(
    Object e, {
    required String genericFallback,
  }) {
    if (e is AuthException) {
      if (kDebugMode) {
        AppLogger.warn(
          'Auth',
          'email OTP failed status=${e.statusCode} msg=${e.message}',
        );
      }
      final msg = e.message.toLowerCase();
      final statusCode = int.tryParse('${e.statusCode ?? ''}');
      if (msg.contains('rate limit') ||
          msg.contains('too many') ||
          msg.contains('security purposes') ||
          msg.contains('request this after')) {
        return 'تم تجاوز حد الإرسال. انتظر بضع دقائق ثم حاول مجدداً.';
      }
      if (msg.contains('invalid email') || msg.contains('unable to validate')) {
        return 'البريد الإلكتروني غير صالح.';
      }
      if (msg.contains('not found') ||
          msg.contains('no user') ||
          msg.contains('otp_disabled')) {
        return 'لا يوجد حساب مرتبط بهذا البريد الإلكتروني.';
      }
      if (statusCode == 504 ||
          msg.contains('upstream') ||
          msg.contains('gateway timeout')) {
        return 'تعذّر إرسال بريد التحقق: الخادم تأخر كثيراً. '
            'السبب الشائع: إعداد Gmail SMTP في Supabase غير صحيح. '
            'جرّب المنفذ 587 بدل 465، أو عطّل SMTP المخصّص مؤقتاً من Authentication → Emails.';
      }
      if (msg.contains('smtp') ||
          (msg.contains('mail') && msg.contains('send')) ||
          msg.contains('email provider')) {
        return 'تعذّر إرسال بريد التحقق. راجع إعدادات البريد في Supabase: Authentication → Emails → SMTP.';
      }
      if (msg.contains('network') ||
          msg.contains('connection') ||
          msg.contains('timeout')) {
        return 'تعذّر الوصول لخادم التحقق. إن كان الإنترنت يعمل، '
            'فالمشكلة غالباً من إعداد البريد على Supabase وليس من جهازك.';
      }
      return genericFallback;
    }
    if (kDebugMode) {
      AppLogger.warn('Auth', 'email OTP failed: $e');
    }
    return 'تعذر إرسال رمز التحقق. تحقق من الاتصال بالإنترنت.';
  }

  /// يُرسل رمز OTP إلى [email] عبر Supabase (طول الرمز حسب إعداد المشروع، غالباً 8 أرقام).
  /// يُعيد null عند النجاح أو رسالة خطأ عربية.
  ///
  /// لمسار **إنشاء حساب** استخدم [sendRegistrationOtp] حتى يطابق قالب
  /// «تأكيد التسجيل» ونوع التحقق `OtpType.signup`.
  Future<String?> sendEmailOtp(String email) async {
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email.trim().toLowerCase(),
      );
      return null;
    } on AuthException catch (e) {
      return _mapEmailOtpSendError(
        e,
        genericFallback: 'تعذر إرسال رمز التحقق. حاول مرة أخرى لاحقاً.',
      );
    } catch (e) {
      return _mapEmailOtpSendError(
        e,
        genericFallback: 'تعذر إرسال رمز التحقق. حاول مرة أخرى لاحقاً.',
      );
    }
  }

  String? _validateRegistrationPassword(String password) {
    if (password.length < 8) {
      return 'كلمة السر قصيرة. استخدم 8 أحرف على الأقل مع حرف كبير وصغير ورقم ورمز خاص.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'[0-9]').hasMatch(password) ||
        !RegExp(r'[!@#\$%^&*()_+\-=\[\]{};:,./<>?\\|`~]')
            .hasMatch(password)) {
      return 'كلمة السر لا تحقق الشروط. راجع لوحة الشروط في شاشة التسجيل ثم أعد المحاولة.';
    }
    return null;
  }

  String _generateInternalSupabasePassword() {
    final r = Random.secure();
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghjkmnpqrstuvwxyz';
    const digits = '23456789';
    const special = '!@#\$%^&*';
    String pick(String pool) => pool[r.nextInt(pool.length)];
    final chars = <String>[
      pick(upper),
      pick(lower),
      pick(digits),
      pick(special),
    ];
    const all = upper + lower + digits + special;
    while (chars.length < 32) {
      chars.add(all[r.nextInt(all.length)]);
    }
    chars.shuffle(r);
    return chars.join();
  }

  String _normalizeOwnerPhoneForStorage(String phone) {
    var t = phone.trim();
    if (t.startsWith('+964')) {
      final rest = t.substring(4).replaceFirst(RegExp(r'^0+'), '');
      t = '0$rest';
    }
    return t;
  }

  /// تسجيل يدوي: PIN للمستخدم + كلمة سر Supabase داخلية (مؤقتة في secure storage).
  Future<String?> registerManualWithPin({
    required String email,
    required String phone,
    required String pin,
  }) async {
    final offline = await _networkBlockMessageIfOffline();
    if (offline != null) return offline;

    final mail = email.trim().toLowerCase();
    if (mail.isEmpty || !_looksLikeEmail(mail)) {
      return 'البريد الإلكتروني غير صالح.';
    }
    final phoneErr = _validateGoogleOwnerPhone(phone.trim());
    if (phoneErr != null) return phoneErr;
    final pinErr = _validateGoogleOwnerPin(pin);
    if (pinErr != null) return pinErr;

    // بعد حذف حساب من لوحة الإدارة: امسح كلمات Supabase القديمة.
    await _clearSecureAuthCredentialsForEmail(mail);

    final internalPassword = _generateInternalSupabasePassword();
    try {
      await RegistrationSessionStore.instance.savePendingSupabasePassword(
        mail,
        internalPassword,
      );
    } catch (e) {
      AppLogger.warn('AuthProvider', 'save pending registration password: $e');
      return 'تعذر تهيئة التسجيل. حاول مرة أخرى.';
    }
    return sendRegistrationOtp(email: mail, password: internalPassword);
  }

  Future<String?> readPendingRegistrationSupabasePassword(String email) =>
      RegistrationSessionStore.instance.readPendingSupabasePassword(
        email.trim().toLowerCase(),
      );

  Future<void> clearPendingRegistrationSupabasePassword(String email) =>
      RegistrationSessionStore.instance.clearPendingSupabasePassword(
        email.trim().toLowerCase(),
      );

  /// بعد OTP: استبدال كلمة السر الداخلية بـ PIN محلي + جوال.
  Future<String?> finalizeOwnerPin({
    required int localUserId,
    required String pin,
    required String phone,
  }) async {
    final pinErr = _validateGoogleOwnerPin(pin);
    if (pinErr != null) return pinErr;
    final localPhone = _normalizeOwnerPhoneForStorage(phone);
    final phoneErr = _validateGoogleOwnerPhone(localPhone);
    if (phoneErr != null) return phoneErr;

    try {
      await _db.updateOwnerGoogleProfileCredentials(
        id: localUserId,
        phone: localPhone,
        pin: pin.trim(),
      );
    } catch (e, st) {
      AppLogger.warn('AuthProvider', 'finalizeOwnerPin save: $e');
      if (kDebugMode) {
        AppLogger.error('AuthProvider', 'finalizeOwnerPin stack', e, st);
      }
      return 'تعذر حفظ رمز PIN. حاول مرة أخرى.';
    }

    final rowAfter = await _db.getUserById(localUserId);
    if (rowAfter != null) {
      _setFromRow(rowAfter);
    }
    await _pushOwnerAuthToCloud(localUserId);
    notifyListeners();
    return null;
  }

  Future<String?> _resendRegistrationOtp(String mail) async {
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: mail,
      );
      return null;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already confirmed') ||
          msg.contains('email address not authorized') ||
          (msg.contains('not found') && msg.contains('user'))) {
        return 'لا يمكن إرسال رمز تسجيل جديد لهذا البريد. '
            'إن كان الحساب مُفعَّلاً استخدم «تسجيل الدخول»، '
            'أو احذف المستخدم التجريبي من Supabase ثم أعد المحاولة.';
      }
      return _mapEmailOtpSendError(
        e,
        genericFallback: 'تعذر إعادة إرسال رمز التحقق. حاول لاحقاً.',
      );
    } catch (e) {
      return _mapEmailOtpSendError(
        e,
        genericFallback: 'تعذر إعادة إرسال رمز التحقق. حاول لاحقاً.',
      );
    }
  }

  /// إرسال رمز تسجيل جديد — يستخدم قالب Confirm signup في Supabase.
  Future<String?> sendRegistrationOtp({
    required String email,
    required String password,
  }) async {
    final mail = email.trim().toLowerCase();
    final pwdErr = _validateRegistrationPassword(password);
    if (pwdErr != null) return pwdErr;

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: mail,
        password: password,
      );

      if (response.session != null) {
        return 'هذا البريد جاهز للاستخدام. ارجع واستخدم «تسجيل الدخول» '
            'بنفس البريد وكلمة السر.';
      }

      final user = response.user;
      if (user != null) {
        final confirmedAt = user.emailConfirmedAt;
        if (confirmedAt != null && confirmedAt.isNotEmpty) {
          return 'البريد مُفعَّل مسبقاً. استخدم تسجيل الدخول بدل إنشاء حساب.';
        }
        // تسجيل جديد — Supabase أرسل البريد عادةً.
        return null;
      }

      // حماية من تعداد الحسابات: signUp قد لا يُرجع user — نجرب resend صراحةً.
      return _resendRegistrationOtp(mail);
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') ||
          msg.contains('already been registered') ||
          msg.contains('user already exists')) {
        return _resendRegistrationOtp(mail);
      }
      return _mapEmailOtpSendError(
        e,
        genericFallback: 'تعذر إرسال رمز التحقق. حاول مرة أخرى لاحقاً.',
      );
    } catch (e) {
      return _mapEmailOtpSendError(
        e,
        genericFallback: 'تعذر إرسال رمز التحقق. حاول مرة أخرى لاحقاً.',
      );
    }
  }

  /// يطابق قالب «تأكيد التسجيل» ثم «رمز الدخول» إن لزم.
  Future<AuthResponse> _verifyRegistrationOtp({
    required String email,
    required String otp,
  }) async {
    final mail = email.trim().toLowerCase();
    final token = otp.replaceAll(RegExp(r'\D'), '');
    final auth = Supabase.instance.client.auth;
    AuthException? lastError;

    for (final type in [OtpType.signup, OtpType.email]) {
      try {
        final res = await auth.verifyOTP(
          email: mail,
          token: token,
          type: type,
        );
        if (res.user != null) {
          if (kDebugMode) {
            AppLogger.info('Auth', 'registration OTP verified via $type');
          }
          return res;
        }
      } on AuthException catch (e) {
        lastError = e;
        if (kDebugMode) {
          AppLogger.warn(
            'Auth',
            'registration verifyOTP type=$type: ${e.message}',
          );
        }
      }
    }
    throw lastError ??
        const AuthException('رمز التحقق غير صحيح أو منتهي الصلاحية');
  }

  /// يتحقق من الرمز المُدخل ثم يُنشئ الحساب المحلي ويسجّل الدخول.
  /// يُعيد null عند النجاح أو رسالة خطأ عربية.
  Future<String?> verifyOtpAndRegister({
    required String email,
    required String otp,
    required String displayName,
    required String phone,
    required String password,
  }) async {
    User? verifiedUser;
    try {
      final res = await _verifyRegistrationOtp(
        email: email,
        otp: otp,
      );
      verifiedUser = res.user ?? Supabase.instance.client.auth.currentUser;
      if (verifiedUser == null) {
        return 'رمز التحقق غير صحيح أو منتهي الصلاحية';
      }
    } on AuthException catch (e) {
      final lower = e.message.toLowerCase();
      if (lower.contains('banned')) {
        return 'تعذّر إكمال التحقق بهذا البريد. جرّب بريداً إلكترونياً آخر أو تواصل مع الدعم.';
      }
      return 'رمز التحقق خاطئ أو منتهي الصلاحية.';
    } catch (e) {
      return 'تعذر التحقق من الرمز. حاول مرة أخرى.';
    }
    final user = verifiedUser;

    final mail = (user.email ?? email).trim().toLowerCase();
    if (mail.isEmpty) return 'تعذر إنشاء الحساب. البريد الإلكتروني غير صالح.';

    // توحيد صيغة الجوال للصيغة المحلية 07XXXXXXXXX — يمنع تخزين صيغ مشوّهة
    // مثل +96407… في السحابة أو محلياً.
    final normalizedPhone = _normalizeOwnerPhoneForStorage(phone);

    // كلمة السر ثُبّتت عند signUp قبل إرسال الرمز — لا نعيد إرسالها هنا
    // (Supabase يرفض أحياناً updateUser بنفس كلمة السر بعد OTP).
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {'full_name': displayName.trim(), 'phone': normalizedPhone},
        ),
      );
    } on AuthException catch (e) {
      if (kDebugMode) {
        AppLogger.warn('Auth', 'updateUser(profile) failed: ${e.message}');
      }
      // غير حرج — الحساب مُفعَّل والجلسة موجودة بعد OTP.
    } catch (e) {
      AppLogger.warn('AuthProvider', 'verify email OTP profile update failed: $e');
    }

    try {
      await _bindAccountDataScope(
        'cloud:${user.id}',
        allowUnsyncedDataLoss: true,
      );
      int localId;
      try {
        localId = await _db.upsertGoogleUserSafe(
          supabaseUid: user.id,
          email: mail,
          displayName: displayName.trim(),
          asDeviceOwner: true,
        );
      } on GoogleIdentityCollisionException {
        localId = await _db.upsertGoogleUserSafe(
          supabaseUid: user.id,
          email: mail,
          displayName: displayName.trim(),
          asDeviceOwner: true,
          allowUidRelink: true,
        );
      }

      final salt = PasswordHashing.generateSalt();
      final hash = await PasswordHashing.hashPin(password, salt);
      await _db.updateUserPasswordByLogin(
        login: mail,
        passwordHash: hash,
        passwordSalt: salt,
      );
      await _db.reconcileCloudOwnerLoginIdentity(
        localId: localId,
        canonicalEmail: mail,
      );

      final localRow = await _db.getUserById(localId);
      if (localRow == null) return 'تعذر إنشاء الحساب محلياً.';
      final role = ((localRow['role'] ?? 'staff').toString().trim().isEmpty)
          ? 'staff'
          : (localRow['role'] ?? 'staff').toString().trim();
      await _db.updateUserAdminBasic(
        id: localId,
        displayName: displayName.trim(),
        email: mail,
        phone: normalizedPhone,
        jobTitle: (localRow['jobTitle'] ?? '').toString().trim(),
        role: role,
        phone2: (localRow['phone2'] ?? '').toString().trim(),
        passwordHash: hash,
        passwordSalt: salt,
      );

      final rowAfter = await _db.getUserById(localId);
      if (rowAfter == null) return 'تعذر قراءة الحساب بعد الإنشاء.';
      _setFromRow(rowAfter);
      await _bindDeviceToOwner(rowAfter);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefUserId, localId);

      // احفظ كلمة Supabase الداخلية — دخول لاحق على نفس الجهاز دون OTP.
      await _persistOwnerSupabaseCredential(mail, password);

      final bootstrapErr =
          await _completeCloudBootstrapAfterRestore(localId);
      if (bootstrapErr != null) {
        return bootstrapErr;
      }
      notifyListeners();
      return null;
    } catch (e, st) {
      AppLogger.warn('AuthProvider', 'finalize verify-email local setup failed: $e');
      if (kDebugMode) {
        AppLogger.error(
          'AuthProvider',
          'verifyOtpAndRegister local setup stack',
          e,
          st,
        );
      }
      if (e is StateError) {
        final msg = e.message.trim();
        if (msg.isNotEmpty) return msg;
      }
      if (e is UserGovernanceException) {
        return e.message;
      }
      // Supabase قد يكون فعّل البريد رغم فشل الإعداد المحلي — لا تُربك المستخدم برسالة «رمز خاطئ».
      return _userFacingLocalSetupError(emailAlreadyVerified: true);
    }
  }

  // ── نسيت رمز الدخول (استعادة كلمة السر محلياً عبر OTP البريد) ─────────────

  /// يُرسل رمز تحقق إلى البريد لإعادة تعيين رمز الدخول المحلي.
  Future<String?> sendPasswordResetOtp(String email) async {
    final mail = email.trim().toLowerCase();
    if (mail.isEmpty) return 'أدخل البريد الإلكتروني';
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: mail,
        shouldCreateUser: false,
      );
      return null;
    } on AuthException catch (e) {
      return _mapEmailOtpSendError(
        e,
        genericFallback: 'تعذر إرسال رمز التحقق. حاول مرة أخرى لاحقاً.',
      );
    } catch (e) {
      return _mapEmailOtpSendError(
        e,
        genericFallback: 'تعذر إرسال رمز التحقق. حاول مرة أخرى لاحقاً.',
      );
    }
  }

  /// يتحقق من رمز OTP البريدي — يجرّب أنواع Supabase المختلفة (دخول / تسجيل / magiclink).
  Future<String?> _verifyEmailOtpToken({
    required String email,
    required String otp,
  }) async {
    final mail = email.trim().toLowerCase();
    final token = otp.replaceAll(RegExp(r'\D'), '');
    if (mail.isEmpty) return 'أدخل البريد الإلكتروني';
    if (token.isEmpty) return 'أدخل رمز التحقق';
    if (token.length < 6) {
      return 'رمز التحقق قصير. أدخل $_otpDigitsExpected أرقاماً كما في البريد.';
    }

    final auth = Supabase.instance.client.auth;
    AuthException? lastError;

    for (final type in [
      OtpType.email,
      OtpType.signup,
      OtpType.magiclink,
      OtpType.recovery,
    ]) {
      try {
        final res = await auth.verifyOTP(
          email: mail,
          token: token,
          type: type,
        );
        if (res.user != null) {
          if (kDebugMode) {
            AppLogger.info('Auth', 'email OTP verified via $type');
          }
          return null;
        }
      } on AuthException catch (e) {
        lastError = e;
        if (kDebugMode) {
          AppLogger.warn('Auth', 'verifyOTP type=$type: ${e.message}');
        }
      }
    }

    final lower = lastError?.message.toLowerCase() ?? '';
    if (lower.contains('banned')) {
      return 'تعذّر إكمال التحقق بهذا البريد. جرّب بريداً إلكترونياً آخر أو تواصل مع الدعم.';
    }
    return 'رمز التحقق غير صحيح أو منتهي الصلاحية. '
        'استخدم آخر بريد وصل (رمز الدخول أو تأكيد التسجيل) أو اضغط «إعادة إرسال الرمز».';
  }

  static const int _otpDigitsExpected = OtpConfig.emailOtpLength;

  /// يتحقق من رمز الاستعادة المُدخل. لا يُغير أي بيانات محلية.
  Future<String?> verifyPasswordResetOtp({
    required String email,
    required String otp,
  }) async {
    try {
      return await _verifyEmailOtpToken(email: email, otp: otp);
    } catch (e) {
      AppLogger.warn('AuthProvider', 'verify password-reset OTP failed: $e');
      return 'تعذر التحقق من الرمز. حاول مرة أخرى.';
    }
  }

  /// يحدّث رمز الدخول المحلي + كلمة مرور Supabase (إن كانت الجلسة موجودة بعد verifyOTP).
  Future<String?> resetLocalAndServerPassword({
    required String email,
    required String newPassword,
  }) async {
    final mail = email.trim().toLowerCase();
    if (mail.isEmpty) return 'أدخل البريد الإلكتروني';
    if (!AuthValidators.isValidPin(newPassword.trim())) return 'رمز الدخول يجب أن يكون 4 أرقام';

    // 1) تأكد من جلسة OTP ثم حدّث كلمة المرور على السيرفر.
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;
      if (session == null || user == null) {
        return 'انتهت جلسة التحقق. أعد طلب رمز التحقق ثم حاول مجدداً.';
      }
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      final userEmail = (user.email ?? mail).trim();
      final displayName =
          (user.userMetadata?['full_name'] as String?) ??
          (user.userMetadata?['name'] as String?) ??
          userEmail.split('@').first;
      await _db.upsertGoogleUser(
        supabaseUid: user.id,
        email: userEmail,
        displayName: displayName,
        asDeviceOwner: true,
      );
    } on AuthException catch (e) {
      AppLogger.warn('AuthProvider', 'reset password server auth failed: ${e.message}');
      return 'تعذر تحديث كلمة المرور على السيرفر. حاول مرة أخرى.';
    } catch (e) {
      AppLogger.warn('AuthProvider', 'reset password server update failed: $e');
      return 'تعذر تحديث كلمة المرور على السيرفر. تحقق من الاتصال بالإنترنت.';
    }

    // 2) حدّث رمز الدخول المحلي.
    final salt = PasswordHashing.generateSalt();
    final hash = await PasswordHashing.hashPin(newPassword, salt);
    final ok = await _db.updateUserPasswordByLogin(
      login: mail,
      passwordHash: hash,
      passwordSalt: salt,
    );
    if (!ok) return 'تعذر تحديث رمز الدخول محلياً على هذا الجهاز.';

    // لا نحتفظ بجلسة Supabase الناتجة عن verifyOTP داخل تطبيق محلي.
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      AppLogger.warn('AuthProvider', 'post-reset Supabase signOut failed: $e');
    }
    return null;
  }

  // ── Google Sign-In + مزامنة سحابية ───────────────────────────────────────

  /// يتحقق سحابياً أن البريد غير مربوط بـ auth.users آخر قبل أي ربط محلي.
  Future<String?> _assertIdentityLinkAllowed({
    required String email,
    required String supabaseUid,
  }) async {
    try {
      await Supabase.instance.client.rpc(
        'assert_identity_link_allowed',
        params: {
          'p_email': email.trim().toLowerCase(),
          'p_supabase_uid': supabaseUid,
        },
      );
      return null;
    } on PostgrestException catch (e) {
      final msg = e.message.toUpperCase();
      if (msg.contains('EMAIL_BOUND_TO_OTHER_ACCOUNT')) {
        return 'البريد مربوط بحساب آخر. استخدم نفس طريقة التسجيل السابقة.';
      }
      if (msg.contains('UID_MISMATCH') || msg.contains('NOT_AUTHENTICATED')) {
        return 'تعذّر التحقق من الهوية السحابية. أعد تسجيل الدخول.';
      }
      if (msg.contains('INVALID_EMAIL')) {
        return 'البريد الإلكتروني غير صالح.';
      }
      if (msg.contains('ASSERT_IDENTITY_LINK_ALLOWED') &&
          (msg.contains('COULD NOT FIND') || msg.contains('FUNCTION'))) {
        AppLogger.warn(
          'AuthProvider',
          'assert_identity_link_allowed RPC missing — run migration 20260608',
        );
        if (kStrictRpcEnforcement) {
          return 'خطأ في الإعداد — تواصل مع الدعم';
        }
        return null;
      }
      AppLogger.warn(
        'AuthProvider',
        'assert_identity_link_allowed failed: ${e.message}',
      );
      return 'تعذّر التحقق من ربط الحساب. حاول لاحقاً.';
    } catch (e) {
      AppLogger.warn('AuthProvider', 'assert_identity_link_allowed error: $e');
      return 'تعذّر التحقق من ربط الحساب. تحقق من الاتصال.';
    }
  }

  /// بعد فتح Safari الخارجي: انتظر callback عبر deep link أو حدث signedIn.
  Future<Session?> _waitForGoogleOAuthSession(GoTrueClient client) async {
    var session = client.currentSession;
    if (session != null) return session;

    final completer = Completer<Session?>();
    final sub = client.onAuthStateChange.listen((e) {
      if (e.session != null && !completer.isCompleted) {
        completer.complete(e.session);
      }
    });

    try {
      session = await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => client.currentSession,
      );
      return session ?? client.currentSession;
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _signOutSupabaseAfterFailedGoogleLink() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      AppLogger.warn(
        'AuthProvider',
        'signOut after failed Google link: $e',
      );
    }
  }

  /// بعد OAuth: tenant مكتمل لكن intent خاطئ — إنهاء الجلسة وإرجاع المستخدم للتبويب الصحيح.
  Future<void> _revertGoogleSessionAfterIntentMismatch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefUserId);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      AppLogger.warn(
        'AuthProvider',
        'signOut after Google intent mismatch: $e',
      );
    }
    await CloudSyncService.instance.stopForSignOut();
    _clear(preserveTenant: _deviceOwnerBound);
    notifyListeners();
  }

  /// هل اكتمل إعداد Naboo على السحابة (جوال + PIN في `owner_auth_secrets`).
  ///
  /// يفصل «لا يوجد حساب» عن «تعذر الاتصال» — انقطاع الشبكة لا يعني عدم وجود حساب.
  Future<TenantCloudStatus> _resolveTenantCloudStatus() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      return TenantCloudStatus.incomplete;
    }
    try {
      final secret = await OwnerAuthCloudService.instance.fetch();
      return secret != null
          ? TenantCloudStatus.complete
          : TenantCloudStatus.incomplete;
    } catch (e) {
      AppLogger.warn('AuthProvider', '_resolveTenantCloudStatus: $e');
      return TenantCloudStatus.networkError;
    }
  }

  /// صف المالك المحلي المربوط بالجهاز/جلسة Supabase — لاستئناف إكمال Google.
  Future<Map<String, dynamic>?> getLocalOwnerRow() async {
    try {
      final sessionUid =
          (Supabase.instance.client.auth.currentUser?.id ?? '').trim();
      if (sessionUid.isNotEmpty) {
        final bySession = await _db.getUserBySupabaseUid(sessionUid);
        if (bySession != null) return bySession;
      }

      final prefs = await SharedPreferences.getInstance();
      final deviceOwnerUid =
          (prefs.getString(_prefDeviceOwnerSupabaseUid) ?? '').trim();
      if (deviceOwnerUid.isNotEmpty) {
        final byDevice = await _db.getUserBySupabaseUid(deviceOwnerUid);
        if (byDevice != null) return byDevice;
      }

      final localId = prefs.getInt(_prefUserId);
      if (localId != null) {
        final row = await _db.getUserById(localId);
        if (row != null && (row['role'] as String?) == 'owner') return row;
      }
    } catch (e) {
      AppLogger.warn('AuthProvider', 'getLocalOwnerRow failed: $e');
    }
    return null;
  }

  /// F4 — تجديد جلسة Supabase قبل sync/bootstrap/realtime (بدون `autoRefreshToken`).
  static Future<void> ensureFreshSession() =>
      session_freshness.ensureFreshSession();

  /// هل اكتمل جوال + PIN للمالك **محلياً** — لمسار OTP (sync فقط).
  static bool isGoogleOwnerProfileCompleteLocal(Map<String, dynamic> row) {
    final phone = (row['phone'] as String?)?.trim() ?? '';
    if (!AuthValidators.isValidIraqiPhone(phone)) return false;
    final salt = (row['passwordSalt'] as String?)?.trim() ?? '';
    final hash = (row['passwordHash'] as String?)?.trim() ?? '';
    return salt.isNotEmpty && hash.isNotEmpty;
  }

  /// هل اكتمل ملف المالك **محلياً** — جاهز لـ [verifyPinForUser] وبوابة الدخول.
  ///
  /// وجود سر على السحابة وحده **لا** يكفي — يحتاج OTP أولاً.
  Future<bool> isGoogleOwnerProfileCompleteAsync() async {
    final row = await getLocalOwnerRow();
    return row != null && isGoogleOwnerProfileCompleteLocal(row);
  }

  /// سر في `owner_auth_secrets` لكن hash محلي فارغ — يحتاج OTP قبل استخدام PIN.
  Future<bool> cloudHasSecretButLocalEmpty(int localUserId) async {
    return ownerPinRestoreRequiresOtp(localUserId);
  }

  /// يحدد المسار بعد hydrate: bootstrap · OTP · أو إكمال ملف.
  Future<GoogleOwnerProfileGate> resolveGoogleOwnerProfileGate(
    int localUserId,
  ) async {
    final row = await _db.getUserById(localUserId);
    if (row != null && isGoogleOwnerProfileCompleteLocal(row)) {
      return GoogleOwnerProfileGate.complete;
    }
    if (await cloudHasSecretButLocalEmpty(localUserId)) {
      return GoogleOwnerProfileGate.cloudHasSecretButLocalEmpty;
    }
    return GoogleOwnerProfileGate.needsCompleteProfile;
  }

  /// بعد Google OAuth + hydrate: OTP أو إكمال ملف أو bootstrap.
  Future<String?> continueGoogleOwnerSessionAfterHydrate(int localId) async {
    final gate = await resolveGoogleOwnerProfileGate(localId);
    switch (gate) {
      case GoogleOwnerProfileGate.cloudHasSecretButLocalEmpty:
        final otpErr = await beginOwnerPinRestoreOtpFlow();
        if (otpErr != null) return otpErr;
        notifyListeners();
        return kGoogleOwnerPinRestoreOtpRequired;
      case GoogleOwnerProfileGate.needsCompleteProfile:
        notifyListeners();
        return kGoogleOwnerProfileRequired;
      case GoogleOwnerProfileGate.complete:
        final bootstrapErr =
            await _completeCloudBootstrapAfterRestore(localId);
        if (bootstrapErr != null) return bootstrapErr;
        notifyListeners();
        return null;
    }
  }

  /// مسار الإقلاع عند جلسة Supabase نشطة (بعد hydrate في splash).
  Future<String> resolveGoogleOwnerStartupRoute() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      return resolveRouteAfterAuthenticatedSession();
    }
    final row = await getLocalOwnerRow();
    if (row == null) return '/complete-google-profile';
    final localId = (row['id'] as num).toInt();
    final gate = await resolveGoogleOwnerProfileGate(localId);
    switch (gate) {
      case GoogleOwnerProfileGate.cloudHasSecretButLocalEmpty:
        return '/owner-pin-restore-otp';
      case GoogleOwnerProfileGate.needsCompleteProfile:
        return '/complete-google-profile';
      case GoogleOwnerProfileGate.complete:
        return resolveRouteAfterAuthenticatedSession();
    }
  }

  /// مسار إقلاع خفيف — بدون مزامنة مكررة (بعد hydrate في splash).
  Future<String> resolveStartupRouteLight() async {
    if (_deviceAccessRevokedPending) return '/device-access-revoked';
    if (!deviceOwnerBound) return '/login';

    if (Supabase.instance.client.auth.currentUser != null) {
      try {
        final ownerRoute = await googleOwnerProfileRouteIfNeeded().timeout(
          const Duration(seconds: 10),
          onTimeout: () => null,
        );
        if (ownerRoute != null) return ownerRoute;
      } catch (e) {
        AppLogger.warn('AuthProvider', 'resolveStartupRouteLight profile gate: $e');
      }
    }

    // بعد تسجيل الخروج أو انتهاء جلسة Google: بوابة PIN/الدخول —
    // لا نُعيد «إعداد سريع» (اختيار التخصص) بلا جلسة سحابية نشطة.
    final hasCloudSession = Supabase.instance.client.auth.currentUser != null;
    if (!isLoggedIn && !hasCloudSession) {
      return '/employee-gate';
    }

    try {
      final skipOnboarding = await _shouldSkipInitialOnboarding().timeout(
        const Duration(seconds: 4),
        onTimeout: () => true,
      );
      if (!skipOnboarding) return '/onboarding';
    } catch (e) {
      AppLogger.warn('AuthProvider', 'resolveStartupRouteLight onboarding: $e');
    }

    if (!isLoggedIn) return '/employee-gate';
    if (deviceOwnerBound) return '/employee-gate';
    return isOwner ? '/home' : '/open-shift';
  }

  String? _validateGoogleOwnerPhone(String phone) {
    final t = phone.trim();
    if (t.isEmpty) return 'رقم الجوال مطلوب';
    if (!AuthValidators.isValidIraqiPhone(t)) {
      return 'أدخل رقم جوال عراقي صحيح (11 رقماً يبدأ بـ 07)';
    }
    return null;
  }

  String? _validateGoogleOwnerPin(String pin) {
    final t = pin.trim();
    if (t.isEmpty) return 'رمز PIN مطلوب';
    if (!AuthValidators.isValidPin(t)) {
      return 'رمز PIN يجب أن يكون 4 أرقام';
    }
    return null;
  }

  /// بعد OAuth Google: حفظ جوال + PIN ثم bootstrap السحابة.
  ///
  /// يُعيد جلسة Supabase إن انقطعت بعد اختيار حساب Google (شائع على Android
  /// قبل إكمال الجوال+PIN) — عبر refresh، Keychain، أو Google silent/interactive.
  Future<bool> ensureSupabaseSessionForOwnerProfileCompletion({
    bool allowInteractiveGoogle = true,
  }) {
    return ensureCloudSessionActive(
      allowInteractiveGoogle: allowInteractiveGoogle,
    );
  }

  Future<String?> completeGoogleOwnerProfile({
    required String phone,
    required String pin,
  }) async {
    final phoneErr = _validateGoogleOwnerPhone(phone);
    if (phoneErr != null) return phoneErr;
    final pinErr = _validateGoogleOwnerPin(pin);
    if (pinErr != null) return pinErr;

    final ownerRow = await getLocalOwnerRow();
    final localId = (ownerRow?['id'] as num?)?.toInt();
    if (localId == null || localId <= 0) {
      return 'تعذر تحديد حساب المالك على هذا الجهاز. '
          'ارجع وسجّل الدخول من جديد.';
    }

    if (!await _awaitOwnerProfileCompletionPrerequisites()) {
      return 'انقطعت جلسة Google. اضغط «متابعة» مرة أخرى أو سجّل الدخول من جديد.';
    }

    // إكمال الملف = إعداد حساب جديد — ليس استعادة مساحة عمل سابقة.
    _pendingCloudWorkspaceRestore = false;

    try {
      await _db.updateOwnerGoogleProfileCredentials(
        id: localId,
        phone: phone.trim(),
        pin: pin.trim(),
      );
    } catch (e, st) {
      AppLogger.warn('AuthProvider', 'completeGoogleOwnerProfile save: $e');
      if (kDebugMode) {
        AppLogger.error('AuthProvider', 'completeGoogleOwnerProfile stack', e, st);
      }
      return 'تعذر حفظ البيانات. حاول مرة أخرى.';
    }

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'phone': phone.trim()}),
      );
    } on AuthException catch (e) {
      AppLogger.warn(
        'AuthProvider',
        'Google profile metadata update failed: ${e.message}',
      );
    } catch (e) {
      AppLogger.warn('AuthProvider', 'Google profile metadata update: $e');
    }

    final rowAfter = await _db.getUserById(localId);
    if (rowAfter == null) return 'تعذر قراءة الحساب بعد الحفظ.';
    _setFromRow(rowAfter);

    await _pushOwnerAuthToCloud(localId);

    final bootstrapErr = await _completeCloudBootstrapAfterRestore(
      localId,
      requireMandatoryRestore: false,
    );
    if (bootstrapErr != null) return bootstrapErr;
    notifyListeners();
    return null;
  }

  /// بعد عودة OAuth على الويب (إعادة تحميل الصفحة) — يُستدعى من شاشة الإقلاع.
  Future<String?> tryCompletePendingWebGoogleOAuth() async {
    if (!kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefPendingGoogleOAuthIntent);
    if (raw == null || raw.isEmpty) return null;
    if (Supabase.instance.client.auth.currentUser == null) return null;
    if (_googleSignInRunning) return null;

    _googleSignInRunning = true;
    try {
      await prefs.remove(_prefPendingGoogleOAuthIntent);
      final intent = raw == GoogleSignInIntent.signup.name
          ? GoogleSignInIntent.signup
          : GoogleSignInIntent.login;
      return await _finalizeGoogleOAuthSession(intent: intent);
    } catch (e, st) {
      AppLogger.warn('AuthProvider', 'tryCompletePendingWebGoogleOAuth: $e');
      if (kDebugMode) {
        debugPrint('tryCompletePendingWebGoogleOAuth stack: $st');
      }
      return 'فشل إكمال تسجيل Google. أعد المحاولة.';
    } finally {
      _googleSignInRunning = false;
    }
  }

  /// إكمال جلسة Google/OTP: فحص intent مقابل اكتمال الحساب على السحابة
  /// (`owner_auth_secrets`) **قبل** أي كتابة محلية، ثم ربط + hydrate.
  ///
  /// «الحساب موجود» = سر PIN مكتمل على السحابة — وليس مجرد وجود صف في
  /// `auth.users` (OAuth يُنشئ auth.users لحظة الدخول فلا يصلح كفحص).
  Future<String?> _finalizeGoogleOAuthSession({
    required GoogleSignInIntent intent,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return 'لم يكتمل تسجيل الدخول عبر Google.';
    }
    final email = (user.email ?? '').trim();
    if (email.isEmpty) {
      return 'حساب Google لا يحتوي على بريد صالح.';
    }

    final displayName =
        (user.userMetadata?['full_name'] as String?) ??
        (user.userMetadata?['name'] as String?) ??
        email.split('@').first;

    final assertErr = await _assertIdentityLinkAllowed(
      email: email,
      supabaseUid: user.id,
    );
    if (assertErr != null) {
      await _signOutSupabaseAfterFailedGoogleLink();
      return assertErr;
    }

    // فحص اكتمال الحساب قبل أي مسح/كتابة محلية — لا يعتمد على SQLite.
    final tenantStatus = await _resolveTenantCloudStatus().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        AppLogger.warn(
          'AuthProvider',
          '_resolveTenantCloudStatus timed out during Google sign-in',
        );
        return TenantCloudStatus.networkError;
      },
    );
    if (tenantStatus == TenantCloudStatus.networkError) {
      // انقطاع شبكة فقط — لا نلمس ربط الجهاز ولا البيانات المحلية.
      await _signOutSupabaseAfterFailedGoogleLink();
      return kGoogleNetworkError;
    }
    if (intent == GoogleSignInIntent.signup &&
        tenantStatus == TenantCloudStatus.complete) {
      await _revertGoogleSessionAfterIntentMismatch();
      return kGoogleAccountAlreadyExists;
    }
    if (intent == GoogleSignInIntent.login &&
        tenantStatus == TenantCloudStatus.incomplete) {
      await _revertGoogleSessionAfterIntentMismatch();
      return kGoogleNoAccountFound;
    }

    // تبديل نطاق البيانات أولاً: حساب سحابي جديد (uid مختلف) يمسح SQLite
    // بالكامل — وهذا يزيل أيضاً أي صف يتيم بـ uid قديم لنفس البريد
    // (حالة «حذفتُ الحساب ثم أعدت التسجيل بنفس البريد»).
    await _bindAccountDataScope('cloud:${user.id}');

    int localId;
    try {
      localId = await _db.upsertGoogleUserSafe(
        supabaseUid: user.id,
        email: email,
        displayName: displayName,
        asDeviceOwner: true,
      );
    } on GoogleIdentityCollisionException {
      // صف محلي قديم بنفس البريد لكن uid مختلف. السيرفر أكّد للتو
      // (assert_identity_link_allowed) أن البريد غير مربوط بأي حساب حي آخر
      // ⇒ الـ uid المحلي يتيم (حساب محذوف) — يُسمح بإعادة الربط.
      AppLogger.warn(
        'AuthProvider',
        'orphan local uid for this email — relinking after server assert',
      );
      unawaited(
        BusinessAuditLogService.instance.record(
          eventType: 'auth_orphan_uid_relinked',
          entityType: 'auth_session',
          entityId: email,
          newValueJson: jsonEncode({'newSupabaseUid': user.id}),
        ),
      );
      try {
        localId = await _db.upsertGoogleUserSafe(
          supabaseUid: user.id,
          email: email,
          displayName: displayName,
          asDeviceOwner: true,
          allowUidRelink: true,
        );
      } on GoogleIdentityCollisionException catch (e) {
        await _signOutSupabaseAfterFailedGoogleLink();
        return e.message;
      }
    }

    final row = await _db.getUserById(localId);
    if (row == null) {
      await _signOutSupabaseAfterFailedGoogleLink();
      return 'تعذر إنشاء حساب محلي لهذا المستخدم.';
    }

    _setFromRow(row);
    await _bindDeviceToOwner(row);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefUserId, localId);

    await hydrateCloudAccountData(
      timeout: const Duration(seconds: 20),
      forcePull: true,
      forceImportOnPull: true,
    );

    return continueGoogleOwnerSessionAfterHydrate(localId);
  }

  /// المسار الموحّد لتسجيل الدخول/التسجيل عبر Google (ويب + موبايل + ديسكتوب).
  ///
  /// - الويب: مسار ID token المباشر إن فُعّل، وإلا إعادة توجيه (يكمل في الإقلاع).
  /// - الموبايل/الديسكتوب: منتقي حسابات Google الأصلي (مثل Talabat) عبر
  ///   `google_sign_in` + `signInWithIdToken`؛ احتياط: متصفح خارجي + deep link.
  /// - منطق intent الصحيح عبر [_finalizeGoogleOAuthSession] (اكتمال tenant على
  ///   السحابة) بدل فحص وجود auth.users الذي يُنشأ لحظة OAuth.
  Future<GoogleAuthResult> handleGoogleAuth({
    required GoogleSignInIntent intent,
  }) async {
    if (_googleSignInRunning) {
      return GoogleAuthResult.error(
        'جاري تسجيل الدخول عبر Google. يرجى الانتظار.',
      );
    }
    _googleSignInRunning = true;
    try {
      final offline = await _networkBlockMessageIfOffline();
      if (offline != null) {
        return GoogleAuthResult.networkError();
      }

      final client = Supabase.instance.client;

      if (kIsWeb) {
        // مسار ID token المباشر (بدون إعادة توجيه) إن ضُبط GOOGLE_WEB_CLIENT_ID.
        if (GoogleOAuthConfig.isWebIdTokenEnabled) {
          final idTokenOk = await signInWithGoogleIdTokenOnWeb();
          if (idTokenOk) {
            return _mapFinalizeResult(
              await _finalizeGoogleOAuthSession(intent: intent),
            );
          }
        }
        // مسار إعادة التوجيه — الصفحة ستُعاد تحميلها والإكمال في شاشة الإقلاع
        // عبر [tryCompletePendingWebGoogleOAuth].
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefPendingGoogleOAuthIntent, intent.name);
        final res = await client.auth.getOAuthSignInUrl(
          provider: OAuthProvider.google,
          redirectTo: WebAppOrigin.appRootUrl(),
        );
        redirectBrowserToOAuth(res.url);
        return GoogleAuthResult.redirectStarted();
      }

      // موبايل/ديسكتوب: منتقي حسابات Google الأصلي (بدون مغادرة التطبيق).
      final nativeResult = await signInWithGoogleNativeIdToken();
      switch (nativeResult.status) {
        case NativeGoogleIdTokenSignInStatus.success:
          return _mapFinalizeResult(
            await _finalizeGoogleOAuthSession(intent: intent),
          );
        case NativeGoogleIdTokenSignInStatus.cancelled:
          return GoogleAuthResult.cancelled();
        case NativeGoogleIdTokenSignInStatus.error:
          if (nativeResult.message != null &&
              AuthUserMessages.isNetworkRelated(nativeResult.message!)) {
            return GoogleAuthResult.networkError();
          }
          return GoogleAuthResult.error(nativeResult.message);
        case NativeGoogleIdTokenSignInStatus.notConfigured:
          AppLogger.warn(
            'AuthProvider',
            'GOOGLE_WEB_CLIENT_ID not set — native Google picker unavailable',
          );
          if (_prefersNativeGoogleAccountPicker) {
            return GoogleAuthResult.error(
              'إعداد Google غير مكتمل في هذا الإصدار. حدّث التطبيق.',
            );
          }
          break;
      }

      if (_prefersNativeGoogleAccountPicker) {
        return GoogleAuthResult.error(AuthUserMessages.googleUnavailable);
      }

      // احتياط للديسكتوب فقط: متصفح خارجي + deep link.
      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.naboo://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      if (!launched) {
        return GoogleAuthResult.error('تعذر فتح صفحة تسجيل Google.');
      }

      final session = await _waitForGoogleOAuthSession(client.auth).timeout(
        const Duration(seconds: 90),
        onTimeout: () => client.auth.currentSession,
      );
      if (session == null || client.auth.currentUser == null) {
        // لم تصل جلسة — الغالب أن المستخدم أغلق نافذة Google دون إكمال.
        AppLogger.info(
          'AuthProvider',
          'Google sign-in returned no session (likely cancelled)',
        );
        await _signOutSupabaseAfterFailedGoogleLink();
        return GoogleAuthResult.cancelled();
      }

      return _mapFinalizeResult(
        await _finalizeGoogleOAuthSession(intent: intent),
      );
    } on TimeoutException {
      AppLogger.warn('AuthProvider', 'Google sign-in timed out');
      await _signOutSupabaseAfterFailedGoogleLink();
      return GoogleAuthResult.timeout();
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled' || e.code == 'CANCELED') {
        AppLogger.info('AuthProvider', 'Google sign-in cancelled by user');
        return GoogleAuthResult.cancelled();
      }
      AppLogger.warn('AuthProvider', 'Google sign-in platform error: ${e.code}');
      if (_isGooglePlatformNetworkIssue(e)) {
        return GoogleAuthResult.networkError();
      }
      return GoogleAuthResult.error(
        AuthUserMessages.googleUnavailable,
      );
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('cancel')) {
        AppLogger.info('AuthProvider', 'Google sign-in cancelled by user');
        return GoogleAuthResult.cancelled();
      }
      AppLogger.warn('AuthProvider', 'Google sign-in auth error: ${e.message}');
      return GoogleAuthResult.error(AuthUserMessages.googleServerError);
    } on GoogleIdentityCollisionException catch (e) {
      await _signOutSupabaseAfterFailedGoogleLink();
      AppLogger.warn('AuthProvider', 'Google identity collision on sign-in');
      return GoogleAuthResult.error(e.message);
    } catch (e, st) {
      AppLogger.error('AuthProvider', 'Google sign-in unexpected error', e, st);
      if (_isLikelyNetworkError(e)) {
        return GoogleAuthResult.networkError();
      }
      return GoogleAuthResult.error(kAuthServerUnreachableMessage);
    } finally {
      _googleSignInRunning = false;
    }
  }

  /// يحوّل ناتج [_finalizeGoogleOAuthSession] النصّي إلى [GoogleAuthResult] مُصنّف.
  GoogleAuthResult _mapFinalizeResult(String? err) {
    if (err == null) return GoogleAuthResult.loginSuccess();
    switch (err) {
      case kGoogleOwnerProfileRequired:
        return GoogleAuthResult.needsProfileCompletion();
      case kGoogleOwnerPinRestoreOtpRequired:
        return GoogleAuthResult.pinRestoreOtpRequired();
      case kGoogleAccountAlreadyExists:
        return GoogleAuthResult.accountAlreadyExists();
      case kGoogleNoAccountFound:
        return GoogleAuthResult.noAccountFound();
      case kGoogleNetworkError:
        return GoogleAuthResult.networkError();
      default:
        return GoogleAuthResult.error(err);
    }
  }

  /// هل يحتاج المالك OTP قبل سحب PIN من السحابة (سر موجود + محلي ناقص).
  Future<bool> ownerPinRestoreRequiresOtp(int localUserId) async {
    if (Supabase.instance.client.auth.currentUser == null) return false;
    final row = await _db.getUserById(localUserId);
    if (row == null || isGoogleOwnerProfileCompleteLocal(row)) return false;
    try {
      final secret = await OwnerAuthCloudService.instance.fetch();
      return secret != null;
    } catch (e) {
      AppLogger.warn('AuthProvider', 'ownerPinRestoreRequiresOtp: $e');
      return false;
    }
  }

  /// يرسل OTP على بريد المالك قبل استعادة PIN من السحابة.
  Future<String?> beginOwnerPinRestoreOtpFlow() async {
    _ownerPinRestoreOtpVerified = false;
    final email = Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';
    if (email.isEmpty) {
      return 'لا يوجد بريد مرتبط بالحساب. أعد تسجيل الدخول.';
    }
    return sendEmailOtp(email);
  }

  /// بعد OTP ناجح: استعادة PIN من السحابة + bootstrap.
  Future<String?> verifyOwnerPinRestoreOtpAndApply({
    required int localUserId,
    required String otp,
  }) async {
    final email = Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';
    if (email.isEmpty) {
      return 'لا يوجد بريد مرتبط بالحساب. أعد تسجيل الدخول.';
    }

    final verifyErr = await verifyPasswordResetOtp(email: email, otp: otp);
    if (verifyErr != null) return verifyErr;

    _ownerPinRestoreOtpVerified = true;
    try {
      final restored = await tryRestoreOwnerAuthFromCloud(localUserId);
      if (!restored) {
        return 'تعذر استعادة بيانات الحساب من السحابة.';
      }
      final bootstrapErr =
          await _completeCloudBootstrapAfterRestore(localUserId);
      if (bootstrapErr != null) return bootstrapErr;
      notifyListeners();
      return null;
    } finally {
      _ownerPinRestoreOtpVerified = false;
    }
  }

  /// يسحب hash+salt+jوال المالك من Supabase ويطبّقها محلياً — **بعد OTP فقط**.
  Future<bool> tryRestoreOwnerAuthFromCloud(int localId) async {
    if (!_ownerPinRestoreOtpVerified) {
      AppLogger.warn(
        'AuthProvider',
        'tryRestoreOwnerAuthFromCloud blocked without OTP',
      );
      return false;
    }
    if (Supabase.instance.client.auth.currentUser == null) return false;
    try {
      final secret = await OwnerAuthCloudService.instance.fetch();
      if (secret == null) return false;

      await _db.applyOwnerAuthFromCloud(
        id: localId,
        phone: secret.phone,
        pinHash: secret.pinHash,
        pinSalt: secret.pinSalt,
      );

      final row = await _db.getUserById(localId);
      if (row == null || !isGoogleOwnerProfileCompleteLocal(row)) return false;

      _setFromRow(row);

      try {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'phone': secret.phone.trim()}),
        );
      } catch (e) {
        AppLogger.warn(
          'AuthProvider',
          'owner auth cloud restore metadata update: $e',
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.warn('AuthProvider', 'tryRestoreOwnerAuthFromCloud: $e');
      return false;
    }
  }

  Future<void> _pushOwnerAuthToCloud(int localId) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    final row = await _db.getUserById(localId);
    if (row == null || !isGoogleOwnerProfileCompleteLocal(row)) return;

    final phone = (row['phone'] as String?)?.trim() ?? '';
    final hash = (row['passwordHash'] as String?)?.trim() ?? '';
    final salt = (row['passwordSalt'] as String?)?.trim() ?? '';

    try {
      await OwnerAuthCloudService.instance.upsert(
        phone: phone,
        pinHash: hash,
        pinSalt: salt,
      );
    } on PostgrestException catch (e) {
      final msg = e.message.toUpperCase();
      if (msg.contains('APP_UPSERT_OWNER_AUTH_SECRET') &&
          (msg.contains('COULD NOT FIND') || msg.contains('FUNCTION'))) {
        AppLogger.warn(
          'AuthProvider',
          'app_upsert_owner_auth_secret RPC missing — run migration 20260609',
        );
        return;
      }
      AppLogger.warn('AuthProvider', 'push owner auth to cloud: $e');
    } catch (e) {
      AppLogger.warn('AuthProvider', 'push owner auth to cloud: $e');
    }
  }

  /// يتحقق من رمز الدخول/كلمة مرور صاحب العمل قبل عمليات حساسة (مثل الخروج النهائي).
  Future<bool> verifyOwnerConfirmationCredential({
    required Map<String, dynamic> ownerRow,
    required String credential,
  }) async {
    final userId = (ownerRow['id'] as num?)?.toInt();
    if (userId == null || userId <= 0) return false;
    final trimmed = credential.trim();
    if (trimmed.isEmpty) return false;

    final guardScope = PinAttemptGuard.userScope(userId);
    final locked = await PinAttemptGuard.remainingLock(guardScope);
    if (locked != null) return false;

    final localOk = await _db.verifyPinForUser(userId, trimmed);
    if (localOk) {
      await PinAttemptGuard.recordSuccess(guardScope);
      return true;
    }

    // بديل سحابي: نتحقق من الـ PIN مقابل hash/salt المرفوعين على Supabase
    // (owner_auth_secrets) — وليس عبر signInWithPassword بالـ PIN، لأن كلمة
    // سر Supabase الداخلية تختلف عن الـ PIN لحسابات Google/OTP (نمط F4).
    if (Supabase.instance.client.auth.currentUser == null) {
      // لا جلسة سحابية ولا hash محلي → لا يمكن التحقق. لا نحتسبها فشل PIN.
      return false;
    }
    try {
      final secret = await OwnerAuthCloudService.instance.fetch();
      if (secret == null || !secret.isComplete) return false;
      final cloudOk =
          await PasswordHashing.verifyPin(trimmed, secret.pinSalt, secret.pinHash);
      if (cloudOk) {
        await PinAttemptGuard.recordSuccess(guardScope);
        return true;
      }
      await PinAttemptGuard.recordFailure(
        guardScope,
        userId: userId,
        username: ownerRow['username'] as String?,
      );
      return false;
    } catch (e) {
      AppLogger.warn('AuthProvider', 'Owner confirmation cloud verify failed: $e');
      return false;
    }
  }

  /// خروج نهائي من الجهاز: مزامنة + فصل الجهاز على السيرفر + إلغاء الربط + تسجيل خروج كامل.
  ///
  /// [allowOwnerEmergencyOpenShiftLogout] = true يسمح للمالك بالخروج النهائي
  /// رغم وجود وردية مفتوحة (يُسجَّل في `business_audit_events` تلقائياً).
  /// [allowUnsyncedDataLoss] = true يتجاوز فحص قائمة المزامنة (خطر: قد تفقد
  /// عمليات لم تُرفع). لا تستخدمها إلا بعد إنذار صريح للمستخدم.
  Future<String?> signOutPermanentlyFromDevice({
    bool allowOwnerEmergencyOpenShiftLogout = false,
    bool allowUnsyncedDataLoss = false,
    bool ownerEmergencyVerified = false,
    int? ownerEmergencyUserId,
    String? ownerEmergencyUsername,
  }) async {
    if (allowUnsyncedDataLoss && ownerEmergencyVerified) {
      unawaited(
        BusinessAuditLogService.instance.record(
          eventType: 'owner_emergency_sync_bypass',
          entityType: 'sync_queue',
          entityId: 'device_sign_out',
          userId: ownerEmergencyUserId,
          username: ownerEmergencyUsername,
          newValueJson: jsonEncode({
            'action': 'تسجيل الخروج النهائي',
            'allowUnsyncedDataLoss': true,
          }),
        ),
      );
    }
    if (Supabase.instance.client.auth.currentUser != null) {
      final serverErr =
          await CloudSyncService.instance.signOutAndRevokeCurrentDevice();
      if (serverErr != null) return serverErr;
    }
    final emailsToClear = await _collectKnownAuthEmails();
    for (final mail in emailsToClear) {
      await _clearSecureAuthCredentialsForEmail(mail);
    }
    await clearDeviceOwnerBinding();
    await logout(
      allowUnsyncedDataLoss: allowUnsyncedDataLoss,
      allowOwnerEmergencyOpenShiftLogout: allowOwnerEmergencyOpenShiftLogout,
      ownerEmergencyVerified: ownerEmergencyVerified,
      ownerEmergencyUserId: ownerEmergencyUserId,
      ownerEmergencyUsername: ownerEmergencyUsername,
    );
    return null;
  }

  /// خروج من متصفح الويب دون PIN — يمسح الجلسة ويفك الربط محلياً (للتخلي عن الحساب على هذا الجهاز).
  Future<void> signOutWebBrowserOnly() async {
    if (!kIsWeb) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      AppLogger.warn('AuthProvider', 'signOutWebBrowserOnly supabase: $e');
    }
    await CloudSyncService.instance.stopForSignOut();
    await clearDeviceOwnerBinding();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefUserId);
    await prefs.remove(_prefPendingGoogleOAuthIntent);
    await SessionResumeContext.clear();
    _clear();
    notifyListeners();
  }

  /// إعادة محاولة بعد السماح من جهاز نشط — يُحدّث `account_devices` على السيرفر.
  Future<bool> retryDeviceAccessRegistration() async {
    if (Supabase.instance.client.auth.currentUser == null) return false;
    try {
      final access = await CloudSyncService.instance.registerCurrentDevice();
      if (access == DeviceAccessResult.revoked) return false;
      final bootstrap =
          await CloudSyncService.instance.bootstrapForSignedInUser();
      if (bootstrap == CloudBootstrapResult.deviceRevoked) return false;
      if (!bootstrap.isOk) return false;
      // مسح أي جلسة موظف/مالك قديمة — العودة تبدأ من «من سيبدأ العمل؟».
      await lockSession();
      _deviceAccessRevokedPending = false;
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.warn('AuthProvider', 'retryDeviceAccessRegistration failed: $e');
      return false;
    }
  }

  /// خروج كامل بعد رفض/انتهاء محاولات طلب السماح.
  Future<void> abandonRevokedDeviceSession() async {
    _deviceAccessRevokedPending = false;
    await logout(allowUnsyncedDataLoss: true);
  }

  /// يرسل رمز 8 أرقام إلى بريد صاحب الحساب (Supabase OTP).
  Future<String?> sendDeviceAccessRecoveryOtp({String? email}) async {
    final mail = (email ?? Supabase.instance.client.auth.currentUser?.email)
        ?.trim()
        .toLowerCase();
    if (mail == null || mail.isEmpty) {
      return 'أدخل بريد صاحب الحساب أو سجّل الدخول بالبريد أولاً.';
    }
    return sendPasswordResetOtp(mail);
  }

  /// يتحقق من OTP ثم يفعّل هذا الجهاز — مع فصل الأجهزة الأخرى عند الحاجة.
  Future<String?> recoverDeviceAccessViaEmailOtp({
    required String email,
    required String otp,
    bool revokeOtherDevices = true,
  }) async {
    final verifyErr = await verifyPasswordResetOtp(
      email: email,
      otp: otp,
    );
    if (verifyErr != null) return verifyErr;

    final serverErr =
        await CloudSyncService.instance.ownerRecoverCurrentDeviceAfterEmailVerified(
      revokeOthers: revokeOtherDevices,
    );
    if (serverErr != null) return serverErr;

    final bootstrap =
        await CloudSyncService.instance.bootstrapForSignedInUser();
    if (bootstrap == CloudBootstrapResult.deviceRevoked) {
      return 'تعذّر تفعيل هذا الجهاز بعد التحقق. حاول مرة أخرى.';
    }
    if (!bootstrap.isOk) {
      return 'تعذّر إكمال تهيئة الحساب. تحقق من الاتصال.';
    }

    await lockSession();
    _deviceAccessRevokedPending = false;
    notifyListeners();
    return null;
  }

  /// إنهاء جلسة الموظف/المالك الحالية مع الإبقاء على ربط الجهاز بالمالك.
  Future<void> lockSession() async {
    unawaited(
      BusinessAuditLogService.instance.record(
        eventType: 'session_locked',
        entityType: 'auth_session',
        entityId: _userId?.toString() ?? 'unknown',
        userId: _userId,
        username: _username.isNotEmpty ? _username : null,
        newValueJson: jsonEncode({
          'note': 'قفل جلسة — الجهاز يبقى نشطاً على السيرفر',
        }),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefUserId);

    _isLoggedIn = false;
    _userId = null;
    _username = '';
    _displayName = '';
    _role = '';
    _roleKey = 'staff';
    _email = '';
    _phone = '';

    // شاشة «من سيبدأ العمل؟» تحتاج TenantContext لبعض العمليات (مثل الخروج النهائي).
    if (_deviceOwnerBound) {
      final ownerUid =
          prefs.getString(_prefDeviceOwnerSupabaseUid)?.trim() ?? '';
      if (ownerUid.isNotEmpty) {
        TenantContext.instance.set(ownerUid);
      }
      await _refreshTenantContextSilently();
    }

    notifyListeners();
  }

  /// يُعيد جلسة السحابة تلقائياً على الجهاز المربوط — قبل أي مزامنة أو عرض حالة الحساب.
  ///
  /// الترتيب: تحديث الجلسة الحالية → Google بصمت (بدون كلمة مخزّنة) → كلمة السر → Google احتياط.
  Future<bool> ensureCloudSessionActive({
    bool allowInteractiveGoogle = false,
  }) async {
    if (!_deviceOwnerBound) {
      return Supabase.instance.client.auth.currentUser != null;
    }

    final hadSession = Supabase.instance.client.auth.currentUser != null;
    if (await tryRestoreCloudSessionSilently()) {
      unawaited(_bootstrapCloudBridgeIfNeeded(sessionWasRestored: !hadSession));
      if (!hadSession) notifyListeners();
      return true;
    }

    if (allowInteractiveGoogle && _prefersNativeGoogleAccountPicker) {
      try {
        final googleOk = await tryRestoreGoogleSupabaseSessionViaIdToken(
          interactiveIfNeeded: true,
        );
        if (googleOk) {
          unawaited(_bootstrapCloudBridgeIfNeeded(sessionWasRestored: true));
          notifyListeners();
          return true;
        }
      } catch (e) {
        AppLogger.warn('AuthProvider', 'ensureCloudSession Google interactive: $e');
      }
    }

    return Supabase.instance.client.auth.currentUser != null;
  }

  Future<void> _bootstrapCloudBridgeIfNeeded({
    required bool sessionWasRestored,
  }) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    if (!sessionWasRestored &&
        CloudSyncService.instance.isCloudBridgeActive) {
      return;
    }
    try {
      await CloudSyncService.instance.bootstrapForSignedInUser();
    } catch (e) {
      AppLogger.warn('AuthProvider', 'bootstrap cloud bridge: $e');
    }
  }

  /// يُعيد جلسة Supabase بصمت عند انتهائها — باستخدام كلمة السر الداخلية
  /// المحفوظة في Keychain. يُستدعى عند الإقلاع/العودة من الخلفية قبل المزامنة.
  Future<bool> tryRestoreCloudSessionSilently() async {
    if (!_deviceOwnerBound) return false;

    var session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      try {
        await session_freshness.ensureFreshSession();
        return true;
      } on session_freshness.SessionExpiredException {
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (e) {
          AppLogger.warn('AuthProvider', 'silent restore signOut stale: $e');
        }
      } catch (e) {
        if (!session.isExpired) {
          AppLogger.warn(
            'AuthProvider',
            'silent restore refresh deferred (network): $e',
          );
          return true;
        }
        AppLogger.warn('AuthProvider', 'silent restore refresh: $e');
      }
    }

    final ownerRow = await getLocalOwnerRow();
    if (ownerRow == null) return false;

    final candidates = <String>[];
    void addMail(String? value) {
      if (!_looksLikeEmail(value ?? '')) return;
      final s = _normalizeAuthEmail(value!);
      if (!candidates.contains(s)) candidates.add(s);
    }

    addMail(ownerRow['email'] as String?);
    addMail(ownerRow['username'] as String?);

    final hasStoredPassword = await _hasStoredOwnerPassword(candidates);

    if (!hasStoredPassword && _prefersNativeGoogleAccountPicker) {
      try {
        final googleOk = await tryRestoreGoogleSupabaseSessionViaIdToken(
          interactiveIfNeeded: false,
        );
        if (googleOk) {
          AppLogger.info(
            'AuthProvider',
            'silent Google cloud session restored (no stored password)',
          );
          return true;
        }
      } catch (e) {
        AppLogger.warn('AuthProvider', 'silent Google restore (primary): $e');
      }
    }

    for (final mail in candidates) {
      final storedPwd = await OwnerSupabaseCredentialStore.instance.read(mail);
      if (storedPwd == null || storedPwd.isEmpty) continue;
      final outcome = await _attemptSupabasePasswordSignIn(
        mail: mail,
        password: storedPwd,
        persistCredentialOnSuccess: true,
      );
      if (outcome == _SupabaseSignInOutcome.success) {
        AppLogger.info('AuthProvider', 'silent cloud session restored');
        return true;
      }
      if (outcome == _SupabaseSignInOutcome.networkError) {
        AppLogger.warn('AuthProvider', 'silent restore blocked by network');
        return false;
      }
      AppLogger.info(
        'AuthProvider',
        'silent restore failed for stored credential — clearing stale',
      );
      await _clearSecureAuthCredentialsForEmail(mail);
    }

    if (_prefersNativeGoogleAccountPicker) {
      try {
        final googleOk = await tryRestoreGoogleSupabaseSessionViaIdToken(
          interactiveIfNeeded: false,
        );
        if (googleOk) {
          AppLogger.info('AuthProvider', 'silent Google cloud session restored');
          return true;
        }
      } catch (e) {
        AppLogger.warn('AuthProvider', 'silent Google restore failed: $e');
      }
    }

    return false;
  }

  Future<bool> _hasStoredOwnerPassword(List<String> emails) async {
    for (final mail in emails) {
      final storedPwd = await OwnerSupabaseCredentialStore.instance.read(mail);
      if (storedPwd != null && storedPwd.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> logout({
    bool allowUnsyncedDataLoss = false,
    bool allowOwnerEmergencyOpenShiftLogout = false,
    bool ownerEmergencyVerified = false,
    int? ownerEmergencyUserId,
    String? ownerEmergencyUsername,
  }) async {
    await _assertNoBlockingSyncQueue(
      actionLabel: 'تسجيل الخروج',
      allowUnsyncedDataLoss: allowUnsyncedDataLoss,
    );
    await _assertNoOpenShiftForLogout(
      allowOwnerEmergencyOverride: allowOwnerEmergencyOpenShiftLogout,
      ownerEmergencyVerified: ownerEmergencyVerified,
      ownerEmergencyUserId: ownerEmergencyUserId,
      ownerEmergencyUsername: ownerEmergencyUsername,
    );
    unawaited(
      BusinessAuditLogService.instance.record(
        eventType: 'session_logout_cloud',
        entityType: 'auth_session',
        entityId: _userId?.toString() ?? 'unknown',
        userId: _userId,
        username: _username.isNotEmpty ? _username : null,
        newValueJson: jsonEncode({
          'note': 'خروج كامل — الجهاز قد يبقى active على السيرفر',
        }),
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefUserId);
    // لا نمسح OwnerSupabaseCredentialStore عند الخروج العادي — يُستخدم لاستعادة
    // جلسة السحابة على نفس الجهاز. يُمسح عند إلغاء ربط الجهاز بالمالك.
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      AppLogger.warn('AuthProvider', 'Supabase signOut failed: $e');
    }
    // تنظيف جلسة Supabase من SharedPreferences (fallback) لمنع جلسة شبحية
    // عند فشل Keychain (خطأ -34018 على macOS sandbox).
    await _clearSupabaseFallbackSession();
    await CloudSyncService.instance.stopForSignOut();
    await LicenseService.instance.resetLicenseStateForDataScopeChange();
    AppSessionLifecycle.resetAfterSignOut();
    _deviceAccessRevokedPending = false;
    await SessionResumeContext.clear();
    _clear();
    notifyListeners();
  }

  /// يمسح رمز جلسة Supabase من SharedPreferences (fallback storage)
  /// لضمان عدم بقاء جلسة شبحية بعد تسجيل الخروج.
  Future<void> _clearSupabaseFallbackSession() async {
    try {
      final sessionKey = supabasePersistSessionKeyFromUrl(SupabaseConfig.url);
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(sessionKey)) {
        await prefs.remove(sessionKey);
      }
    } catch (e) {
      AppLogger.warn('AuthProvider', 'fallback session clear failed: $e');
    }
  }
}
