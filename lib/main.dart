import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'dart:ui' show PlatformDispatcher;
import 'utils/debug_ndjson_logger.dart';
import 'storage/sqlite_desktop_init.dart'
    if (dart.library.html) 'storage/sqlite_desktop_init_web.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/cloud_sync_service.dart';
import 'services/sync_queue_service.dart';
import 'services/database_helper.dart';
import 'services/system_notification_service.dart';
import 'services/license_service.dart';
import 'screens/license/license_expired_screen.dart';
import 'providers/invoice_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/idle_timeout_provider.dart';
import 'providers/product_provider.dart';
import 'providers/inventory_products_provider.dart';
import 'providers/customers_provider.dart';
import 'providers/suppliers_ap_provider.dart';
import 'providers/sale_draft_provider.dart';
import 'providers/parked_sales_provider.dart';
import 'providers/shift_provider.dart';
import 'providers/print_settings_provider.dart';
import 'providers/loyalty_settings_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/sale_pos_settings_provider.dart';
import 'providers/ui_feedback_settings_provider.dart';
import 'providers/dashboard_layout_provider.dart';
import 'providers/global_barcode_route_bridge.dart';
import 'providers/open_ops_registry.dart';
import 'widgets/global_barcode_keyboard_listener.dart';
import 'widgets/restricted_mode_banner_controller.dart';
import 'navigation/app_root_navigator_key.dart';
import 'services/mac_style_settings_prefs.dart';
import 'services/tenant_context_service.dart';
import 'services/supabase_config.dart';
import 'services/auth/secure_session_storage.dart';
import 'screens/auth/device_kicked_out_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding/business_setup_wizard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/shift/open_shift_screen.dart';
import 'theme/app_theme_resolver.dart';
import 'widgets/idle_session_shell.dart';
import 'screens/dev/stress_tools_screen.dart';

bool _remoteKickHandlerRegistered = false;
bool _remoteKickInProgress = false;

void _registerRemoteDeviceRevokeHandler() {
  if (_remoteKickHandlerRegistered) return;
  _remoteKickHandlerRegistered = true;
  CloudSyncService.instance.onRemoteDeviceRevoked = () async {
    if (_remoteKickInProgress) return;
    _remoteKickInProgress = true;
    try {
      final nav = appRootNavigatorKey.currentState;
      final ctx = appRootNavigatorKey.currentContext;
      if (nav == null || ctx == null || !nav.mounted) return;
      final auth = Provider.of<AuthProvider>(ctx, listen: false);
      await auth.logout();
      if (!nav.mounted) return;
      await nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const DeviceKickedOutScreen(),
        ),
        (_) => false,
      );
    } finally {
      _remoteKickInProgress = false;
    }
  };
}

// Step 23: ربط Kill Switch (tenant_access UPDATE من Realtime).
// نُعيد استعمال DeviceKickedOutScreen كشاشة "تم إيقاف الحساب" — السلوك متطابق
// (logout + قفل الواجهة). يمكن لاحقاً عرض شاشة مخصّصة لو احتجنا.
bool _tenantRevokeHandlerRegistered = false;
bool _tenantRevokeInProgress = false;

