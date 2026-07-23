import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'dart:ui' show PlatformDispatcher;
import 'utils/debug_ndjson_logger.dart';
import 'utils/app_logger.dart';
import 'config/google_oauth_config.dart';
import 'storage/sqlite_desktop_init.dart'
    if (dart.library.html) 'storage/sqlite_desktop_init_web.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/cloud_sync_service.dart';
import 'services/auth/web_url_cleanup.dart';
import 'services/sync_queue_service.dart';
import 'services/database_helper.dart';
import 'services/system_notification_service.dart';
import 'services/license_service.dart';
import 'screens/license/license_expired_screen.dart';
import 'providers/invoice_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/product_provider.dart';
import 'providers/inventory_products_provider.dart';
import 'providers/customers_provider.dart';
import 'providers/suppliers_ap_provider.dart';
import 'providers/sale_draft_provider.dart';
import 'providers/parked_sales_provider.dart';
import 'providers/shift_provider.dart';
import 'providers/print_settings_provider.dart';
import 'providers/business_features_provider.dart';
import 'owner/services/business_audit_log_service.dart';
import 'owner/providers/owner_command_center_provider.dart';
import 'owner/providers/owner_dashboard_studio_provider.dart';
import 'owner/providers/owner_dashboard_layout_provider.dart';
import 'providers/loyalty_settings_provider.dart';
import 'owner/services/owner_fcm_listener_service.dart';
import 'providers/notification_provider.dart';
import 'providers/sale_pos_settings_provider.dart';
import 'providers/ui_feedback_settings_provider.dart';
import 'providers/dashboard_layout_provider.dart';
import 'providers/global_barcode_route_bridge.dart';
import 'providers/open_ops_registry.dart';
import 'widgets/global_barcode_keyboard_listener.dart';
import 'widgets/keyboard_focus_scroll_scope.dart';
import 'widgets/restricted_mode_banner_controller.dart';
import 'navigation/app_root_navigator_key.dart';
import 'services/marketplace/marketplace_session_service.dart';
import 'services/tenant_context_service.dart';
import 'services/supabase_config.dart';
import 'services/auth/secure_session_storage.dart';
import 'screens/auth/device_access_revoked_screen.dart';
import 'screens/auth/device_kicked_out_screen.dart';
import 'screens/auth/complete_owner_profile_screen.dart';
import 'screens/auth/owner_pin_restore_otp_screen.dart';
import 'screens/auth/employee_pin_gate_screen.dart';
import 'providers/permissions_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding/business_setup_wizard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/owner/owner_dashboard_screen.dart';
import 'screens/shift/open_shift_screen.dart';
import 'theme/app_theme_resolver.dart';
import 'widgets/invoice_deep_link_listener.dart';
import 'widgets/cloud_session_resume_bridge.dart';
import 'screens/dev/stress_tools_screen.dart';
import 'verticals/_contract/vertical_registry.dart';
import 'verticals/general_retail/manifest.dart';
import 'verticals/oil_change/manifest.dart';
import 'verticals/pharmacy/manifest.dart';

void _registerVerticalManifests() {
  VerticalRegistry.instance.register(const GeneralRetailVerticalManifest());
  VerticalRegistry.instance.register(const OilChangeVerticalManifest());
  VerticalRegistry.instance.register(const PharmacyVerticalManifest());
}

/// Supabase OAuth returns `io.supabase.naboo://login-callback?code=…`.
bool _isSupabaseOAuthCallbackUri(Uri uri) {
  return uri.scheme == 'io.supabase.naboo' && uri.host == 'login-callback';
}

/// يُستدعى من onGenerateRoute — يمنع Flutter من التعامل مع deep link كمسار.
bool _isSupabaseOAuthCallbackRoute(String? name) {
  if (name == null || name.isEmpty) return false;
  final uri = Uri.tryParse(name);
  if (uri == null) return false;
  return _isSupabaseOAuthCallbackUri(uri);
}

