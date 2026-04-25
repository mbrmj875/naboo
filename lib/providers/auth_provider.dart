import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/database_helper.dart';
import '../services/cloud_sync_service.dart'
    show CloudSyncService;
import '../services/license_service.dart';
import '../services/password_hashing.dart';
import '../services/tenant_context_service.dart';

/// جلسة محلية فقط (SharedPreferences + SQLite). بدون سحابة أو اشتراك.
class AuthProvider extends ChangeNotifier {
  static const _prefUserId = 'local_auth_user_id';
  /// يحدّد آخر «مالك بيانات» على الجهاز — لا يُحذف عند الخروج لاكتشاف تبديل الحساب.
  static const _prefActiveDataOwner = 'auth.active_data_owner';

  final DatabaseHelper _db = DatabaseHelper();

  bool _isLoggedIn = false;
  int? _userId;
  String _username = '';
  String _displayName = '';
  String _role = '';
  String _roleKey = 'staff';
  String _email = '';
  String _phone = '';

  bool get isLoggedIn => _isLoggedIn;
  bool get isAdmin => _roleKey == 'admin';
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
    _role = r == 'admin' ? 'مدير النظام' : 'موظف';
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

  /// عند تسجيل الدخول بحساب مختلف: مسح محلي يمنع خلط فواتير/مخزون؛ مع السحابة يُسترد من الخادم.
  Future<void> _bindAccountDataScope(String newOwnerKey) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(_prefActiveDataOwner);
    if (previous == newOwnerKey) return;

