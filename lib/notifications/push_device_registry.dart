import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/license_service.dart';
import '../services/permission_service.dart';
import '../services/tenant_context_service.dart';
import '../utils/app_logger.dart';

/// من الداخل على الجهاز الآن (خطة الإشعارات، المرحلة 5).
class PushSession {
  const PushSession({required this.roleKey, this.userId, this.globalId = ''});
  final String roleKey;
  final int? userId;
  final String globalId;

  bool get isOwnerRole => roleKey == 'owner' || roleKey == 'admin';
}

/// تسجيل الجهاز في push_devices، وعلامة «هاتف المالك» على account_devices.
///
/// - الجهاز يرفع دور الداخل عليه ومفاتيح صلاحياته التي توجّه الإشعارات، ويمسحها
///   عند قفل الجلسة أو الخروج (المرحلة 5).
/// - العلامة لا تتغير إلا بالدالة app_set_owner_notify_device بعد رمز المالك.
class PushDeviceRegistry {
  PushDeviceRegistry._();
  static final PushDeviceRegistry instance = PushDeviceRegistry._();

  /// المفاتيح التي يوجّه بها الخادم (جدول الأنواع، خامسا البند 5).
  static const routingPermissionKeys = <String>[
    PermissionKeys.inventoryView,
    PermissionKeys.debtsPanel,
    PermissionKeys.installmentsPlans,
    PermissionKeys.salesPos,
  ];

  /// null = لم يُعرف بعد (بلا اتصال أو بلا جلسة سحابية).
  final ValueNotifier<bool?> accountHasOwnerPhone = ValueNotifier<bool?>(null);
  final ValueNotifier<bool> thisDeviceIsOwnerPhone = ValueNotifier<bool>(false);
  final ValueNotifier<bool> registered = ValueNotifier<bool>(false);

  PushSession? _session;
  Timer? _debounce;
  String? _deviceId;
  bool _tokenListenerAttached = false;

