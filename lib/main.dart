import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/cloud_sync_service.dart';
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
import 'widgets/global_barcode_keyboard_listener.dart';
import 'navigation/app_root_navigator_key.dart';
import 'services/mac_style_settings_prefs.dart';
import 'services/tenant_context_service.dart';
import 'services/supabase_config.dart';
import 'screens/auth/device_kicked_out_screen.dart';
import 'screens/splash_screen.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    // Offline-friendly: prevent noisy infinite refresh retries when DNS/Internet is down.
    // We explicitly trigger sync/bootstrap from our code paths when needed.
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: false,
    ),
  );
  await LicenseService.instance.initialize();
  await SystemNotificationService.instance.initialize();
  unawaited(MacStyleSettingsPrefs.isMacStylePanelEnabled());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
        ChangeNotifierProvider.value(value: TenantContextService.instance),
        Provider(create: (_) => GlobalBarcodeRouteBridge()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return Consumer<SalePosSettingsProvider>(
            builder: (context, salePosProv, _) {
              return MaterialApp(
                navigatorKey: appRootNavigatorKey,
                title: 'نظام إدارة الأعمال',
                debugShowCheckedModeBanner: false,
                theme: AppThemeResolver.light(salePosProv.data),
                darkTheme: AppThemeResolver.dark(salePosProv.data),
                themeMode: themeProvider.isDarkMode
                    ? ThemeMode.dark
                    : ThemeMode.light,
                builder: (context, child) {
                  _registerRemoteDeviceRevokeHandler();
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
                  return Theme(
                    data: base.copyWith(
                      visualDensity: compactUi
                          ? VisualDensity.compact
                          : VisualDensity.standard,
                      snackBarTheme: snackMerged,
                    ),
                    child: content,
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
                  '/dev/stress': (context) => const StressToolsScreen(),
                },
                onGenerateRoute: (settings) {
                  if (settings.name == '/home' ||
                      settings.name == '/open-shift') {
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
