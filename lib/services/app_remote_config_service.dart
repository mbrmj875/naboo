import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// إعدادات من جدول [app_remote_config] (صف واحد id=1).
/// تُقرأ بدون تسجيل دخول (سياسة RLS للجميع SELECT).
class AppRemoteConfigData {
  const AppRemoteConfigData({
    required this.maintenanceMode,
    required this.maintenanceMessageAr,
    required this.syncPausedGlobally,
    required this.syncPausedMessageAr,
    required this.minSupportedVersion,
    required this.latestVersion,
    required this.updateMessageAr,
    required this.forceUpdate,
    required this.updateDownloadUrl,
    required this.announcementTitleAr,
    required this.announcementBodyAr,
    required this.announcementUrl,
  });

  final bool maintenanceMode;
  final String maintenanceMessageAr;
  final bool syncPausedGlobally;
  final String syncPausedMessageAr;
  final String minSupportedVersion;
  final String latestVersion;
  final String updateMessageAr;
  final bool forceUpdate;
  final String updateDownloadUrl;
  /// إعلان عام (أي مناسبة) — يُعرض عند تغيير النص/العنوان/الرابط.
  final String announcementTitleAr;
  final String announcementBodyAr;
  final String announcementUrl;

  static const AppRemoteConfigData fallback = AppRemoteConfigData(
    maintenanceMode: false,
    maintenanceMessageAr: '',
    syncPausedGlobally: false,
    syncPausedMessageAr: 'المزامنة موقوفة مؤقتاً من الخادم.',
    minSupportedVersion: '0.0.0',
    latestVersion: '0.0.0',
    updateMessageAr: '',
    forceUpdate: false,
    updateDownloadUrl: '',
    announcementTitleAr: '',
    announcementBodyAr: '',
    announcementUrl: '',
  );

  /// بصمة المحتوى: عند تغييرك للنص في اللوحة تتغير تلقائياً فيظهر الإعلان من جديد.
  String get announcementContentDigest {
    if (announcementBodyAr.isEmpty) return '';
    final payload =
        '${announcementTitleAr.trim()}\n${announcementBodyAr.trim()}\n${announcementUrl.trim()}';
    return md5.convert(utf8.encode(payload)).toString();
  }

  static AppRemoteConfigData fromJson(Map<String, dynamic> j) {
    bool b(String k) => j[k] == true;
    String s(String k) => (j[k] ?? '').toString().trim();
    return AppRemoteConfigData(
      maintenanceMode: b('maintenance_mode'),
      maintenanceMessageAr: s('maintenance_message_ar'),
      syncPausedGlobally: b('sync_paused_globally'),
      syncPausedMessageAr: s('sync_paused_message_ar').isEmpty
          ? fallback.syncPausedMessageAr
          : s('sync_paused_message_ar'),
      minSupportedVersion: s('min_supported_version').isEmpty
          ? '0.0.0'
          : s('min_supported_version'),
      latestVersion:
          s('latest_version').isEmpty ? '0.0.0' : s('latest_version'),
      updateMessageAr: s('update_message_ar'),
      forceUpdate: b('force_update'),
      updateDownloadUrl: s('update_download_url'),
      announcementTitleAr: s('announcement_title_ar'),
      announcementBodyAr: s('announcement_body_ar'),
      announcementUrl: s('announcement_url'),
    );
  }
}

class AppRemoteConfigService {
  AppRemoteConfigService._();
  static final AppRemoteConfigService instance = AppRemoteConfigService._();

  AppRemoteConfigData _cached = AppRemoteConfigData.fallback;
  DateTime? _lastFetch;

  AppRemoteConfigData get current => _cached;

  /// مقارنة إصدارات بسيطة major.minor.patch (أرقام فقط).
  static int compareVersions(String a, String b) {
    List<int> parts(String v) {
      return v
          .split('.')
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .toList();
    }

    final pa = parts(a);
    final pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// يجلب الإعدادات ويخزّن نسخة في الذاكرة.
  /// [force] يتجاهل التخزين المؤقت القصير.
  Future<AppRemoteConfigData> refresh({bool force = false}) async {
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 2)) {
      return _cached;
    }

    try {
      final row = await Supabase.instance.client
          .from('app_remote_config')
          .select('config')
          .eq('id', 1)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (row == null || row['config'] == null) {
        _cached = AppRemoteConfigData.fallback;
      } else {
        final raw = row['config'];
        if (raw is Map<String, dynamic>) {
          _cached = AppRemoteConfigData.fromJson(raw);
        } else {
          _cached = AppRemoteConfigData.fallback;
        }
      }
    } catch (_) {
      // بدون شبكة أو الجدول غير منشأ: لا نكسر التطبيق.
      _cached = AppRemoteConfigData.fallback;
    }

    _lastFetch = DateTime.now();
    return _cached;
  }
}
