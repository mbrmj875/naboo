import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> initialize() async {
    if ((!_isAndroid && !_isIos) || _initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
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
          await android.requestNotificationsPermission();
        }
      } else if (_isIos) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
      _initialized = true;
    } catch (e, st) {
      debugPrint('SystemNotificationService.initialize: $e\n$st');
    }
  }

  void _onTap(NotificationResponse response) {
    // يمكن لاحقاً فتح شاشة الإشعارات عبر payload
  }

  /// يعرض إشعاراً واحداً في شريط النظام (Android / iOS).
  Future<void> show({
    required String id,
    required String title,
    required String body,
    String summaryText = 'نابو',
  }) async {
    if (!_initialized || kIsWeb) return;
    try {
      final nid = id.hashCode & 0x7FFFFFFF;
      if (_isAndroid) {
        final android = AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
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
          payload: id,
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
          payload: id,
        );
      }
    } catch (e, st) {
      debugPrint('SystemNotificationService.show: $e\n$st');
    }
  }
}
