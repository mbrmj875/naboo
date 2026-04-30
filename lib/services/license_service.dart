import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'license/license_engine.dart';
import 'license/license_engine_v1.dart';
import 'license/license_engine_v2.dart';

// ── خطط الاشتراك ─────────────────────────────────────────────────────────────

class SubscriptionPlan {
  const SubscriptionPlan({
    required this.key,
    required this.nameAr,
    required this.priceIQD,
    required this.maxDevices,
    required this.features,
  });

  final String key;
  final String nameAr;
  final int priceIQD;
  final int maxDevices;
  final List<String> features;

  bool get isUnlimited => maxDevices == 0;

  String get devicesLabel =>
      isUnlimited ? 'أجهزة غير محدودة' : '$maxDevices أجهزة';

  String get priceLabel => '${_fmt(priceIQD)} د.ع / شهر';

  static String _fmt(int p) {
    final s = p.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static const basic = SubscriptionPlan(
    key: 'basic',
    nameAr: 'الأساسية',
    priceIQD: 15000,
    maxDevices: 2,
    features: [
      'جهازان على نفس الحساب',
      'جميع ميزات المخزون والفواتير',
      'التقارير والتحليلات',
      'دعم فني',
    ],
  );

  static const pro = SubscriptionPlan(
    key: 'pro',
    nameAr: 'الاحترافية',
    priceIQD: 30000,
    maxDevices: 3,
    features: [
      '3 أجهزة على نفس الحساب',
      'جميع ميزات الخطة الأساسية',
      'أوامر الشراء وإدارة الموردين',
      'تقارير متقدمة',
      'أولوية في الدعم الفني',
    ],
  );

  static const unlimited = SubscriptionPlan(
    key: 'unlimited',
    nameAr: 'غير المحدودة',
    priceIQD: 50000,
    maxDevices: 0,
    features: [
      'أجهزة غير محدودة على حساب واحد',
      'جميع ميزات الخطة الاحترافية',
      'متعدد الفروع',
      'أولوية قصوى في الدعم',
    ],
  );

  static const all = [basic, pro, unlimited];

  static SubscriptionPlan fromKey(String? k) => switch (k) {
    'basic' => basic,
    'pro' => pro,
    'unlimited' => unlimited,
    _ => basic,
  };
}

// ── مفاتيح الكاش ─────────────────────────────────────────────────────────────

abstract class _Prefs {
  static const licenseKey = 'lic.key';
  static const deviceId = 'lic.device_id';
  static const status = 'lic.status';
  static const expiresAt = 'lic.expires_at';
  static const lastCheckAt = 'lic.last_check';
  static const businessName = 'lic.business_name';
  static const trialEndsAt = 'lic.trial_ends_at';
  static const localTrialStartAt = 'lic.local_trial_start_at';
  static const useCloudTrial = 'lic.use_cloud_trial';
  static const planKey = 'lic.plan';
  static const maxDevices = 'lic.max_devices';
  static const deviceCount = 'lic.device_count';
}

// ── حالة الترخيص ─────────────────────────────────────────────────────────────

enum LicenseStatus {
  trial,
  active,
  expired,
  suspended,
  none,
  checking,
  offline,
  restricted,
  pendingLock,
}

class LicenseState {
  const LicenseState({
    required this.status,
    this.businessName,
    this.expiresAt,
    this.trialEndsAt,
    this.daysLeft,
    this.message,
    this.plan,
    this.registeredDeviceCount = 0,
    this.maxDevices = 1,
  });

  final LicenseStatus status;
  final String? businessName;
  final DateTime? expiresAt;
  final DateTime? trialEndsAt;
  final int? daysLeft;
  final String? message;
  final SubscriptionPlan? plan;
  final int registeredDeviceCount;
  final int maxDevices;

  bool get isAllowed =>
      status == LicenseStatus.trial || status == LicenseStatus.active;
  bool get isUnlimited => maxDevices == 0;
  String get devicesInfo => isUnlimited
      ? 'أجهزة غير محدودة'
      : '$registeredDeviceCount / $maxDevices جهاز';

