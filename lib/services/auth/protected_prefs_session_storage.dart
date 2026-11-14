import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show LocalStorage;

import 'windows_dpapi_stub.dart' if (dart.library.io) 'windows_dpapi_io.dart'
    as dpapi;

/// تشفير وفك نص الجلسة. منفصل ليُختبر المنطق دون ويندوز.
abstract class SessionCipher {
  bool get available;
  Future<String> protect(String plain);
  Future<String> unprotect(String sealed);
}

/// DPAPI لحساب المستخدم الحالي في ويندوز، في عزلة خلفية.
class WindowsDpapiCipher implements SessionCipher {
  const WindowsDpapiCipher();

  @override
  bool get available => dpapi.dpapiAvailable;

  @override
  Future<String> protect(String plain) async => base64Encode(
        await dpapi.dpapiProtect(Uint8List.fromList(utf8.encode(plain))),
      );

  @override
  Future<String> unprotect(String sealed) async =>
      utf8.decode(await dpapi.dpapiUnprotect(base64Decode(sealed)));
}

/// جلسة ويندوز مشفرة في SharedPreferences (البند 5.3).
///
/// كانت الجلسة نصاً عادياً لأن مكتبة التخزين الآمن تعمل على خيط النافذة،
/// وعلّقت الإقلاع. هنا يجري التشفير في عزلة خلفية بمهلة، فلا تتجمد النافذة.
/// إن فشل التشفير أو تأخر تُحفظ الجلسة كما كانت (نص عادي)، فلا يخرج
/// المستخدم من حسابه بسبب التشفير أبداً.
class ProtectedPrefsLocalStorage extends LocalStorage {
  ProtectedPrefsLocalStorage({
    required this.persistSessionKey,
    SessionCipher? cipher,
    Duration? timeout,
  })  : _cipher = cipher ?? const WindowsDpapiCipher(),
        _timeout = timeout ?? const Duration(seconds: 3);

  final String persistSessionKey;
  final SessionCipher _cipher;
  final Duration _timeout;

  String get protectedKey => '$persistSessionKey.dpapi';

  Future<String?> _seal(String plain) async {
    if (!_cipher.available) return null;
    try {
      final sealed = await _cipher.protect(plain).timeout(_timeout);
      // لا نعتمد نسخة مشفرة لا تُفك.
      final back = await _cipher.unprotect(sealed).timeout(_timeout);
      return back == plain ? sealed : null;
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[ProtectedPrefs] seal failed: $e');
      return null;
    }
  }

  Future<String?> _open(String sealed) async {
    for (final wait in [_timeout, _timeout * 2]) {
      try {
        return await _cipher.unprotect(sealed).timeout(wait);
      } on TimeoutException {
        continue;
      } on Object catch (e) {
        if (kDebugMode) debugPrint('[ProtectedPrefs] open failed: $e');
        return null;
      }
    }
    return null;
  }

  /// ينقل جلسة نصية قديمة إلى المشفرة. لا يحذف النص إلا بعد التحقق.
  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final plain = prefs.getString(persistSessionKey);
      if (plain == null || plain.isEmpty) return;
      final sealed = await _seal(plain);
      if (sealed == null) return;
      await prefs.setString(protectedKey, sealed);
      await prefs.remove(persistSessionKey);
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[ProtectedPrefs] migrate failed: $e');
    }
  }

  @override
  Future<bool> hasAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(protectedKey) ||
        prefs.containsKey(persistSessionKey);
  }

  @override
  Future<String?> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final sealed = prefs.getString(protectedKey);
    if (sealed != null && sealed.isNotEmpty) {
      final opened = await _open(sealed);
      if (opened != null) return opened;
    }
    return prefs.getString(persistSessionKey);
  }

  @override
  Future<void> removePersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(protectedKey);
    await prefs.remove(persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    final prefs = await SharedPreferences.getInstance();
    final sealed = await _seal(persistSessionString);
    if (sealed != null) {
      await prefs.setString(protectedKey, sealed);
      await prefs.remove(persistSessionKey);
      return;
    }
    // التشفير غير متاح الآن: الجلسة الأحدث نصاً، وتُحذف المشفرة الأقدم
    // كي لا تُقرأ بدلها.
    await prefs.setString(persistSessionKey, persistSessionString);
    await prefs.remove(protectedKey);
  }
}