    final switching = previous != null && previous != newOwnerKey;
    if (switching) {
      await CloudSyncService.instance.stopForSignOut();
      if (newOwnerKey.startsWith('cloud:')) {
        await _db.closeAndDeleteDatabaseFile();
      } else {
        await _db.wipeBusinessDataKeepUsers();
      }
      await CloudSyncService.instance.clearSyncPreferences();
      await _clearAccountUiPreferences(prefs);
    }
    await prefs.setString(_prefActiveDataOwner, newOwnerKey);
    await TenantContextService.instance.load();
  }

  void _clear() {
    _isLoggedIn = false;
    _userId = null;
    _username = '';
    _displayName = '';
    _role = '';
    _roleKey = 'staff';
    _email = '';
    _phone = '';
  }

  /// استعادة الجلسة بعد إعادة تشغيل التطبيق.
  Future<void> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_prefUserId);

    // إذا لم توجد جلسة محلية لكن توجد جلسة Supabase، أعد ربطها تلقائياً.
    if (id == null) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final email = (user.email ?? '').trim();
          if (email.isNotEmpty) {
            await _bindAccountDataScope('cloud:${user.id}');
            final localId = await _db.upsertGoogleUser(
              supabaseUid: user.id,
              email: email,
              displayName:
                  (user.userMetadata?['full_name'] as String?) ??
                  (user.userMetadata?['name'] as String?) ??
                  email.split('@').first,
            );
            final row = await _db.getUserById(localId);
            if (row != null && (row['isActive'] == 1)) {
              _setFromRow(row);
              await prefs.setInt(_prefUserId, localId);
              // لا تحبس شاشة البداية بعمليات سحابية قد تطول (خصوصاً مع بيانات كبيرة).
              // نُكمل bootstrap + sync في الخلفية.
              unawaited(_completeCloudBootstrapAfterRestore(localId));
              notifyListeners();
              return;
            }
          }
        }
      } catch (_) {}
    }

    if (id == null) {
      _clear();
      notifyListeners();
      return;
    }
    final row = await _db.getUserById(id);
    if (row == null || (row['isActive'] != 1)) {
      await prefs.remove(_prefUserId);
      _clear();
      notifyListeners();
      return;
    }
    _setFromRow(row);
    if (prefs.getString(_prefActiveDataOwner) == null) {
      await prefs.setString(_prefActiveDataOwner, _dataOwnerKeyForRow(row));
    }
    notifyListeners();
  }

  Future<void> _completeCloudBootstrapAfterRestore(int localUserId) async {
    try {
      final bootstrapOk = await CloudSyncService.instance.bootstrapForSignedInUser();
      if (!bootstrapOk) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefUserId);
        await CloudSyncService.instance.stopForSignOut();
        try {
          await Supabase.instance.client.auth.signOut();
        } catch (_) {}
        _clear();
        notifyListeners();
        return;
      }
      await LicenseService.instance.applyTrialFromSupabaseProfile();
      final maxDevices =
          LicenseService.instance.state.plan?.maxDevices ??
          SubscriptionPlan.basic.maxDevices;
      final limitError =
          await CloudSyncService.instance.enforcePlanDeviceLimit(
        maxDevices: maxDevices,
      );
      if (limitError != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefUserId);
        await CloudSyncService.instance.stopForSignOut();
        _clear();
        notifyListeners();
        return;
      }
      // تشغيل المزامنة في الخلفية دون التأثير على التنقل.
      await CloudSyncService.instance.syncNow();
    } catch (_) {
      // لا نقطع واجهة المستخدم بسبب فشل مزامنة عند الإقلاع.
    }
  }

  Future<bool> login(String login, String password) async {
    final row = await _db.getUserByLogin(login);
    if (row == null) return false;
    final salt = row['passwordSalt'] as String?;
    final hash = row['passwordHash'] as String?;
    if (salt == null || hash == null || salt.isEmpty || hash.isEmpty) {
      return false;
    }
    if (!PasswordHashing.verify(password, salt, hash)) return false;

    await _bindAccountDataScope(_dataOwnerKeyForRow(row));
    final rowAfter = await _db.getUserByLogin(login);
    if (rowAfter == null) return false;

    _setFromRow(rowAfter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefUserId, rowAfter['id'] as int);
    await LicenseService.instance.ensureLocalTrialStarted();
    notifyListeners();
    return true;
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
    final role = n == 0 ? 'admin' : 'staff';

    final salt = PasswordHashing.generateSalt();
    final hash = PasswordHashing.hash(password, salt);

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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefUserId, id);
      await LicenseService.instance.ensureLocalTrialStarted();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذر إنشاء الحساب. حاول مرة أخرى.';
    }
  }

  // ── Google Sign-In + مزامنة سحابية ───────────────────────────────────────

  Future<String?> signInWithGoogle() async {
    try {
      final client = Supabase.instance.client;

      final launched = await client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'io.supabase.naboo://login-callback',
      );
      if (!launched) {
        return 'تعذر فتح صفحة تسجيل Google.';
      }

      // على macOS قد يصل callback قبل التقاط حدث signedIn.
      // لذلك ننتظر أي حالة تحوي Session أو نقرأ currentSession دورياً.
      Session? session = client.auth.currentSession;
      if (session == null) {
        final completer = Completer<Session?>();
        final sub = client.auth.onAuthStateChange.listen((e) {
          if (e.session != null && !completer.isCompleted) {
            completer.complete(e.session);
          }
        });
        try {
          for (var i = 0; i < 80 && session == null; i++) {
            session = client.auth.currentSession;
            if (session != null) break;
            if (i % 10 == 0 && !completer.isCompleted) {
              // فرصة لالتقاط event إذا كانت الجلسة لم تُحقن بعد.
              session = await completer.future.timeout(
                const Duration(milliseconds: 300),
                onTimeout: () => null,
              );
              if (session != null) break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        } finally {
          await sub.cancel();
        }
      }

      final user = session?.user ?? client.auth.currentUser;
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

      await _bindAccountDataScope('cloud:${user.id}');
      final localId = await _db.upsertGoogleUser(
        supabaseUid: user.id,
        email: email,
        displayName: displayName,
      );
      final row = await _db.getUserById(localId);
      if (row == null) return 'تعذر إنشاء حساب محلي لهذا المستخدم.';

      _setFromRow(row);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefUserId, localId);
      // لا تحبس واجهة تسجيل الدخول بعمليات سحابية قد تطول (خصوصاً مع بيانات كبيرة).
      // نُكمل bootstrap + sync في الخلفية.
      unawaited(_completeCloudBootstrapAfterRestore(localId));
      notifyListeners();
      return null;
    } on TimeoutException {
      return 'انتهت مهلة تسجيل Google. تحقق من صفحة التفويض ثم أعد المحاولة.';
    } on AuthException catch (e) {
      return 'فشل تسجيل Google: ${e.message}';
    } catch (e) {
      return 'فشل تسجيل Google: $e';
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefUserId);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    await CloudSyncService.instance.stopForSignOut();
    _clear();
    notifyListeners();
  }
}
