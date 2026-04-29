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
  bool _googleSignInRunning = false;

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

    // حماية: إذا كان المفتاح غير موجود (مثلاً بعد تحديث/ترحيل/إعادة تثبيت جزئية)،
    // اعتبره "تبديل" حتى لا تُعرض بيانات حساب سابق بالخطأ.
    final switching = previous == null || previous != newOwnerKey;
    if (switching) {
      await CloudSyncService.instance.stopForSignOut();
      if (newOwnerKey.startsWith('cloud:')) {
        // حساب سحابي: من الآمن حذف الملف بالكامل لأن المصدر الحقيقي سيُسترد من السحابة.
        await _db.closeAndDeleteDatabaseFile();
      } else {
        // حساب محلي: امسح بيانات العمل وابقِ المستخدمين المحليين فقط.
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
    if (!PasswordHashing.verify(password, salt, hash)) return false;

    await _bindAccountDataScope(_dataOwnerKeyForRow(row));
    final rowAfter = await _db.getUserByLogin(login);
    if (rowAfter == null) return false;

    _setFromRow(rowAfter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefUserId, rowAfter['id'] as int);
    await LicenseService.instance.ensureLocalTrialStarted();
    // حاول تفعيل جلسة Supabase تلقائياً للحسابات البريدية (إن كانت سحابية) دون كسر الدخول المحلي.
    await _tryEnableCloudSessionAfterLocalLogin(
      row: rowAfter,
      login: login,
      password: password,
    );
    notifyListeners();
    return true;
  }

  Future<bool> _loginViaSupabaseFallback(String login, String password) async {
    final mail = login.trim().toLowerCase();
    if (mail.isEmpty || !mail.contains('@')) return false;
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: mail,
        password: password,
      );
      final user = res.user ?? Supabase.instance.client.auth.currentUser;
      if (user == null) return false;
      final email = (user.email ?? '').trim();
      if (email.isEmpty) return false;
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

      // احفظ كلمة المرور محلياً حتى يعمل الدخول بدون إنترنت في المرات القادمة
      final newSalt = PasswordHashing.generateSalt();
      final newHash = PasswordHashing.hash(password, newSalt);
      await _db.updateUserPasswordByLogin(
        login: email,
        passwordHash: newHash,
        passwordSalt: newSalt,
      );

      final localRow = await _db.getUserById(localId);
      if (localRow == null) return false;

      _setFromRow(localRow);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefUserId, localId);
      await LicenseService.instance.ensureLocalTrialStarted();
      await _completeCloudBootstrapAfterRestore(localId);
      notifyListeners();
      return true;
    } on AuthException {
      return false;
    } catch (_) {
      return false;
    }
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
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final localId = row['id'] as int?;
      if (localId == null || localId <= 0) return false;
      await _completeCloudBootstrapAfterRestore(localId);
      return true;
    } on AuthException {
      return false;
    } catch (_) {
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

    // لا نُفشل تسجيل الدخول المحلي إذا فشل الربط السحابي (انقطاع شبكة/حساب محلي فقط).
    try {
      await _ensureSupabaseSessionForLocalCloudAccount(
        row: row,
        login: login,
        password: password,
      );
    } catch (_) {}
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

  // ── OTP عبر البريد الإلكتروني ────────────────────────────────────────────

  /// يُرسل رمز OTP إلى [email] عبر Supabase (طول الرمز حسب إعداد المشروع، غالباً 8 أرقام).
  /// يُعيد null عند النجاح أو رسالة خطأ عربية.
  Future<String?> sendEmailOtp(String email) async {
    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email.trim().toLowerCase(),
      );
      return null;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('rate limit') || msg.contains('too many')) {
        return 'تم تجاوز حد الإرسال. انتظر بضع دقائق ثم حاول مجدداً.';
      }
      if (msg.contains('invalid email') || msg.contains('unable to validate')) {
        return 'البريد الإلكتروني غير صالح.';
      }
      return 'تعذر إرسال رمز التحقق: ${e.message}';
    } catch (e) {
      return 'تعذر إرسال رمز التحقق. تحقق من الاتصال بالإنترنت.';
    }
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
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: otp.trim(),
        type: OtpType.email,
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

    // ثبّت كلمة مرور السيرفر مباشرة بعد نجاح OTP لضمان تسجيل الدخول من أي جهاز.
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          password: password,
          data: {
            'full_name': displayName.trim(),
            'phone': phone.trim(),
          },
        ),
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('weak') || msg.contains('password')) {
        return 'رمز الدخول ضعيف. استخدم رمزاً أقوى.';
      }
      return 'تعذر تثبيت رمز الدخول على السيرفر. حاول مجدداً.';
    } catch (_) {
      return 'تعذر تثبيت رمز الدخول على السيرفر. تحقق من الاتصال بالإنترنت.';
    }

    try {
      await _bindAccountDataScope('cloud:${user.id}');
      final localId = await _db.upsertGoogleUser(
        supabaseUid: user.id,
        email: mail,
        displayName: displayName.trim(),
      );

      final salt = PasswordHashing.generateSalt();
      final hash = PasswordHashing.hash(password, salt);
      await _db.updateUserPasswordByLogin(
        login: mail,
        passwordHash: hash,
        passwordSalt: salt,
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
        phone: phone.trim(),
        jobTitle: (localRow['jobTitle'] ?? '').toString().trim(),
        role: role,
        phone2: (localRow['phone2'] ?? '').toString().trim(),
        passwordHash: hash,
        passwordSalt: salt,
      );

      final rowAfter = await _db.getUserById(localId);
      if (rowAfter == null) return 'تعذر قراءة الحساب بعد الإنشاء.';
      _setFromRow(rowAfter);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefUserId, localId);
      await LicenseService.instance.ensureLocalTrialStarted();
      await _completeCloudBootstrapAfterRestore(localId);
      notifyListeners();
      return null;
    } catch (_) {
      return 'تعذر إكمال تجهيز الحساب محلياً. حاول مرة أخرى.';
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
      final msg = e.message.toLowerCase();
      if (msg.contains('rate limit') || msg.contains('too many')) {
        return 'تم تجاوز حد الإرسال. انتظر بضع دقائق ثم حاول مجدداً.';
      }
      if (msg.contains('invalid email') || msg.contains('unable to validate')) {
        return 'البريد الإلكتروني غير صالح.';
      }
      return 'تعذر إرسال رمز التحقق.';
    } catch (_) {
      return 'تعذر إرسال رمز التحقق. تحقق من الاتصال بالإنترنت.';
    }
  }

  /// يتحقق من رمز الاستعادة المُدخل. لا يُغير أي بيانات محلية.
  Future<String?> verifyPasswordResetOtp({
    required String email,
    required String otp,
  }) async {
    final mail = email.trim().toLowerCase();
    if (mail.isEmpty) return 'أدخل البريد الإلكتروني';
    if (otp.trim().isEmpty) return 'أدخل رمز التحقق';
    try {
      final res = await Supabase.instance.client.auth.verifyOTP(
        email: mail,
        token: otp.trim(),
        type: OtpType.email,
      );
      if (res.user == null) {
        return 'رمز التحقق غير صحيح أو منتهي الصلاحية';
      }
      return null;
    } on AuthException catch (e) {
      final lower = e.message.toLowerCase();
      if (lower.contains('banned')) {
        return 'تعذّر إكمال التحقق بهذا البريد. جرّب بريداً إلكترونياً آخر أو تواصل مع الدعم.';
      }
      return 'رمز التحقق غير صحيح أو منتهي الصلاحية';
    } catch (_) {
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
    if (newPassword.trim().length < 8) return 'رمز الدخول قصير جداً';

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
      );
    } on AuthException catch (_) {
      return 'تعذر تحديث كلمة المرور على السيرفر. حاول مرة أخرى.';
    } catch (_) {
      return 'تعذر تحديث كلمة المرور على السيرفر. تحقق من الاتصال بالإنترنت.';
    }

    // 2) حدّث رمز الدخول المحلي.
    final salt = PasswordHashing.generateSalt();
    final hash = PasswordHashing.hash(newPassword, salt);
    final ok = await _db.updateUserPasswordByLogin(
      login: mail,
      passwordHash: hash,
      passwordSalt: salt,
    );
    if (!ok) return 'تعذر تحديث رمز الدخول محلياً على هذا الجهاز.';

    // لا نحتفظ بجلسة Supabase الناتجة عن verifyOTP داخل تطبيق محلي.
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    return null;
  }

  // ── Google Sign-In + مزامنة سحابية ───────────────────────────────────────

  Future<String?> signInWithGoogle() async {
    if (_googleSignInRunning) {
      return 'جاري تسجيل الدخول عبر Google. يرجى الانتظار.';
    }
    _googleSignInRunning = true;
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
    } finally {
      _googleSignInRunning = false;
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
