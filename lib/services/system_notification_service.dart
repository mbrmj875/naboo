import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../notifications/push_channels.dart';
import '../utils/app_logger.dart';

/// إشعارات في **شريط إشعارات النظام** (Android / iOS) — ليست فقط داخل التطبيق.
class SystemNotificationService {
  SystemNotificationService._();
  static final SystemNotificationService instance = SystemNotificationService._();

  static const _channelId = 'naboo_alerts';
  static const _channelName = 'تنبيهات نابو';
  static const _channelDesc =
      'مخزون، أقساط، مرتجعات، صندوق، وغيرها — تظهر في شريط الإشعارات.';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// يُضبط من [PushRouter]: الضغط على إشعار في الشريط يفتح شاشته.
  static void Function(String? payload)? onTapPayload;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize() async {
    if ((!_isAndroid && !_isIos) || _initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
      // الإذن لا يُطلب عند فتح التطبيق، بل بعد شاشة تشرح الفائدة
      // (خطة الإشعارات، خامسا البند 6): [requestPermission].
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const init = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );
      await _plugin.initialize(
        init,
        onDidReceiveNotificationResponse: _onTap,
      );

      if (_isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (android != null) {
          await android.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: _channelDesc,
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
              showBadge: true,
            ),
          );
          for (final c in PushChannels.all) {
            await android.createNotificationChannel(c.toAndroid());
          }
        }
      }
      _initialized = true;
    } catch (e, st) {
      AppLogger.error('Notify', 'فشل تهيئة خدمة إشعارات النظام', e, st);
    }
  }

  void _onTap(NotificationResponse response) {
    onTapPayload?.call(response.payload);
  }

  /// إشعار محلي فُتح منه التطبيق وهو مغلق.
  Future<String?> launchPayload() async {
    if (!_initialized) return null;
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) {
        return d!.notificationResponse?.payload;
      }
    } catch (_) {}
    return null;
  }

  /// هل الإشعارات مسموحة لهذا التطبيق؟ null على المنصات الأخرى.
  Future<bool?> areNotificationsEnabled() async {
    if (!_initialized) return null;
    try {
      if (_isAndroid) {
        return await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled();
      }
      if (_isIos) {
        final o = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.checkPermissions();
        return o?.isEnabled;
      }
    } catch (_) {}
    return null;
  }

  /// يطلب إذن الإشعارات (بعد شاشة الشرح فقط).
  Future<bool> requestPermission() async {
    if (!_initialized) await initialize();
    try {
      if (_isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (_isIos) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (e, st) {
      AppLogger.error('Notify', 'فشل طلب إذن الإشعارات', e, st);
    }
    return false;
  }

  /// هل تجدول هذه المنصة إشعاراً لوقت لاحق والتطبيق مغلق؟
  bool get canSchedule => _initialized && (_isAndroid || _isIos);

  /// إشعار في وقت محدد (تذكيرات المساعد). false إن لم تدعمه المنصة، فيستعمل
  /// المستدعي مؤقتاً داخل التطبيق. الوضع غير الدقيق لا يحتاج صلاحية المنبّه.
  Future<bool> scheduleAt({
    required String id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!canSchedule) return false;
    try {
      final nid = id.hashCode & 0x7FFFFFFF;
      await _plugin.zonedSchedule(
        nid,
        title,
        body,
        tz.TZDateTime.from(when.toUtc(), tz.UTC),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body, contentTitle: title),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: id,
      );
      return true;
    } catch (e, st) {
      AppLogger.error('Notify', 'فشل جدولة إشعار', e, st);
      return false;
    }
  }

  Future<void> cancelScheduled(String id) async {
    if (!canSchedule) return;
    try {
      await _plugin.cancel(id.hashCode & 0x7FFFFFFF);
    } catch (_) {}
  }

  /// يعرض إشعاراً واحداً في شريط النظام (Android / iOS).
  Future<void> show({
    required String id,
    required String title,
    required String body,
    String summaryText = 'نابو',
    PushChannel? channel,
    String? payload,
  }) async {
    if (!_initialized || kIsWeb) return;
    try {
      final nid = id.hashCode & 0x7FFFFFFF;
      if (_isAndroid) {
        final ch = channel;
        final android = AndroidNotificationDetails(
          ch?.id ?? _channelId,
          ch?.name ?? _channelName,
          channelDescription: ch?.description ?? _channelDesc,
          importance: ch?.importance ?? Importance.high,
          priority: (ch?.importance.value ?? Importance.high.value) >=
                  Importance.high.value
              ? Priority.high
              : Priority.defaultPriority,
          sound: (ch?.customSound ?? false)
              ? const RawResourceAndroidNotificationSound('naboo_alert')
              : null,
          ticker: title,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: summaryText,
          ),
        );
        await _plugin.show(
          nid,
          title,
          body,
          NotificationDetails(android: android),
          payload: payload ?? id,
        );
      } else if (_isIos) {
        final ios = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          subtitle: summaryText,
        );
        await _plugin.show(
          nid,
          title,
          body,
          NotificationDetails(iOS: ios),
          payload: payload ?? id,
        );
      }
    } catch (e, st) {
      AppLogger.error('Notify', 'فشل عرض إشعار النظام', e, st);
    }
  }
}