/// معالجة OAuth على iOS/Android/macOS — مع try/catch لمنع crash عند PKCE stale.
void _registerMobileOAuthDeepLinkHandler() {
  if (kIsWeb) return;

  Future<void> handleOAuthUri(Uri uri) async {
    if (!_isSupabaseOAuthCallbackUri(uri)) return;
    try {
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      AppLogger.info('main', 'mobile OAuth session established from deep link');
    } catch (e, st) {
      // يحدث عند إلغاء Google أو hot restart أثناء OAuth — ليس fatal.
      AppLogger.warn('main', 'mobile OAuth getSessionFromUrl failed: $e');
      if (kDebugMode) {
        AppLogger.error('main', 'mobile OAuth deep link stack', e, st);
      }
    }
  }

  final appLinks = AppLinks();
  appLinks.uriLinkStream.listen(handleOAuthUri);
  unawaited(
    appLinks.getInitialLink().then((uri) async {
      if (uri != null) await handleOAuthUri(uri);
    }),
  );
}

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
        MaterialPageRoute<void>(builder: (_) => const DeviceKickedOutScreen()),
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
        MaterialPageRoute<void>(builder: (_) => const DeviceKickedOutScreen()),
        (_) => false,
      );
    } finally {
      _tenantRevokeInProgress = false;
    }
  };
}

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
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
      autoRefreshToken: true,
      // نعالج deep links يدوياً (ويب + موبايل) مع try/catch — تجنب crash PKCE.
      detectSessionInUri: false,
      localStorage: SecureLocalStorage(
        persistSessionKey: supabasePersistSessionKeyFromUrl(SupabaseConfig.url),
      ),
    ),
  );
  _registerMobileOAuthDeepLinkHandler();
  if (!GoogleOAuthConfig.isExplicitDartDefine && kDebugMode) {
    AppLogger.info(
      'main',
      'GOOGLE_WEB_CLIENT_ID: using embedded default (native Google picker enabled)',
    );
  }
  if (kDebugMode) {
    final s = Supabase.instance.client.auth.currentSession;
    debugPrint(
      '[StartupDiag] supabase session restored=${s != null} '
      'user=${Supabase.instance.client.auth.currentUser?.id ?? "null"} '
      'expired=${s?.isExpired}',
    );
  }
  if (kIsWeb) {
    final uri = Uri.base;
    if (uri.queryParameters.containsKey('code') ||
        uri.fragment.contains('access_token')) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
        stripOAuthParamsFromBrowserUrl();
      } catch (e, st) {
        AppLogger.warn('main', 'web OAuth getSessionFromUrl failed: $e');
        if (kDebugMode) {
          debugPrint('web OAuth getSessionFromUrl stack: $st');
        }
      }
    }
  }
  if (kDebugMode) {
    debugPrint('Before runStartupCriticalMigrations');
  }
  await DatabaseHelper().runStartupCriticalMigrations();
  await BusinessAuditLogService.instance.ensureReady();
  if (kDebugMode) {
    debugPrint('After runStartupCriticalMigrations / Before LicenseService');
  }
  await LicenseService.instance.initialize();
  if (kDebugMode) {
    debugPrint('After LicenseService / Before runApp');
  }
  SyncQueueService.instance.initialize();
  _registerVerticalManifests();
  // عجّل ظهور شاشة التحميل (Flutter) — الإشعارات/FCM ليست شرطًا للإقلاع.
  runApp(const MyApp());
  unawaited(_startPostUiServices());
}