void _registerTenantRevokeHandler() {
  if (_tenantRevokeHandlerRegistered) return;
  _tenantRevokeHandlerRegistered = true;
  CloudSyncService.instance.onTenantRevoked = () async {
    if (_tenantRevokeInProgress) return;
    _tenantRevokeInProgress = true;
    try {
      final nav = appRootNavigatorKey.currentState;
      final ctx = appRootNavigatorKey.currentContext;
      if (nav == null || ctx == null || !nav.mounted) return;
      final auth = Provider.of<AuthProvider>(ctx, listen: false);
      await auth.logout();
      if (!nav.mounted) return;
      await nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => const DeviceKickedOutScreen(),
        ),
        (_) => false,
      );
    } finally {
      _tenantRevokeInProgress = false;
    }
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    // #region agent log
    DebugNdjsonLogger.log(
      runId: 'pre-fix',
      hypothesisId: 'H0',
      location: 'main.dart:main',
      message: 'debug session started',
      data: const {},
    );
    // #endregion

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');

      // #region agent log
      DebugNdjsonLogger.log(
        runId: 'pre-fix',
        hypothesisId: 'H0',
        location: 'main.dart:FlutterError.onError',
        message: 'FlutterError captured',
        data: {
          'exception': details.exceptionAsString(),
          'library': details.library,
          'context': details.context?.toDescription(),
          'stack': details.stack?.toString(),
        },
      );
      // #endregion
    };

    // Catch errors that bypass FlutterError (async / platform dispatcher).
    // #region agent log
    PlatformDispatcher.instance.onError = (error, stack) {
      DebugNdjsonLogger.log(
        runId: 'pre-fix',
        hypothesisId: 'H0',
        location: 'main.dart:PlatformDispatcher.onError',
        message: 'uncaught error captured',
        data: {'error': error.toString(), 'stack': stack.toString()},
      );
      return false;
    };
    // #endregion
  }
  initSqliteForPlatform();
  // Fail fast if --dart-define values are missing (or assertions stripped in release).
  SupabaseConfig.assertConfigured();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    // Offline-friendly: prevent noisy infinite refresh retries when DNS/Internet is down.
    // We explicitly trigger sync/bootstrap from our code paths when needed.
    // Token persisted in OS-level secure storage (Keychain / EncryptedSharedPreferences / DPAPI)
    // instead of plain SharedPreferences. Also auto-migrates any legacy token on first run.
    authOptions: FlutterAuthClientOptions(
      autoRefreshToken: false,
      localStorage: SecureLocalStorage(
        persistSessionKey:
            supabasePersistSessionKeyFromUrl(SupabaseConfig.url),
      ),
    ),
  );
  if (kDebugMode) {
    debugPrint('Before runStartupCriticalMigrations');
  }
  await DatabaseHelper().runStartupCriticalMigrations();
  if (kDebugMode) {
    debugPrint('After runStartupCriticalMigrations / Before LicenseService');
  }
  await LicenseService.instance.initialize();
  if (kDebugMode) {
    debugPrint('After LicenseService / Before SyncQueueService');
  }
  SyncQueueService.instance.initialize();
  if (kDebugMode) {
    debugPrint('After SyncQueueService / Before SystemNotificationService');
  }
  await SystemNotificationService.instance.initialize();
  if (kDebugMode) {
    debugPrint('After SystemNotificationService / Before runApp');
  }
  unawaited(MacStyleSettingsPrefs.isMacStylePanelEnabled());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // توفير خدمة الترخيص عالمياً لاستخدامها في البانر/التعطيل داخل Restricted Mode.
        ChangeNotifierProvider.value(value: LicenseService.instance),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => InvoiceProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProductsProvider()),
        ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ChangeNotifierProvider(create: (_) => SuppliersApProvider()),
        ChangeNotifierProvider(create: (_) => SaleDraftProvider()),
        ChangeNotifierProvider(create: (_) => ParkedSalesProvider()),
        ChangeNotifierProvider(create: (_) => IdleTimeoutProvider()),
        ChangeNotifierProvider(create: (_) => ShiftProvider()),
        ChangeNotifierProvider(create: (_) => PrintSettingsProvider()),
        ChangeNotifierProvider(create: (_) => LoyaltySettingsProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => SalePosSettingsProvider()),
        ChangeNotifierProvider(create: (_) => UiFeedbackSettingsProvider()),
        ChangeNotifierProvider(create: (_) => DashboardLayoutProvider()),
        ChangeNotifierProvider(create: (_) => OpenOpsRegistry()),
        ChangeNotifierProvider.value(value: TenantContextService.instance),
        Provider(create: (_) => GlobalBarcodeRouteBridge()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return Consumer<SalePosSettingsProvider>(
            builder: (context, salePosProv, _) {
              return MaterialApp(
                navigatorKey: appRootNavigatorKey,
                title: 'naboo',
                debugShowCheckedModeBanner: false,
                theme: AppThemeResolver.light(salePosProv.data),
                darkTheme: AppThemeResolver.dark(salePosProv.data),
                themeMode: themeProvider.isDarkMode
                    ? ThemeMode.dark
                    : ThemeMode.light,
                themeAnimationDuration: const Duration(milliseconds: 460),
                themeAnimationCurve: Curves.easeOutCubic,
                builder: (context, child) {
                  _registerRemoteDeviceRevokeHandler();
                  _registerTenantRevokeHandler();
                  LicenseService.instance.attachOpenOpsRegistry(
                    Provider.of<OpenOpsRegistry>(context, listen: false),
                  );
                  final salePosSettings = Provider.of<SalePosSettingsProvider>(
                    context,
                    listen: false,
                  );
                  final uiFeedback = Provider.of<UiFeedbackSettingsProvider>(
                    context,
                    listen: false,
                  );
                  final mq = MediaQuery.of(context);
                  final userScale = salePosSettings.data.appTextScale;
                  final combinedScaler = TextScaler.linear(
                    (mq.textScaler.scale(1.0) * userScale).clamp(0.75, 2.2),
                  );
                  Widget content = child ?? const SizedBox.shrink();
                  content = MediaQuery(
                    data: mq.copyWith(textScaler: combinedScaler),
                    child: content,
                  );
                  content = Selector<AuthProvider, bool>(
                    selector: (_, a) => a.isLoggedIn,
                    builder: (context, loggedIn, child) {
                      if (!loggedIn) return child ?? const SizedBox.shrink();
                      final isDark = context.select<ThemeProvider, bool>(
                        (t) => t.isDarkMode,
                      );
                      final label = context.select<AuthProvider, String>(
                        (a) => a.displayName,
                      );
                      return GlobalBarcodeKeyboardListener(
                        child: IdleSessionShell(
                          isDark: isDark,
                          userLabel: label,
                          child: child ?? const SizedBox.shrink(),
                        ),
                      );
                    },
                    child: content,
                  );
                  content = RestrictedModeBannerController(child: content);
                  final sz = MediaQuery.sizeOf(context);
                  final compactUi = sz.width < 360 || sz.height < 640;
                  final base = Theme.of(context);
                  final snackBase = base.snackBarTheme;
                  final snackMerged = snackBase.copyWith(
                    behavior: uiFeedback.useCompactSnackNotifications
                        ? SnackBarBehavior.floating
                        : SnackBarBehavior.fixed,
                    width: uiFeedback.useCompactSnackNotifications
                        ? (sz.width - 32).clamp(280.0, 520.0)
                        : null,
                  );
                  final themedContent = Theme(
                    data: base.copyWith(
                      visualDensity: compactUi
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                      snackBarTheme: snackMerged,
                    ),
                    child: content,
                  );
                  return _ThemeModeTransitionShell(
                    isDarkMode: themeProvider.isDarkMode,
                    child: themedContent,
                  );
                },
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ar', 'SA')],
                locale: const Locale('ar', 'SA'),
                initialRoute: '/',
                routes: {
                  '/': (context) => const _LicenseAwareRoot(),
                  '/login': (context) => const LoginScreen(),
                  '/home': (context) => const HomeScreen(),
                  '/open-shift': (context) => const OpenShiftScreen(),
                  '/onboarding': (context) => const BusinessSetupWizardScreen(),
                  '/dev/stress': (context) => const StressToolsScreen(),
                },
                onGenerateRoute: (settings) {
                  if (settings.name == '/home' ||
                      settings.name == '/open-shift' ||
                      settings.name == '/onboarding') {
                    final auth = Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    );
                    if (!auth.isLoggedIn) {
                      return MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      );
                    }
                  }
                  return null;
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ThemeModeTransitionShell extends StatefulWidget {
  const _ThemeModeTransitionShell({
    required this.isDarkMode,
    required this.child,
  });

  final bool isDarkMode;
  final Widget child;

  @override
  State<_ThemeModeTransitionShell> createState() =>
      _ThemeModeTransitionShellState();
}

class _ThemeModeTransitionShellState extends State<_ThemeModeTransitionShell> {
  bool _showTransition = false;

  @override
  void didUpdateWidget(covariant _ThemeModeTransitionShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDarkMode == widget.isDarkMode) return;

    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disableAnimations) return;

    setState(() => _showTransition = true);
    unawaited(Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      setState(() => _showTransition = false);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final overlayColor = widget.isDarkMode
        ? const Color(0xFF0F172A)
        : const Color(0xFFFFFBEB);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _showTransition ? 0.18 : 0,
            duration: Duration(milliseconds: _showTransition ? 160 : 360),
            curve: Curves.easeOutCubic,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: AlignmentDirectional.topEnd,
                  radius: 1.15,
                  colors: [
                    overlayColor.withValues(alpha: 0.95),
                    overlayColor.withValues(alpha: 0.18),
                    overlayColor.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── بوابة الترخيص داخل Navigator (لها وصول لـ Overlay) ──────────────────────

class _LicenseAwareRoot extends StatefulWidget {
  const _LicenseAwareRoot();

  @override
  State<_LicenseAwareRoot> createState() => _LicenseAwareRootState();
}

class _LicenseAwareRootState extends State<_LicenseAwareRoot> {
  @override
  void initState() {
    super.initState();
    LicenseService.instance.addListener(_onLicenseChange);
  }

  @override
  void dispose() {
    LicenseService.instance.removeListener(_onLicenseChange);
    super.dispose();
  }

  void _onLicenseChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final state = LicenseService.instance.state;

    switch (state.status) {
      case LicenseStatus.checking:
        return const _LicenseCheckingScreen();

      case LicenseStatus.none:
        return const SplashScreen();

      case LicenseStatus.trial:
      case LicenseStatus.active:
        return const SplashScreen();

      case LicenseStatus.restricted:
      case LicenseStatus.pendingLock:
        return const SplashScreen();

      case LicenseStatus.expired:
      case LicenseStatus.suspended:
        return LicenseExpiredScreen(state: state);

      case LicenseStatus.offline:
        // نسمح بالدخول مع تحذير (ستُعرض في الشاشة الرئيسية)
        return const SplashScreen();
    }
  }
}

class _LicenseCheckingScreen extends StatelessWidget {
  const _LicenseCheckingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1E3A5F),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NaBoo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'نظام إدارة المتاجر',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            SizedBox(height: 32),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'جارٍ التحقق من الترخيص…',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
