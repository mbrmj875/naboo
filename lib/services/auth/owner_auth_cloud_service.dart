import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';
import '../../utils/auth_validators.dart';

/// سر PIN المالك على Supabase — hash+salt فقط (بدون plaintext).
class OwnerAuthCloudSecret {
  const OwnerAuthCloudSecret({
    required this.phone,
    required this.pinHash,
    required this.pinSalt,
    this.hasPin = false,
  });

  final String phone;
  final String pinHash;
  final String pinSalt;

  /// السيرفر قد يخفي الـ hash ويكتفي بالإشارة إلى وجود PIN (المرحلة 2).
  final bool hasPin;

  /// هل الـ hash نفسه وصل؟ (لا يصل إلا بعد رمز بريد حديث في المرحلة 2.)
  bool get hasHashMaterial =>
      pinHash.trim().isNotEmpty && pinSalt.trim().isNotEmpty;

  bool get isComplete =>
      AuthValidators.isValidIraqiPhone(phone) && (hasHashMaterial || hasPin);

  factory OwnerAuthCloudSecret.fromJson(Map<String, dynamic> json) {
    return OwnerAuthCloudSecret(
      phone: (json['phone'] ?? '').toString().trim(),
      pinHash: (json['pin_hash'] ?? json['pinHash'] ?? '').toString().trim(),
      pinSalt: (json['pin_salt'] ?? json['pinSalt'] ?? '').toString().trim(),
      hasPin: json['has_pin'] == true,
    );
  }
}

/// نتيجة التحقق من PIN المالك على السيرفر (دالة الحافة owner-pin-verify).
enum OwnerPinVerdict {
  ok,
  wrong,
  locked,
  noSecret,

  /// الدالة غير منشورة أو أخطأت — ليس حكماً على الرمز.
  unavailable,

  /// لا شبكة أو انتهت المهلة.
  network,
}

class OwnerPinVerifyResult {
  const OwnerPinVerifyResult(
    this.verdict, {
    this.phone = '',
    this.remaining,
    this.lockedUntil,
  });

  final OwnerPinVerdict verdict;
  final String phone;
  final int? remaining;
  final DateTime? lockedUntil;

  bool get isOk => verdict == OwnerPinVerdict.ok;

  /// هل قال السيرفر كلمته في الرمز؟ (فلا داعي لتجربة طريق آخر بالرمز نفسه.)
  bool get isDefinitive =>
      verdict == OwnerPinVerdict.ok ||
      verdict == OwnerPinVerdict.wrong ||
      verdict == OwnerPinVerdict.locked;

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// يحوّل رد الدالة (أو تفاصيل الخطأ) إلى نتيجة.
  static OwnerPinVerifyResult fromBody(Object? raw, {int? status}) {
    final m = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    if (m['ok'] == true) {
      return OwnerPinVerifyResult(
        OwnerPinVerdict.ok,
        phone: (m['phone'] ?? '').toString().trim(),
      );
    }
    switch (m['reason']) {
      case 'wrong_pin':
        return OwnerPinVerifyResult(
          OwnerPinVerdict.wrong,
          remaining: (m['remaining'] as num?)?.toInt(),
          lockedUntil: _date(m['locked_until']),
        );
      case 'locked':
        return OwnerPinVerifyResult(
          OwnerPinVerdict.locked,
          lockedUntil: _date(m['locked_until']),
        );
      case 'no_secret':
        return const OwnerPinVerifyResult(OwnerPinVerdict.noSecret);
      case 'bad_pin':
        return const OwnerPinVerifyResult(OwnerPinVerdict.wrong);
    }
    if (status == 429) return const OwnerPinVerifyResult(OwnerPinVerdict.locked);
    return const OwnerPinVerifyResult(OwnerPinVerdict.unavailable);
  }
}

/// رفع/سحب [OwnerAuthCloudSecret] عبر RPC (migration 20260609).
class OwnerAuthCloudService {
  OwnerAuthCloudService._();
  static final OwnerAuthCloudService instance = OwnerAuthCloudService._();

  Future<void> upsert({
    required String phone,
    required String pinHash,
    required String pinSalt,
  }) async {
    await Supabase.instance.client.rpc(
      'app_upsert_owner_auth_secret',
      params: {
        'p_phone': phone.trim(),
        'p_pin_hash': pinHash.trim(),
        'p_pin_salt': pinSalt.trim(),
      },
    );
  }

  /// يتحقق من PIN على السيرفر دون أن يصل الـ hash إلى الجهاز.
  /// خمس محاولات خاطئة تقفل الحساب مؤقتاً (يتضاعف القفل حتى 12 ساعة).
  Future<OwnerPinVerifyResult> verifyPin(
    String pin, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final res = await Supabase.instance.client.functions
          .invoke('owner-pin-verify', body: {'pin': pin.trim()})
          .timeout(timeout);
      return OwnerPinVerifyResult.fromBody(res.data, status: res.status);
    } on FunctionException catch (e) {
      if (e.status == 404) {
        AppLogger.warn('OwnerAuthCloudService', 'owner-pin-verify not deployed');
        return const OwnerPinVerifyResult(OwnerPinVerdict.unavailable);
      }
      return OwnerPinVerifyResult.fromBody(e.details, status: e.status);
    } on TimeoutException {
      return const OwnerPinVerifyResult(OwnerPinVerdict.network);
    } catch (e) {
      AppLogger.warn('OwnerAuthCloudService', 'verifyPin: $e');
      final s = e.toString().toLowerCase();
      final net = s.contains('socket') ||
          s.contains('host lookup') ||
          s.contains('connection') ||
          s.contains('network');
      return OwnerPinVerifyResult(
        net ? OwnerPinVerdict.network : OwnerPinVerdict.unavailable,
      );
    }
  }

  Future<OwnerAuthCloudSecret?> fetch({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final raw = await Supabase.instance.client
          .rpc('app_get_owner_auth_secret')
          .timeout(timeout);
      if (raw == null) return null;
      if (raw is! Map) return null;
      final secret = OwnerAuthCloudSecret.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      return secret.isComplete ? secret : null;
    } on PostgrestException catch (e) {
      final msg = e.message.toUpperCase();
      if (msg.contains('APP_GET_OWNER_AUTH_SECRET') &&
          (msg.contains('COULD NOT FIND') || msg.contains('FUNCTION'))) {
        AppLogger.warn(
          'OwnerAuthCloudService',
          'app_get_owner_auth_secret RPC missing — run migration 20260609',
        );
        return null;
      }
      rethrow;
    } on TimeoutException {
      AppLogger.warn('OwnerAuthCloudService', 'fetch timed out');
      return null;
    }
  }
}