  static const none = LicenseState(status: LicenseStatus.none);
  static const checking = LicenseState(status: LicenseStatus.checking);
}

// ── الخدمة الرئيسية ───────────────────────────────────────────────────────────

class LicenseService extends ChangeNotifier {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  late final LicenseEngine _engine = LicenseEngineV1(this);
  // v2 activator فقط لتخزين/تحقق JWT من شاشة التفعيل — لا يغير حالة v1 حتى يتم تفعيل feature-flag لاحقاً.
  final LicenseEngineV2 _v2Activator = LicenseEngineV2();

  LicenseState _state = LicenseState.checking;
  LicenseState get state => _state;
  String? _cachedDeviceId;

  // ── تهيئة ─────────────────────────────────────────────────────────────────

  Future<void> initialize() => _engine.initialize();

  // ── معرّف الجهاز ──────────────────────────────────────────────────────────

  Future<String> getDeviceId() => _engine.getDeviceId();

  /// تنفيذ v1 الحالي (سيتحول إلى UUID لاحقاً في v2).
  Future<String> getDeviceIdV1() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_Prefs.deviceId);
    if (saved != null && saved.isNotEmpty) {
      _cachedDeviceId = saved;
      return saved;
    }
    String id = 'unknown-${DateTime.now().millisecondsSinceEpoch}';
    try {
      final p = DeviceInfoPlugin();
      if (Platform.isMacOS) {
        final i = await p.macOsInfo;
        id = '${i.hostName}-${i.model}-${i.systemGUID ?? i.computerName}';
      } else if (Platform.isAndroid) {
        id = (await p.androidInfo).id;
      } else if (Platform.isIOS) {
        final i = await p.iosInfo;
        id = i.identifierForVendor ?? i.name;
      } else if (Platform.isWindows) {
        id = (await p.windowsInfo).deviceId;
      } else if (kIsWeb) {
        id = 'web-${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (_) {}
    id = id.replaceAll(RegExp(r'[^a-zA-Z0-9\-_]'), '-').toLowerCase();
    if (id.length > 64) id = id.substring(0, 64);
    _cachedDeviceId = id;
    await prefs.setString(_Prefs.deviceId, id);
    return id;
  }

  Future<String> getDeviceName() => _engine.getDeviceName();

  Future<String> getDeviceNameV1() async {
    try {
      final p = DeviceInfoPlugin();
      if (Platform.isMacOS) {
        final i = await p.macOsInfo;
        return '${i.model} (${i.computerName})';
      } else if (Platform.isAndroid) {
        final i = await p.androidInfo;
        return '${i.brand} ${i.model}';
      } else if (Platform.isIOS) {
        final i = await p.iosInfo;
        return '${i.name} (${i.model})';
      } else if (Platform.isWindows) {
        return (await p.windowsInfo).computerName;
      }
    } catch (_) {}
    return 'Unknown Device';
  }

  // ── Supabase (عبر Supabase.instance.client) ──────────────────────────────

  Future<Map<String, dynamic>?> _fetchLicense(String key) async {
    final client = Supabase.instance.client;
    final row = await client
        .from('licenses')
        .select()
        .eq('license_key', key)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  Future<void> _patchLicense(String key, Map<String, dynamic> data) async {
    final client = Supabase.instance.client;
    await client.from('licenses').update(data).eq('license_key', key);
  }

  // ── التحقق من الترخيص ─────────────────────────────────────────────────────

  /// يختار ترخيصاً واحداً مفعّلاً ليُربط بهذا الحساب (أفضلية: active ثم trial؛ يتجاهل الموقوف).
  static Map<String, dynamic>? pickBestAssignedLicense(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) return null;
    int statusRank(String raw) {
      switch (raw.toLowerCase()) {
        case 'active':
          return 0;
        case 'trial':
          return 1;
        case 'expired':
          return 2;
        default:
          return 9;
      }
    }

    final usable = rows.where((r) {
      final st = (r['status'] as String? ?? '').toLowerCase();
      return st != 'suspended';
    }).toList();

    if (usable.isEmpty) return null;

    final activeOrTrial =
        usable
            .where((r) {
              final st = (r['status'] as String? ?? '').toLowerCase();
              return st == 'active' || st == 'trial';
            })
            .toList();

    final pool = activeOrTrial.isNotEmpty ? activeOrTrial : usable;

    pool.sort((a, b) {
      final ra = statusRank(a['status'] as String? ?? '');
      final rb = statusRank(b['status'] as String? ?? '');
      if (ra != rb) return ra.compareTo(rb);
      int idVal(Map<String, dynamic> m) {
        final v = m['id'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return 0;
      }

      DateTime? expiresVal(Map<String, dynamic> m) {
        final s = m['expires_at']?.toString();
        if (s == null || s.isEmpty) return null;
        return DateTime.tryParse(s);
      }

      final ea = expiresVal(a);
      final eb = expiresVal(b);
      if (ea != null && eb != null && !ea.isAtSameMomentAs(eb)) {
        return eb.compareTo(ea);
      }
      if (ea != null && eb == null) return -1;
      if (ea == null && eb != null) return 1;
      return idVal(b).compareTo(idVal(a));
    });
    return pool.first;
  }

  /// عند تسجيل الدخول: يجعل الترخيص المربوط بـ assigned_user_id مصدر الحقيقة
  /// ويكتبه في التفضيلات حتى لا يظل جهاز بحفظ مفتاح قديم (مثلاً تجربة basic)
  /// بعد تعيين pro من لوحة الإدارة بدون إدخال مفتاح.
  Future<void> _syncAssignedLicenseFromSupabaseIntoPrefs(
    SharedPreferences prefs,
  ) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final response = await Supabase.instance.client
          .from('licenses')
          .select()
          .eq('assigned_user_id', user.id);
      final maps = List<Map<String, dynamic>>.from(
        (response as List<dynamic>).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      final picked = pickBestAssignedLicense(maps);
      if (picked == null) return;
      final keyRaw = picked['license_key']?.toString().trim() ?? '';
      if (keyRaw.isEmpty) return;
      final key = keyRaw.toUpperCase();
      final prevUpper = (prefs.getString(_Prefs.licenseKey) ?? '').trim().toUpperCase();
      if (prevUpper != key) {
        await prefs.remove(_Prefs.status);
        await prefs.remove(_Prefs.businessName);
        await prefs.remove(_Prefs.expiresAt);
        await prefs.remove(_Prefs.planKey);
        await prefs.remove(_Prefs.maxDevices);
        await prefs.remove(_Prefs.deviceCount);
        await prefs.remove(_Prefs.lastCheckAt);
      }
      await prefs.setString(_Prefs.licenseKey, key);
      await prefs.setBool(_Prefs.useCloudTrial, false);
      await prefs.remove(_Prefs.trialEndsAt);
      await prefs.remove(_Prefs.localTrialStartAt);
    } catch (_) {
      // تجاهل؛ يُكمِل checkLicense بدون تعيين
    }
  }

  Future<void> checkLicense({bool forceRemote = false}) =>
      _engine.checkLicense(forceRemote: forceRemote);

  Future<void> initializeV1() => checkLicenseV1();

  Future<void> checkLicenseV1({bool forceRemote = false}) async {
    _setState(LicenseState.checking);
    final prefs = await SharedPreferences.getInstance();
    await _syncAssignedLicenseFromSupabaseIntoPrefs(prefs);
    var effectiveKey = (prefs.getString(_Prefs.licenseKey) ?? '').trim();
    if (effectiveKey.isEmpty) {
      _setState(_resolveLocalTrialState(prefs));
      return;
    }

    final keyUpper = effectiveKey.toUpperCase();

    final lastMs = prefs.getInt(_Prefs.lastCheckAt) ?? 0;
    final since = DateTime.now().millisecondsSinceEpoch - lastMs;
    final cacheValid = since < const Duration(hours: 1).inMilliseconds;

    if (!forceRemote && cacheValid) {
      final cached = await _loadFromCache(prefs);
      if (cached != null) {
        _setState(cached);
        return;
      }
    }

    try {
      final data = await _fetchLicense(keyUpper);
      if (data == null) {
        _setState(
          const LicenseState(
            status: LicenseStatus.none,
            message: 'مفتاح الترخيص غير صالح',
          ),
        );
        await prefs.remove(_Prefs.licenseKey);
        return;
      }

      final deviceId = await getDeviceId();
      final maxDev = (data['max_devices'] as num?)?.toInt() ?? 2;
      final regDevices =
          (data['registered_devices'] as Map?)?.cast<String, dynamic>() ?? {};
      final isUnlimited = maxDev == 0;
      final isRegistered = regDevices.containsKey(deviceId);

      if (!isRegistered && !isUnlimited && regDevices.length >= maxDev) {
        _setState(
          LicenseState(
            status: LicenseStatus.suspended,
            plan: SubscriptionPlan.fromKey(data['plan'] as String?),
            maxDevices: maxDev,
            registeredDeviceCount: regDevices.length,
            message:
                'وصلت الحد الأقصى للأجهزة ($maxDev) في خطتك. رقِّ خطتك لإضافة أجهزة.',
          ),
        );
        return;
      }

      final result = await _resolveState(
        data,
        keyUpper,
        prefs,
        deviceId,
        regDevices,
      );
      await _saveToCache(prefs, result, keyUpper);
      _setState(result);
    } catch (_) {
      final cached = await _loadFromCache(prefs);
      _setState(
        cached ??
            const LicenseState(
              status: LicenseStatus.offline,
              message: 'لا يوجد اتصال بالإنترنت.',
            ),
      );
    }
  }

  /// حساب الأيام المتبقية بشكل يوم كامل تقريبًا (لا يظهر «0» بينما لا يزال هناك وقت في نفس اليوم).
  static int trialDaysLeftCalendar(DateTime trialEnd, DateTime now) {
    if (!now.isBefore(trialEnd)) return 0;
    final ms = trialEnd.millisecondsSinceEpoch - now.millisecondsSinceEpoch;
    return ((ms + 86400000 - 1) ~/ 86400000).clamp(0, 9999);
  }

  LicenseState _stateFromTrialEndLocal(DateTime trialEnd, {required bool cloud}) {
    final now = DateTime.now();
    if (!now.isBefore(trialEnd)) {
      return LicenseState(
        status: LicenseStatus.expired,
        trialEndsAt: trialEnd,
        plan: SubscriptionPlan.basic,
        maxDevices: SubscriptionPlan.basic.maxDevices,
        registeredDeviceCount: 1,
        message: 'انتهت التجربة المجانية (15 يوم). اختر خطة اشتراك للمتابعة.',
      );
    }
    return LicenseState(
      status: LicenseStatus.trial,
      trialEndsAt: trialEnd,
      daysLeft: trialDaysLeftCalendar(trialEnd, now).clamp(0, 15),
      plan: SubscriptionPlan.basic,
      maxDevices: SubscriptionPlan.basic.maxDevices,
      registeredDeviceCount: 1,
      message: cloud
          ? 'تجربة مجانية 15 يوم من أول تسجيل Google لهذا الحساب (موحّدة لكل الأجهزة).'
          : 'تجربة مجانية مفعلة لمدة 15 يوم من أول استخدام لهذا الجهاز.',
    );
  }

  LicenseState _resolveLocalTrialState(SharedPreferences prefs) {
    final useCloud = prefs.getBool(_Prefs.useCloudTrial) ?? false;
    final endMs = prefs.getInt(_Prefs.trialEndsAt);
    if (useCloud && endMs != null) {
      final trialEnd = DateTime.fromMillisecondsSinceEpoch(endMs);
      return _stateFromTrialEndLocal(trialEnd, cloud: true);
    }

    final trialStartMs =
        prefs.getInt(_Prefs.localTrialStartAt) ??
        DateTime.now().millisecondsSinceEpoch;
    if (!prefs.containsKey(_Prefs.localTrialStartAt)) {
      prefs.setInt(_Prefs.localTrialStartAt, trialStartMs);
    }

    final trialStart = DateTime.fromMillisecondsSinceEpoch(trialStartMs);
    final trialEnd = trialStart.add(const Duration(days: 15));

    return _stateFromTrialEndLocal(trialEnd, cloud: false);
  }

  /// بعد تسجيل Google: تاريخ بداية التجربة في `profiles.trial_started_at` (نفسه لكل الأجهزة).
  ///
  /// مهم: لا نستخدم `upsert` بحقول جزئية فقط — في PostgreSQL قد يصفّر ذلك
  /// أعمدة أخرى مثل `trial_started_at` فيُعاد احتساب الـ 15 يوماً عند كل تسجيل دخول.
  Future<void> applyTrialFromSupabaseProfile() =>
      _engine.applyTrialFromSupabaseProfile();

  Future<void> applyTrialFromSupabaseProfileV1() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      await ensureLocalTrialStarted();
      return;
    }
    final prefsEarly = await SharedPreferences.getInstance();
    await _syncAssignedLicenseFromSupabaseIntoPrefs(prefsEarly);
    if ((prefsEarly.getString(_Prefs.licenseKey) ?? '').trim().isNotEmpty) {
      await checkLicense(forceRemote: true);
      return;
    }
    final accountCreatedAtIso = _supabaseUserCreatedAtIsoUtc(user);
    try {
      final client = Supabase.instance.client;
      var row = await client
          .from('profiles')
          .select('trial_started_at')
          .eq('id', user.id)
          .maybeSingle();

      if (row == null) {
        await client.from('profiles').insert({
          'id': user.id,
          'email': user.email,
          'trial_started_at': accountCreatedAtIso,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        await client.from('profiles').update({
          'email': user.email,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', user.id);
      }

      row = await client
          .from('profiles')
          .select('trial_started_at')
          .eq('id', user.id)
          .maybeSingle();
      dynamic ts = row?['trial_started_at'];
      if (ts == null || ts.toString().isEmpty) {
        await client.from('profiles').update({
          'trial_started_at': accountCreatedAtIso,
        }).eq('id', user.id);
        ts = accountCreatedAtIso;
      }
      final start = DateTime.parse(ts.toString()).toUtc();
      final endUtc = start.add(const Duration(days: 15));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_Prefs.useCloudTrial, true);
      await prefs.setInt(_Prefs.trialEndsAt, endUtc.millisecondsSinceEpoch);
      await prefs.remove(_Prefs.localTrialStartAt);
      _setState(_stateFromTrialEndLocal(endUtc.toLocal(), cloud: true));
    } catch (_) {
      await ensureLocalTrialStarted();
    }
  }

  String _supabaseUserCreatedAtIsoUtc(User user) {
    try {
      final raw = user.toJson()['created_at'];
      if (raw is String && raw.trim().isNotEmpty) {
        return DateTime.parse(raw).toUtc().toIso8601String();
      }
    } catch (_) {}
    return DateTime.now().toUtc().toIso8601String();
  }

  Future<void> ensureLocalTrialStarted() => _engine.ensureLocalTrialStarted();

  Future<void> ensureLocalTrialStartedV1() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_Prefs.useCloudTrial, false);
    if (!prefs.containsKey(_Prefs.localTrialStartAt)) {
      await prefs.setInt(
        _Prefs.localTrialStartAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    if ((prefs.getString(_Prefs.licenseKey) ?? '').isEmpty) {
      _setState(_resolveLocalTrialState(prefs));
    }
  }

  Future<LicenseState> _resolveState(
    Map<String, dynamic> data,
    String licenseKey,
    SharedPreferences prefs,
    String deviceId,
    Map<String, dynamic> regDevices,
  ) async {
    final status = (data['status'] as String?) ?? 'none';
    final businessName = (data['business_name'] as String?) ?? '';
    final plan = SubscriptionPlan.fromKey(data['plan'] as String?);
    final maxDev = (data['max_devices'] as num?)?.toInt() ?? plan.maxDevices;
    final isRegistered = regDevices.containsKey(deviceId);

    // تسجيل الجهاز إذا جديد
    if (!isRegistered) {
      final deviceName = await getDeviceName();
      final updated = Map<String, dynamic>.from(regDevices);
      updated[deviceId] = {
        'name': deviceName,
        'registered_at': DateTime.now().toIso8601String(),
        'last_seen_at': DateTime.now().toIso8601String(),
      };
      await _patchLicense(licenseKey, {'registered_devices': updated});
    } else {
      final updated = Map<String, dynamic>.from(regDevices);
      if (updated[deviceId] is Map) {
        (updated[deviceId] as Map)['last_seen_at'] = DateTime.now()
            .toIso8601String();
      }
      await _patchLicense(licenseKey, {'registered_devices': updated});
    }

    final deviceCount = regDevices.length + (isRegistered ? 0 : 1);

    switch (status) {
      case 'suspended':
        return LicenseState(
          status: LicenseStatus.suspended,
          businessName: businessName,
          plan: plan,
          maxDevices: maxDev,
          registeredDeviceCount: deviceCount,
          message: 'تم إيقاف الترخيص. تواصل مع الدعم.',
        );

      case 'expired':
        return LicenseState(
          status: LicenseStatus.expired,
          businessName: businessName,
          plan: plan,
          maxDevices: maxDev,
          registeredDeviceCount: deviceCount,
          message: 'انتهى الاشتراك. جدّد للمتابعة.',
        );

      case 'trial':
        {
          final trialDays = (data['trial_days'] as num?)?.toInt() ?? 15;
          String? trialStartedAtStr = data['trial_started_at'] as String?;
          if (trialStartedAtStr == null || trialStartedAtStr.isEmpty) {
            trialStartedAtStr = DateTime.now().toIso8601String();
            await _patchLicense(licenseKey, {
              'trial_started_at': trialStartedAtStr,
            });
          }
          final trialStart = DateTime.parse(trialStartedAtStr);
          final trialEnd = trialStart.add(Duration(days: trialDays));
          final now = DateTime.now();
          if (now.isAfter(trialEnd)) {
            await _patchLicense(licenseKey, {'status': 'expired'});
            return LicenseState(
              status: LicenseStatus.expired,
              businessName: businessName,
              plan: plan,
              maxDevices: maxDev,
              registeredDeviceCount: deviceCount,
              trialEndsAt: trialEnd,
              message: 'انتهت فترة التجربة.',
            );
          }
          return LicenseState(
            status: LicenseStatus.trial,
            businessName: businessName,
            plan: plan,
            maxDevices: maxDev,
            registeredDeviceCount: deviceCount,
            trialEndsAt: trialEnd,
            daysLeft: trialDaysLeftCalendar(trialEnd, now).clamp(0, trialDays),
          );
        }

      case 'active':
        {
          final expiresAtStr = data['expires_at'] as String?;
          if (expiresAtStr == null || expiresAtStr.isEmpty) {
            return LicenseState(
              status: LicenseStatus.active,
              businessName: businessName,
              plan: plan,
              maxDevices: maxDev,
              registeredDeviceCount: deviceCount,
            );
          }
          final expiresAt = DateTime.parse(expiresAtStr);
          final now = DateTime.now();
          if (now.isAfter(expiresAt)) {
            await _patchLicense(licenseKey, {'status': 'expired'});
            return LicenseState(
              status: LicenseStatus.expired,
              businessName: businessName,
              plan: plan,
              maxDevices: maxDev,
              registeredDeviceCount: deviceCount,
              expiresAt: expiresAt,
            );
          }
          return LicenseState(
            status: LicenseStatus.active,
            businessName: businessName,
            plan: plan,
            maxDevices: maxDev,
            registeredDeviceCount: deviceCount,
            expiresAt: expiresAt,
            daysLeft: expiresAt.difference(now).inDays,
          );
        }

      default:
        return LicenseState.none;
    }
  }

  // ── تفعيل مفتاح جديد ─────────────────────────────────────────────────────

  Future<({bool ok, String message})> activateLicense(String key) =>
      _engine.activateLicense(key);

  /// تفعيل JWT موقّع (v2). يُستخدم من واجهة إدخال المفتاح فقط.
  Future<({bool ok, String message})> activateSignedToken(String jwt) =>
      _v2Activator.activateLicense(jwt);

  Future<({bool ok, String message})> activateLicenseV1(String key) async {
    final cleaned = key.trim().toUpperCase();
    if (cleaned.isEmpty) return (ok: false, message: 'أدخل مفتاح الترخيص');
    try {
      final data = await _fetchLicense(cleaned);
      if (data == null) {
        return (
          ok: false,
          message: 'مفتاح الترخيص غير صالح. تحقق وأعد المحاولة.',
        );
      }
      final statusVal = (data['status'] as String?) ?? '';
      final maxDev = (data['max_devices'] as num?)?.toInt() ?? 2;
      final regDevices =
          (data['registered_devices'] as Map?)?.cast<String, dynamic>() ?? {};
      final deviceId = await getDeviceId();
      final isReg = regDevices.containsKey(deviceId);

      if (statusVal == 'suspended') {
        return (ok: false, message: 'هذا الترخيص موقوف. تواصل مع الدعم.');
      }
      if (statusVal == 'expired') {
        return (ok: false, message: 'انتهى هذا الترخيص. تواصل لتجديده.');
      }
      if (!isReg && maxDev != 0 && regDevices.length >= maxDev) {
        return (
          ok: false,
          message: 'وصل الحساب للحد الأقصى ($maxDev أجهزة). رقِّ خطتك.',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_Prefs.licenseKey, cleaned);
      await checkLicense(forceRemote: true);
      if (state.isAllowed) {
        return (ok: true, message: 'تم تفعيل الترخيص بنجاح!');
      }
      return (ok: false, message: state.message ?? 'حالة غير معروفة');
    } catch (e) {
      return (ok: false, message: 'خطأ: $e');
    }
  }

  // ── إلغاء الترخيص ────────────────────────────────────────────────────────

  Future<void> deactivate() => _engine.deactivate();

  Future<void> deactivateV1() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [
      _Prefs.licenseKey,
      _Prefs.status,
      _Prefs.expiresAt,
      _Prefs.trialEndsAt,
      _Prefs.useCloudTrial,
      _Prefs.lastCheckAt,
      _Prefs.businessName,
      _Prefs.planKey,
      _Prefs.maxDevices,
      _Prefs.deviceCount,
      _Prefs.localTrialStartAt,
    ]) {
      await prefs.remove(k);
    }
    _setState(LicenseState.none);
  }

  // ── الكاش المحلي ─────────────────────────────────────────────────────────

  Future<LicenseState?> _loadFromCache(SharedPreferences prefs) async {
    final s = prefs.getString(_Prefs.status);
    if (s == null) return null;
    LicenseStatus status;
    try {
      status = LicenseStatus.values.firstWhere((e) => e.name == s);
    } catch (_) {
      return null;
    }
    final businessName = prefs.getString(_Prefs.businessName);
    final expiresMs = prefs.getInt(_Prefs.expiresAt);
    final trialMs = prefs.getInt(_Prefs.trialEndsAt);
    final planK = prefs.getString(_Prefs.planKey);
    final maxDev = prefs.getInt(_Prefs.maxDevices) ?? 1;
    final devCount = prefs.getInt(_Prefs.deviceCount) ?? 1;
    final expiresAt = expiresMs != null
        ? DateTime.fromMillisecondsSinceEpoch(expiresMs)
        : null;
    final trialEndsAt = trialMs != null
        ? DateTime.fromMillisecondsSinceEpoch(trialMs)
        : null;
    int? daysLeft;
    if (status == LicenseStatus.trial && trialEndsAt != null) {
      if (DateTime.now().isAfter(trialEndsAt)) {
        return const LicenseState(
          status: LicenseStatus.expired,
          message: 'انتهت فترة التجربة.',
        );
      }
      daysLeft = trialDaysLeftCalendar(
        trialEndsAt,
        DateTime.now(),
      ).clamp(0, 999);
    } else if (status == LicenseStatus.active && expiresAt != null) {
      if (DateTime.now().isAfter(expiresAt)) {
        return const LicenseState(
          status: LicenseStatus.expired,
          message: 'انتهى الاشتراك.',
        );
      }
      daysLeft = expiresAt.difference(DateTime.now()).inDays.clamp(0, 9999);
    }
    return LicenseState(
      status: status,
      businessName: businessName,
      expiresAt: expiresAt,
      trialEndsAt: trialEndsAt,
      daysLeft: daysLeft,
      plan: SubscriptionPlan.fromKey(planK),
      maxDevices: maxDev,
      registeredDeviceCount: devCount,
    );
  }

  Future<void> _saveToCache(
    SharedPreferences prefs,
    LicenseState s,
    String key,
  ) async {
    await prefs.setString(_Prefs.licenseKey, key);
    await prefs.setString(_Prefs.status, s.status.name);
    await prefs.setInt(
      _Prefs.lastCheckAt,
      DateTime.now().millisecondsSinceEpoch,
    );
    if (s.businessName != null) {
      await prefs.setString(_Prefs.businessName, s.businessName!);
    }
    if (s.expiresAt != null) {
      await prefs.setInt(_Prefs.expiresAt, s.expiresAt!.millisecondsSinceEpoch);
    }
    if (s.trialEndsAt != null) {
      await prefs.setInt(
        _Prefs.trialEndsAt,
        s.trialEndsAt!.millisecondsSinceEpoch,
      );
    }
    if (s.plan != null) await prefs.setString(_Prefs.planKey, s.plan!.key);
    await prefs.setInt(_Prefs.maxDevices, s.maxDevices);
    await prefs.setInt(_Prefs.deviceCount, s.registeredDeviceCount);
  }

  void _setState(LicenseState s) {
    _state = s;
    notifyListeners();
  }
}
