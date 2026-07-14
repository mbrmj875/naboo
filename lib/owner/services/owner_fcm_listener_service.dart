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
import '../../providers/auth_provider.dart';
import '../../services/tenant_context_service.dart';
import '../../utils/app_logger.dart';
import '../models/owner_push_payload.dart';
import 'owner_alert_cloud_sync_service.dart';
import 'owner_push_action_registry.dart';
import 'owner_push_notification_router.dart';

/// معالج FCM في الخلفية — data-only؛ العرض في شريط النظام من الخادم.
@pragma('vm:entry-point')
Future<void> ownerFcmBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );

      messaging.onTokenRefresh.listen(_registerTokenIfOwner);

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

  /// بعد جاهزية Navigator + جلسة المالk.
  void flushPendingIfReady() {
    if (_pendingMessage == null) return;
    final before = _pendingMessage;
    _routeMessage(before!);
    if (_pendingMessage == before) return;
  }

  Future<void> _registerTokenIfOwner(String token) async {
    if (!_firebaseReady) return;
    if (Supabase.instance.client.auth.currentUser == null) return;

    final ctx = appRootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted) {
      final auth = Provider.of<AuthProvider>(ctx, listen: false);
      if (!auth.isOwner) return;
    }

    final tenantId = TenantContextService.instance.activeTenantId;
    await OwnerAlertCloudSyncService.registerFcmToken(
      localTenantId: tenantId,
      token: token,
    );
  }

  void _onForegroundMessage(RemoteMessage message) {
    _routeMessage(message);
  }

  void _onOpenedFromNotification(RemoteMessage message) {
    _routeMessage(message);
  }

  void _routeMessage(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;

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

  /// يُستدعى بعد تسجيل دخول المالk — تسجيل التوken + مزامنة التفضيلات.
  void refreshTokenRegistration() {
    if (!_firebaseReady) return;
    unawaited(FirebaseMessaging.instance.getToken().then((token) {
      if (token != null) _registerTokenIfOwner(token);
    }));
    flushPendingIfReady();
  }
}
