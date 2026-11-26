import 'dart:async' show unawaited;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../firebase_options.dart';
import '../../navigation/app_root_navigator_key.dart';
import '../../notifications/push_channels.dart';
import '../../notifications/push_device_registry.dart';
import '../../notifications/push_router.dart';
import '../../providers/auth_provider.dart';
import '../../services/system_notification_service.dart';
import '../../services/tenant_context_service.dart';
import '../../utils/app_logger.dart';
import '../models/owner_push_payload.dart';
import 'owner_alert_cloud_sync_service.dart';
import 'owner_push_action_registry.dart';
import 'owner_push_notification_router.dart';

/// معالج FCM في الخلفية — يعرض شريط النظام عند غياب حمولة notification من الخادم.
@pragma('vm:entry-point')
Future<void> ownerFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // عندما يرسل الخادم حقل notification يعرضه النظام تلقائياً.
  // هنا نغطي data-only حتى لا تضيع الرسالة والقفل/السكون.
  if (message.notification != null) return;

  final title = (message.data[OwnerPushPayload.dataTitleAr] ??
          message.data['title'] ??
          'نابو')
      .toString()
      .trim();
  final body = (message.data[OwnerPushPayload.dataBodyAr] ??
          message.data['body'] ??
          '')
      .toString()
      .trim();
  if (title.isEmpty && body.isEmpty) return;

  try {
    await SystemNotificationService.instance.initialize();
    final alertId =
        (message.data[OwnerPushPayload.dataAlertId] ?? 'owner_push').toString();
    await SystemNotificationService.instance.show(
      id: 'fcm_$alertId',
      title: title.isEmpty ? 'نابو' : title,
      body: body.isEmpty ? title : body,
      summaryText: 'تنبيه المالك',
    );
  } catch (e, st) {
    AppLogger.error('OwnerFcm', 'فشل عرض إشعار الخلفية', e, st);
  }
}

/// استقبال FCM وتوجيه المالك — بدون حساب تنبيهات محلي.
class OwnerFcmListenerService {
  OwnerFcmListenerService._();
  static final OwnerFcmListenerService instance = OwnerFcmListenerService._();

  bool _initialized = false;
  bool _firebaseReady = false;
  RemoteMessage? _pendingMessage;

  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> initialize() async {
    if (!_isMobile || _initialized) return;
    _initialized = true;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _firebaseReady = true;

      FirebaseMessaging.onBackgroundMessage(ownerFcmBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      // لا نطلب الإذن عند فتح التطبيق: يُطلب بعد شرح الفائدة (OwnerPhonePrompt).
      // العرض في المقدمة يتم يدوياً عبر SystemNotificationService.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

      // رمز جديد: يُسجَّل لكل الأدوار في push_devices (النظام الموحد).
      messaging.onTokenRefresh.listen((_) => unawaited(PushDeviceRegistry.instance.syncNow()));

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedFromNotification);

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _pendingMessage = initial;
      }
    } catch (e, st) {
      AppLogger.error('OwnerFcm', 'فشل تهيئة FCM للمالك', e, st);
    }
  }

  /// بعد جاهزية Navigator + جلسة المالك.
  void flushPendingIfReady() {
    if (_pendingMessage == null) return;
    final before = _pendingMessage;
    _routeMessage(before!);
    if (_pendingMessage == before) return;
  }

  Future<void> _registerToken() async {
    if (!_firebaseReady) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    await PushDeviceRegistry.instance.syncNow();
  }

  void _onForegroundMessage(RemoteMessage message) {
    unawaited(_showTrayFromMessage(message));
    // إشعار النظام الموحد لا يفتح شاشة وحده وهو في المقدمة: يفتحها الضغط عليه.
    if (PushRouter.isUnifiedPayload(message.data)) return;
    _routeMessage(message);
  }

  void _onOpenedFromNotification(RemoteMessage message) {
    _routeMessage(message);
  }

  Future<void> _showTrayFromMessage(RemoteMessage message) async {
    final n = message.notification;
    final title = (n?.title ??
            message.data[OwnerPushPayload.dataTitleAr] ??
            message.data['title'] ??
            '')
        .toString()
        .trim();
    final body = (n?.body ??
            message.data[OwnerPushPayload.dataBodyAr] ??
            message.data['body'] ??
            '')
        .toString()
        .trim();
    if (title.isEmpty && body.isEmpty) return;

    final data = message.data;
    if (PushRouter.isUnifiedPayload(data)) {
      await SystemNotificationService.instance.show(
        id: 'n${data['notification_id']}',
        title: title.isEmpty ? 'نابو' : title,
        body: body.isEmpty ? title : body,
        channel: PushChannels.forCategory(
          '${data['category'] ?? ''}',
          '${data['priority'] ?? 'normal'}',
        ),
        payload: PushRouter.encodeForLocal(data),
      );
      return;
    }
    final alertId =
        (data[OwnerPushPayload.dataAlertId] ?? 'owner_push').toString();
    await SystemNotificationService.instance.show(
      id: 'fcm_fg_$alertId',
      title: title.isEmpty ? 'نابو' : title,
      body: body.isEmpty ? title : body,
      summaryText: 'تنبيه المالك',
    );
  }

  void _routeMessage(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;
    if (PushRouter.isUnifiedPayload(data)) {
      if (_pendingMessage == message) _pendingMessage = null;
      PushRouter.instance.handleData(Map<String, dynamic>.from(data));
      return;
    }

    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      _pendingMessage = message;
      return;
    }

    final auth = Provider.of<AuthProvider>(ctx, listen: false);
    if (!auth.isLoggedIn || !auth.isOwner) return;

    final payload = OwnerPushPayload.fromFcmData(data);
    if (!payload.isValid) return;

    final activeTenant = TenantContextService.instance.activeTenantId;
    if (payload.tenantId != activeTenant) return;

    _pendingMessage = null;

    OwnerPushNotificationRouter.handleFcmData(
      ctx,
      data,
      onPurchasePdf: OwnerPushActionRegistry.purchasePdf,
      onDebtReminders: OwnerPushActionRegistry.debtReminders,
    );
  }

  /// يُستدعى بعد تسجيل دخول المالك — تسجيل التوكن + مزامنة التفضيلات.
  void refreshTokenRegistration() {
    if (!_firebaseReady) return;
    unawaited(_registerToken());
    // يضمن رفع push_alert_ids الافتراضية الحرجة حتى لو لم يفتح Studio.
    OwnerAlertCloudSyncService.scheduleResyncActiveTenantPreferences();
    flushPendingIfReady();
  }
}
