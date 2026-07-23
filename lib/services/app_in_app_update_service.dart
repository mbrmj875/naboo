import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';

/// تنزيل APK وتثبيته على Android ثم إعادة فتح التطبيق بعد النجاح.
class AppInAppUpdateService {
  AppInAppUpdateService._();
  static final AppInAppUpdateService instance = AppInAppUpdateService._();

  static const _channel = MethodChannel('com.basra.storemanager/apk_installer');

  /// رابط احتياطي لآخر APK منشور على GitHub.
  static const fallbackApkUrl =
      'https://github.com/mbrmj875/naboo/releases/latest/download/naboo.apk';

  bool get isAndroidInAppUpdateSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> canRequestPackageInstalls() async {
    if (!isAndroidInAppUpdateSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('canRequestPackageInstalls');
      return ok == true;
    } catch (e, st) {
      AppLogger.error('InAppUpdate', 'canRequestPackageInstalls', e, st);
      return false;
    }
  }

  Future<void> openUnknownSourcesSettings() async {
    if (!isAndroidInAppUpdateSupported) return;
    await _channel.invokeMethod<void>('openUnknownSourcesSettings');
  }

  /// ينزّل الملف مع تقدّم، ثم يطلب التثبيت الأصلي.
  Future<void> downloadAndInstall({
    required String downloadUrl,
    void Function(double progress)? onProgress,
    void Function(String statusAr)? onStatus,
  }) async {
    if (!isAndroidInAppUpdateSupported) {
      throw StateError('التحديث من داخل التطبيق متاح على أندرويد فقط.');
    }

    final url = downloadUrl.trim().isEmpty ? fallbackApkUrl : downloadUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      throw StateError('رابط التحديث غير صالح.');
    }

    onStatus?.call('جاري تنزيل التحديث…');
    onProgress?.call(0);

    final dir = await getTemporaryDirectory();
    final updatesDir = Directory(p.join(dir.path, 'updates'));
    if (!await updatesDir.exists()) {
      await updatesDir.create(recursive: true);
    }
    final outFile = File(p.join(updatesDir.path, 'naboo-update.apk'));
    if (await outFile.exists()) {
      await outFile.delete();
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      request.headers['Accept'] = '*/*';
      final response = await client.send(request).timeout(
            const Duration(minutes: 8),
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('تعذر تنزيل التحديث (رمز ${response.statusCode}).');
      }

      final contentType = (response.headers['content-type'] ?? '').toLowerCase();
      if (contentType.contains('text/html')) {
        throw StateError(
          'رابط التحديث يفتح صفحة ويب وليس ملف APK. ضع رابط الملف المباشر.',
        );
      }

      final total = response.contentLength ?? 0;
      final sink = outFile.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        } else if (received > 0) {
          // تقدّم تقريبي عند غياب Content-Length.
          onProgress?.call((received / (received + 5 * 1024 * 1024)).clamp(0.0, 0.95));
        }
      }
      await sink.flush();
      await sink.close();

      if (await outFile.length() < 1024) {
        throw StateError('ملف التحديث ناقص أو تالف.');
      }

      // تحقق سريع أن الملف أرشيف ZIP (صيغة APK).
      final raf = await outFile.open();
      try {
        final header = await raf.read(4);
        final isZip = header.length >= 2 &&
            header[0] == 0x50 &&
            header[1] == 0x4B;
        if (!isZip) {
          throw StateError('الملف المُنزَّل ليس حزمة تثبيت صالحة.');
        }
      } finally {
        await raf.close();
      }

      onProgress?.call(1);
      onStatus?.call('جاري التثبيت… أكّد التثبيت إن طلب النظام');

      final allowed = await canRequestPackageInstalls();
      if (!allowed) {
        await openUnknownSourcesSettings();
        throw StateError(
          'فعّل «السماح من هذا المصدر» ثم اضغط تحديث مرة أخرى.',
        );
      }

      await _channel.invokeMethod<void>('installApk', {
        'path': outFile.path,
      });
      onStatus?.call('اكتمل الطلب — سيُعاد فتح التطبيق بعد التثبيت');
    } finally {
      client.close();
    }
  }
}
