import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

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
    required this.updateDownloadUrlWindows,
    required this.announcementTitleAr,
    required this.announcementBodyAr,
    required this.announcementUrl,
    this.oilShellDisabled = false,
    this.assistant = AssistantRemoteFlags.off,
  });

  final bool maintenanceMode;
  final String maintenanceMessageAr;
  final bool syncPausedGlobally;
  final String syncPausedMessageAr;
  final String minSupportedVersion;
  final String latestVersion;
  final String updateMessageAr;
  final bool forceUpdate;

  /// رابط APK للأندرويد (والافتراضي إن لم يُحدَّد ويندوز).
  final String updateDownloadUrl;

  /// رابط مُثبّت ويندوز (.exe) — إن وُجد يُستخدم على الحاسوب فقط.
  final String updateDownloadUrlWindows;

  /// إعلان عام (أي مناسبة) — يُعرض عند تغيير النص/العنوان/الرابط.
  final String announcementTitleAr;
  final String announcementBodyAr;
  final String announcementUrl;

  /// مفتاح رجوع: يعيد موظف الزيت إلى الرئيسية المشتركة عند أول تشغيل متصل.
  final bool oilShellDisabled;

  /// مفاتيح مساعد نابو الجديد (مفتاح الإيقاف ومفاتيح القدرات).
  final AssistantRemoteFlags assistant;

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
    updateDownloadUrlWindows: '',
    announcementTitleAr: '',
    announcementBodyAr: '',
    announcementUrl: '',
  );

  /// رابط التحميل المناسب للمنصة الحالية.
  /// ويندوز لا يسقط إلى APK الأندرويد إذا غاب رابط الـ setup.
  String downloadUrlForPlatform({required bool isWindows}) {
    if (isWindows) return updateDownloadUrlWindows;
    return updateDownloadUrl;
  }

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
      latestVersion: s('latest_version').isEmpty
          ? '0.0.0'
          : s('latest_version'),
      updateMessageAr: s('update_message_ar'),
      forceUpdate: b('force_update'),
      updateDownloadUrl: s('update_download_url'),
      updateDownloadUrlWindows: s('update_download_url_windows'),
      announcementTitleAr: s('announcement_title_ar'),
      announcementBodyAr: s('announcement_body_ar'),
      announcementUrl: s('announcement_url'),
      oilShellDisabled: b('oil_shell_disabled'),
      assistant: AssistantRemoteFlags.fromJson(j['assistant']),
    );
  }
}

/// `config.assistant` في [app_remote_config] — خطة المساعد، القسم 7.
///
/// - [kill]: يعيد كل المحلات إلى المساعد القديم خلال دقائق بلا تحديث.
/// - [rollout]: `off` لا أحد، `tenants` المحلات المفعّلة في
///   `assistant_tenant_settings` فقط، `all` الجميع.
/// - مفتاح لكل قدرة يُطفئها وحدها.
class AssistantRemoteFlags {
  const AssistantRemoteFlags({
    required this.kill,
    required this.rollout,
    required this.executeEnabled,
    required this.webEnabled,
    required this.imagesEnabled,
    required this.whatsappResponderEnabled,
    this.videos = const {},
  });

  final bool kill;

  /// روابط فيديو الشرح لكل شاشة (م3-15)، يديرها المالك من لوحة الإدارة.
  /// المفتاح معرّف المسار، والقيمة رابط https فقط.
  final Map<String, String> videos;
  final String rollout;
  final bool executeEnabled;
  final bool webEnabled;
  final bool imagesEnabled;
  final bool whatsappResponderEnabled;

  /// بلا إعداد من الخادم: الجديد مطفأ، والقدرات مسموحة إن فُعّل لاحقاً.
  static const AssistantRemoteFlags off = AssistantRemoteFlags(
    kill: false,
    rollout: 'off',
    executeEnabled: true,
    webEnabled: true,
    imagesEnabled: true,
    whatsappResponderEnabled: true,
  );

  static AssistantRemoteFlags fromJson(Object? raw) {
    if (raw is! Map) return off;
    final caps = raw['caps'] is Map ? raw['caps'] as Map : const {};
    bool cap(String k) => caps[k] != false;
    final rollout = (raw['v2_rollout'] ?? 'off').toString().trim();
    return AssistantRemoteFlags(
      kill: raw['kill'] == true,
      rollout: const {'off', 'tenants', 'all'}.contains(rollout)
          ? rollout
          : 'off',
      executeEnabled: cap('execute'),
      webEnabled: cap('web'),
      imagesEnabled: cap('images'),
      whatsappResponderEnabled: cap('whatsapp_responder'),
      videos: _videos(raw['videos']),
    );
  }

  static Map<String, String> _videos(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      final url = (v ?? '').toString().trim();
      final uri = Uri.tryParse(url);
      if (k is String && k.startsWith('app_') && uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
        out[k] = url;
      }
    });
    return out;
  }

  /// هل الجديد مفعّل لهذا المحل؟ [tenantEnabled] من `assistant_tenant_settings`.
  bool v2EnabledFor({required bool tenantEnabled}) {
    if (kill) return false;
    return switch (rollout) {
      'all' => true,
      'tenants' => tenantEnabled,
      _ => false,
    };
  }
}

class AppRemoteConfigService {
  AppRemoteConfigService._();
  static final AppRemoteConfigService instance = AppRemoteConfigService._();

  AppRemoteConfigData _cached = AppRemoteConfigData.fallback;
  DateTime? _lastFetch;

  AppRemoteConfigData get current => _cached;

  /// تطبيع رقم الإصدار: يتجاهل لاحقة البناء (`2.2.27+250` → `2.2.27`)
  /// وأي بادئة غير رقمية.
  static String normalizeVersion(String raw) {
    var v = raw.trim();
    final plus = v.indexOf('+');
    if (plus >= 0) v = v.substring(0, plus);
    final dash = v.indexOf('-');
    if (dash >= 0) v = v.substring(0, dash);
    return v.trim();
  }

  /// مقارنة إصدارات بسيطة major.minor.patch (أرقام فقط).
  /// تُرجع سالباً إذا [a] < [b]، وصفر إذا تساويا، وموجباً إذا [a] > [b].
  static int compareVersions(String a, String b) {
    List<int> parts(String v) {
      return normalizeVersion(
        v,
      ).split('.').map((e) => int.tryParse(e.trim()) ?? 0).toList();
    }

    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// هل نسخة الجهاز أقل من [latestVersion] على السيرفر؟
  /// إذا كان [latestVersion] فارغاً أو `0.0.0` (fallback) لا يُطلب تحديث.
  static bool isUpdateAvailable({
    required String installedVersion,
    required String latestVersion,
  }) {
    final latest = normalizeVersion(latestVersion);
    if (latest.isEmpty || latest == '0.0.0') return false;
    return compareVersions(installedVersion, latest) < 0;
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
    } catch (e, st) {
      AppLogger.error(
        'RemoteConfig',
        'تعذّر جلب الإعدادات السحابية — استخدام fallback',
        e,
        st,
      );
      _cached = AppRemoteConfigData.fallback;
    }

    _lastFetch = DateTime.now();
    return _cached;
  }
}