Future<void> _startPostUiServices() async {
  try {
    await SystemNotificationService.instance.initialize();
  } catch (e, st) {
    AppLogger.error('main', 'SystemNotificationService init', e, st);
  }
  unawaited(OwnerFcmListenerService.instance.initialize());
  try {
    MarketplaceSessionService.instance.start();
  } catch (e, st) {
    AppLogger.error('main', 'MarketplaceSessionService start', e, st);
  }
  if (kDebugMode) {
    debugPrint('After post-UI services');
  }
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
        ChangeNotifierProxyProvider<AuthProvider, BusinessFeaturesProvider>(
          create: (_) => BusinessFeaturesProvider(),
          update: (_, auth, previous) {
            final provider = previous ?? BusinessFeaturesProvider();
            provider.onActiveStaffChanged(auth.userId);
            return provider;
          },
        ),
        ChangeNotifierProvider.value(value: TenantContextService.instance),
        ChangeNotifierProvider(create: (_) => OwnerCommandCenterProvider()),
        ChangeNotifierProxyProvider<TenantContextService,
            OwnerDashboardStudioProvider>(
          create: (_) => OwnerDashboardStudioProvider(
            tenantId: TenantContextService.instance.activeTenantId,
          ),
          update: (_, tenantCtx, previous) {
            final provider = previous ??
                OwnerDashboardStudioProvider(
                  tenantId: tenantCtx.activeTenantId,
                );
            if (provider.tenantId != tenantCtx.activeTenantId) {
              unawaited(provider.bindTenant(tenantCtx.activeTenantId));
            }
            return provider;
          },
        ),
        ChangeNotifierProxyProvider<TenantContextService,
            OwnerDashboardLayoutProvider>(
          create: (_) => OwnerDashboardLayoutProvider(
            tenantId: TenantContextService.instance.activeTenantId,
          ),
          update: (_, tenantCtx, previous) {
            final provider = previous ??
                OwnerDashboardLayoutProvider(
                  tenantId: tenantCtx.activeTenantId,
                );
            if (provider.tenantId != tenantCtx.activeTenantId) {
              unawaited(provider.bindTenant(tenantCtx.activeTenantId));
            }
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => InvoiceProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProductsProvider()),
        ChangeNotifierProvider(create: (_) => CustomersProvider()),
        ChangeNotifierProvider(create: (_) => SuppliersApProvider()),
        ChangeNotifierProvider(create: (_) => SaleDraftProvider()),
        ChangeNotifierProvider(create: (_) => ParkedSalesProvider()),
        ChangeNotifierProvider(create: (_) => ShiftProvider()),
        ChangeNotifierProxyProvider2<AuthProvider, ShiftProvider, PermissionsProvider>(
          create: (context) => PermissionsProvider(
            context.read<AuthProvider>(),
            context.read<ShiftProvider>(),
          ),
          update: (context, auth, shift, previous) => previous ?? PermissionsProvider(auth, shift),
        ),
        ChangeNotifierProxyProvider<AuthProvider, PrintSettingsProvider>(
          create: (_) => PrintSettingsProvider(),
          update: (_, auth, previous) {
            final provider = previous ?? PrintSettingsProvider();
            provider.onActiveStaffChanged(auth.userId);
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (_) => LoyaltySettingsProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => SalePosSettingsProvider()),
        ChangeNotifierProvider(create: (_) => UiFeedbackSettingsProvider()),
        ChangeNotifierProvider(create: (_) => DashboardLayoutProvider()),
        ChangeNotifierProvider(create: (_) => OpenOpsRegistry()),
        Provider(create: (_) => GlobalBarcodeRouteBridge()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return Consumer<SalePosSettingsProvider>(
            builder: (context, salePosProv, _) {
              return CloudSessionResumeBridge(
                child: MaterialApp(
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
                      if (loggedIn) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          OwnerFcmListenerService.instance.flushPendingIfReady();
                        });
                      }
                      if (!loggedIn) return child ?? const SizedBox.shrink();
                      return GlobalBarcodeKeyboardListener(
                        child: InvoiceDeepLinkListener(
                          child: child ?? const SizedBox.shrink(),
                        ),
                      );
                    },
                    child: content,
                  );
                  content = RestrictedModeBannerController(child: content);
                  content = KeyboardFocusScrollScope(child: content);
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
                  '/employee-gate': (context) {
                    final auth = context.read<AuthProvider>();
                    if (!auth.deviceOwnerBound) {
                      return const LoginScreen();
                    }
                    if (auth.deviceAccessRevokedPending) {
                      return const DeviceAccessRevokedScreen();
                    }
                    return const EmployeePinGateScreen();
                  },
                  '/device-access-revoked': (context) =>
                      const DeviceAccessRevokedScreen(),
                  '/complete-google-profile': (context) {
                    final auth = context.read<AuthProvider>();
                    if (!auth.deviceOwnerBound) {
                      return const LoginScreen();
                    }
                    if (auth.deviceAccessRevokedPending) {
                      return const DeviceAccessRevokedScreen();
                    }
                    return const CompleteOwnerProfileScreen();
                  },
                  '/owner-pin-restore-otp': (context) {
                    final auth = context.read<AuthProvider>();
                    if (!auth.deviceOwnerBound) {
                      return const LoginScreen();
                    }
                    if (auth.deviceAccessRevokedPending) {
                      return const DeviceAccessRevokedScreen();
                    }
                    final args = ModalRoute.of(context)?.settings.arguments;
                    final otpAlreadySent =
                        args is Map && args['otpAlreadySent'] == true;
                    return OwnerPinRestoreOtpScreen(
                      otpAlreadySent: otpAlreadySent,
                    );
                  },
                  '/home': (context) => const _HomeRouteResolver(),
                  '/open-shift': (context) => const OpenShiftScreen(),
                  '/onboarding': (context) => const BusinessSetupWizardScreen(),
                  '/dev/stress': (context) => const StressToolsScreen(),
                },
                onGenerateRoute: (settings) {
                  if (_isSupabaseOAuthCallbackRoute(settings.name)) {
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => const _LicenseAwareRoot(),
                    );
                  }
                  if (settings.name == '/home' ||
                      settings.name == '/open-shift' ||
                      settings.name == '/onboarding') {
                    final auth = Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    );
                    if (!auth.isLoggedIn) {
                      if (auth.deviceOwnerBound) {
                        return MaterialPageRoute(
                          builder: (_) => const EmployeePinGateScreen(),
                        );
                      }
                      return MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      );
                    }
                  }
                  return null;
                },
                onUnknownRoute: (settings) {
                  if (_isSupabaseOAuthCallbackRoute(settings.name)) {
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => const _LicenseAwareRoot(),
                    );
                  }
                  return MaterialPageRoute<void>(
                    settings: settings,
                    builder: (_) => const LoginScreen(),
                  );
                },
              ),
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
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 520), () {
        if (!mounted) return;
        setState(() => _showTransition = false);
      }),
    );
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
      case LicenseStatus.none:
      case LicenseStatus.trial:
      case LicenseStatus.active:
      case LicenseStatus.restricted:
      case LicenseStatus.pendingLock:
      case LicenseStatus.offline:
        // شاشة إقلاع واحدة — بدون قفز بين واجهتين مختلفتين.
        return const SplashScreen(key: ValueKey('app-splash'));

      case LicenseStatus.expired:
      case LicenseStatus.suspended:
        return LicenseExpiredScreen(state: state);
    }
  }
}

class _HomeRouteResolver extends StatelessWidget {
  const _HomeRouteResolver();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isOwner) {
      return const OwnerDashboardScreen();
    }
    return const HomeScreen();
  }
}