  static bool get isPhone =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get platformLabel {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  PushSession? get session => _session;

  Future<String> deviceId() async {
    final cached = _deviceId;
    if (cached != null && cached.isNotEmpty) return cached;
    final id = (await LicenseService.instance.getDeviceId()).trim();
    _deviceId = id;
    return id;
  }

  /// بعد كل دخول (مالك أو موظف).
  void updateSession(PushSession session) {
    _session = session;
    _scheduleSync();
  }

  /// قفل الجلسة: الجهاز يبقى مسجلا (قد يكون هاتف المالك)، وتُمسح صلاحيات الموظف.
  void clearSession() {
    _session = null;
    _scheduleSync();
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      unawaited(syncNow());
    });
  }

  SupabaseClient? get _client {
    try {
      final c = Supabase.instance.client;
      return c.auth.currentUser == null ? null : c;
    } catch (_) {
      return null;
    }
  }

  /// يسجّل الجهاز ثم يقرأ حالة هاتف المالك.
  Future<void> syncNow() async {
    final client = _client;
    if (client == null) return;
    if (isPhone) {
      await _register(client);
    }
    await refreshOwnerPhoneStatus();
  }

  Future<void> _register(SupabaseClient client) async {
    try {
      if (Firebase.apps.isEmpty) return;
      final messaging = FirebaseMessaging.instance;
      if (!_tokenListenerAttached) {
        _tokenListenerAttached = true;
        messaging.onTokenRefresh.listen((_) => _scheduleSync());
      }
      final token = await messaging.getToken();
      if (token == null || token.trim().isEmpty) return;
      final id = await deviceId();
      if (id.isEmpty) return;

      final s = _session;
      var perms = const <String>[];
      if (s != null && !s.isOwnerRole && (s.userId ?? 0) > 0) {
        final map = await PermissionService.instance
            .getUserPermissionMapForEdit(userId: s.userId!, roleKey: s.roleKey);
        perms = routingPermissionKeys.where((k) => map[k] == true).toList();
      }
      final version = (await PackageInfo.fromPlatform()).version;

      await client.rpc(
        'app_register_push_device',
        params: {
          'p_device_id': id,
          'p_fcm_token': token,
          'p_platform': platformLabel,
          'p_app_version': version,
          'p_local_tenant_id': TenantContextService.instance.activeTenantId,
          'p_role_key': s?.roleKey,
          'p_staff_global_id':
              (s == null || s.isOwnerRole || s.globalId.isEmpty)
              ? null
              : s.globalId,
          'p_permission_keys': perms,
        },
      );
      registered.value = true;
    } on PostgrestException catch (e) {
      registered.value = false;
      // DEVICE_NOT_ACTIVE: الجهاز مفصول. الدالة غير موجودة: الخادم أقدم. لا شيء يُكسر.
      AppLogger.warn('PushRegistry', 'register: ${e.message}');
    } catch (e) {
      registered.value = false;
      AppLogger.warn('PushRegistry', 'register: $e');
    }
  }

  /// يقرأ أجهزة الحساب: هل فيه هاتف مالك؟ وهل هو هذا الجهاز؟
  Future<void> refreshOwnerPhoneStatus() async {
    final client = _client;
    if (client == null) return;
    try {
      final id = await deviceId();
      final rows = await client
          .from('account_devices')
          .select('device_id, owner_notify, access_status')
          .eq('user_id', client.auth.currentUser!.id);
      var any = false;
      var mine = false;
      for (final r in (rows as List).whereType<Map<String, dynamic>>()) {
        final active =
            (r['access_status'] ?? 'active').toString().toLowerCase() ==
            'active';
        final flagged = r['owner_notify'] == true;
        if (active && flagged) {
          any = true;
          if (r['device_id']?.toString() == id) mine = true;
        }
      }
      accountHasOwnerPhone.value = any;
      thisDeviceIsOwnerPhone.value = mine;
    } catch (e) {
      // العمود غير موجود على خادم أقدم، أو بلا اتصال: لا نعرض الشريط.
      AppLogger.warn('PushRegistry', 'owner phone status: $e');
    }
  }

  /// يعلّم جهازا أو يزيل علامته. يُستدعى بعد التحقق من رمز المالك فقط.
  /// يعيد رسالة خطأ بالعربية أو null.
  Future<String?> setOwnerPhone({
    required String deviceId,
    required bool enabled,
  }) async {
    final client = _client;
    if (client == null)
      return 'لا اتصال بالحساب السحابي. اتصل بالإنترنت وحاول مجددا.';
    try {
      await client.rpc(
        'app_set_owner_notify_device',
        params: {'p_device_id': deviceId, 'p_enabled': enabled},
      );
      if (enabled && deviceId == await this.deviceId() && isPhone) {
        await _register(client);
      }
      await refreshOwnerPhoneStatus();
      return null;
    } on PostgrestException catch (e) {
      final m = e.message.toUpperCase();
      if (m.contains('DEVICE_REVOKED')) return 'هذا الجهاز مفصول عن الحساب.';
      if (m.contains('DEVICE_NOT_FOUND'))
        return 'الجهاز غير مسجل في الحساب بعد. أعد المحاولة بعد دقيقة.';
      return 'تعذر الحفظ: ${e.message}';
    } catch (e) {
      return 'تعذر الاتصال بالخادم. حاول مجددا.';
    }
  }

  /// قبل الخروج من الحساب: لا يبقى رمز هذا الجهاز على الحساب.
  Future<void> unregister() async {
    final client = _client;
    if (client == null) return;
    try {
      await client
          .rpc(
            'app_unregister_push_device',
            params: {'p_device_id': await deviceId()},
          )
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      AppLogger.warn('PushRegistry', 'unregister: $e');
    }
    registered.value = false;
    thisDeviceIsOwnerPhone.value = false;
    accountHasOwnerPhone.value = null;
    _session = null;
  }

  /// زر «أرسل إشعارا تجريبيا». يعيد رسالة خطأ أو null.
  Future<String?> sendTest() async {
    final client = _client;
    if (client == null) return 'لا اتصال بالحساب السحابي.';
    if (!registered.value) await syncNow();
    try {
      await client.rpc(
        'app_send_test_notification',
        params: {
          'p_device_id': await deviceId(),
          'p_local_tenant_id': TenantContextService.instance.activeTenantId,
        },
      );
      return null;
    } on PostgrestException catch (e) {
      if (e.message.toUpperCase().contains('DEVICE_NOT_REGISTERED')) {
        return 'هذا الجهاز غير مسجل للإشعارات بعد. تأكد من إذن الإشعارات والإنترنت.';
      }
      return 'تعذر الإرسال: ${e.message}';
    } catch (e) {
      return 'تعذر الاتصال بالخادم.';
    }
  }
}
