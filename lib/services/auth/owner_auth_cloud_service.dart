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
  });

  final String phone;
  final String pinHash;
  final String pinSalt;

  bool get isComplete =>
      AuthValidators.isValidIraqiPhone(phone) &&
      pinHash.trim().isNotEmpty &&
      pinSalt.trim().isNotEmpty;

  factory OwnerAuthCloudSecret.fromJson(Map<String, dynamic> json) {
    return OwnerAuthCloudSecret(
      phone: (json['phone'] ?? '').toString().trim(),
      pinHash: (json['pin_hash'] ?? json['pinHash'] ?? '').toString().trim(),
      pinSalt: (json['pin_salt'] ?? json['pinSalt'] ?? '').toString().trim(),
    );
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
