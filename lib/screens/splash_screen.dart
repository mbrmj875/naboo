import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/business_features_provider.dart';
import '../providers/auth_provider.dart';
import '../services/app_session_lifecycle.dart';
import '../services/app_remote_config_service.dart';
import '../services/app_in_app_update_service.dart';
import '../services/app_settings_repository.dart';
import '../services/business_setup_settings.dart';
import '../services/license_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_update_progress_dialog.dart';
import '../widgets/glass/glass_surface.dart';
import '../utils/app_logger.dart';
import '../utils/screen_layout.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final int _bootGeneration;

  late final AnimationController _stampCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;

  AudioPlayer? _player;
  bool _stampSoundPlayed = false;
  Timer? _startupFailsafeTimer;

  @override
  void initState() {
    super.initState();
    _bootGeneration = ++AppSessionLifecycle.splashBootstrapGeneration;

    // One controller for the full "royal stamp" sequence (0..1300ms)
    _stampCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    // شاشة التحميل الكاملة ظاهرة من أول إطار — بدون مرحلة «شعار فقط».
    _logoScale = const AlwaysStoppedAnimation<double>(1.0);
    _logoOpacity = const AlwaysStoppedAnimation<double>(1.0);
    _textOpacity = const AlwaysStoppedAnimation<double>(1.0);

    // صوت الختم بعد لحظة قصيرة دون إخفاء عناصر الشاشة.
    _stampCtrl.addListener(() {
      if (_stampSoundPlayed) return;
      if (_stampCtrl.value < (750 / 1300)) return;
      _stampSoundPlayed = true;
      _playStampSound();
    });

    _stampCtrl.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_handoffFromNativeSplash());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_bootGeneration != AppSessionLifecycle.splashBootstrapGeneration) {
        return;
      }
      unawaited(_goNext());
    });

    _startupFailsafeTimer = Timer(const Duration(seconds: 22), () {
      if (!mounted) return;
      if (!_bootStillActive()) return;
      if (AppSessionLifecycle.splashNavigationCompleted) return;
      AppLogger.warn('Splash', 'failsafe — الإقلاع تجاوز 22 ثانية');
      AppSessionLifecycle.splashNavigationCompleted = true;
      // جهاز مربوط → بوابة PIN وليس شاشة Google (حتى لو بطُؤ الإقلاع بعد قتل التطبيق).
      final auth = context.read<AuthProvider>();
      final target = auth.deviceOwnerBound ? '/employee-gate' : '/login';
      unawaited(Navigator.of(context).pushReplacementNamed(target));
    });
  }

  bool _bootStillActive() =>
      mounted && _bootGeneration == AppSessionLifecycle.splashBootstrapGeneration;

  /// يبقي شاشة النظام ظاهرة حتى تُحمَّل أصول Flutter — يمنع وميض اللون الكحلي الفارغ.
  Future<void> _handoffFromNativeSplash() async {
    try {
      await Future.wait<void>([
        precacheImage(const AssetImage('assets/images/splash_bg.png'), context),
        precacheImage(
          const AssetImage('assets/images/splash_logo_mark.png'),
          context,
        ),
      ]);
    } catch (e) {
      AppLogger.warn('Splash', 'precache splash assets: $e');
    }
    if (!mounted) return;
    FlutterNativeSplash.remove();
  }

  Future<void> _playStampSound() async {
    try {
      final p = _player ?? AudioPlayer();
      _player = p;
      await p.setVolume(0.7);
      await p.play(AssetSource('stamp_sound.mp3'), volume: 0.7);
    } catch (_) {
      // Ignore audio failures
    }
  }

  Future<void> _goNext() async {
    if (AppSessionLifecycle.splashNavigationCompleted) return;
    if (!_bootStillActive()) return;

    final gen = _bootGeneration;
    final prior = AppSessionLifecycle.splashNavigationTask;
    if (prior != null) {
      if (AppSessionLifecycle.splashNavigationTaskGen == gen) {
        await prior;
        if (AppSessionLifecycle.splashNavigationCompleted || !_bootStillActive()) {
          return;
        }
      } else if (AppSessionLifecycle.splashNavigationTaskGen < gen) {
        await prior;
        if (!_bootStillActive()) return;
        if (AppSessionLifecycle.splashNavigationCompleted) return;
      }
    }

    if (!_bootStillActive()) return;
    if (AppSessionLifecycle.splashNavigationCompleted) return;

    AppSessionLifecycle.splashNavigationTaskGen = gen;
    final task = _runStartupNavigation();
    AppSessionLifecycle.splashNavigationTask = task;
    try {
      await task;
    } finally {
      if (identical(AppSessionLifecycle.splashNavigationTask, task)) {
        AppSessionLifecycle.splashNavigationTask = null;
      }
    }
  }

  Future<void> _runStartupNavigation() async {
    final auth = context.read<AuthProvider>();

    // إعدادات سحابية: صيانة، تحديث، إلخ — تصل لكل من ثبّت التطبيق سابقاً عند فتحه مع إنترنت.
    try {
      await AppRemoteConfigService.instance
          .refresh(force: true)
          .timeout(const Duration(seconds: 6));
    } catch (e, st) {
      AppLogger.error('Splash', 'remote config refresh', e, st);
    }
    if (!_bootStillActive()) return;

    final cfg = AppRemoteConfigService.instance.current;
    if (cfg.maintenanceMode) {
      final msg = cfg.maintenanceMessageAr.isNotEmpty
          ? cfg.maintenanceMessageAr
          : 'التطبيق تحت الصيانة. حاول لاحقاً.';
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('صيانة'),
          content: SingleChildScrollView(child: Text(msg)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
      return;
    }

    final pkg = await PackageInfo.fromPlatform();
    final v = pkg.version;
    final downloadUrl = cfg.updateDownloadUrl.isNotEmpty
        ? cfg.updateDownloadUrl
        : AppInAppUpdateService.fallbackApkUrl;
    final updateMsg = cfg.updateMessageAr.isNotEmpty
        ? cfg.updateMessageAr
        : 'يتوفر تحديث جديد للتطبيق. اضغط «تحديث التطبيق الآن» ليُنزَّل ويُثبَّت تلقائياً.';

    if (cfg.forceUpdate &&
        AppRemoteConfigService.compareVersions(v, cfg.minSupportedVersion) <
            0) {
      if (!_bootStillActive()) return;
      await showAppUpdateAndInstallDialog(
        context,
        title: 'تحديث مطلوب',
        message: updateMsg,
        downloadUrl: downloadUrl,
        force: true,
      );
      return;
    }

    final hasNewer = AppRemoteConfigService.compareVersions(
          v,
          cfg.latestVersion,
        ) <
        0;
    if (hasNewer && cfg.latestVersion != '0.0.0') {
      if (!_bootStillActive()) return;
      await showAppUpdateAndInstallDialog(
        context,
        title: 'تحديث التطبيق',
        message: updateMsg,
        downloadUrl: downloadUrl,
        force: false,
      );
    }

    // إعلان عام (مناسبات، تنبيهات، عروض…) — يظهر مرة لكل محتوى جديد (بصمة MD5).
    final annDigest = cfg.announcementContentDigest;
    if (annDigest.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getString('naboo.announcement_digest_seen') ?? '';
      if (seen != annDigest) {
        if (!_bootStillActive()) return;
        final title = cfg.announcementTitleAr.isNotEmpty
            ? cfg.announcementTitleAr
            : 'رسالة من الإدارة';
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(cfg.announcementBodyAr)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('حسناً'),
              ),
              if (cfg.announcementUrl.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final u = Uri.tryParse(cfg.announcementUrl);
                    if (u != null) {
                      await launchUrl(u, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('فتح الرابط'),
                ),
            ],
          ),
        );
        await prefs.setString('naboo.announcement_digest_seen', annDigest);
      }
    }

    // ربط الجهاز يُقرأ أولاً وبمعزل عن بقية الاستعادة — وإلا مؤقت قصير
    // أو بطء بعد مسح التطبيق من «التطبيقات الحديثة» يوجّه خطأً لشاشة Google.
    try {
      await auth.loadPersistedDeviceOwnerBinding().timeout(
        const Duration(seconds: 3),
      );
    } catch (e, st) {
      AppLogger.error('Splash', 'فشل loadPersistedDeviceOwnerBinding', e, st);
    }
    if (!_bootStillActive()) return;

    try {
      await auth.restoreSession().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          AppLogger.warn(
            'Splash',
            'restoreSession timed out — binding kept '
            '(deviceOwnerBound=${auth.deviceOwnerBound})',
          );
        },
      );
    } catch (e, st) {
      AppLogger.error('Splash', 'فشل restoreSession', e, st);
    }
    if (!_bootStillActive()) return;

    if (kIsWeb) {
      try {
        final oauthErr = await auth.tryCompletePendingWebGoogleOAuth().timeout(
          const Duration(seconds: 60),
          onTimeout: () => 'انتهت مهلة إكمال تسجيل Google',
        );
        if (!_bootStillActive()) return;
        if (oauthErr == AuthProvider.kGoogleOwnerPinRestoreOtpRequired) {
          AppSessionLifecycle.splashNavigationCompleted = true;
          final row = await auth.getLocalOwnerRow();
          final localId = (row?['id'] as num?)?.toInt();
          unawaited(
            Navigator.of(context).pushReplacementNamed(
              '/owner-pin-restore-otp',
              arguments: {
                'otpAlreadySent': true,
                if (localId != null) 'localOwnerUserId': localId,
              },
            ),
          );
          return;
        }
        if (oauthErr == AuthProvider.kGoogleOwnerProfileRequired) {
          AppSessionLifecycle.splashNavigationCompleted = true;
          unawaited(
            Navigator.of(context).pushReplacementNamed(
              '/complete-google-profile',
            ),
          );
          return;
        }
        if (oauthErr == AuthProvider.kGoogleNetworkError) {
          AppSessionLifecycle.splashNavigationCompleted = true;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'تعذر التحقق من الحساب. تحقق من الاتصال بالإنترنت وحاول مرة أخرى.',
                ),
                backgroundColor: Colors.orange.shade800,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          unawaited(Navigator.of(context).pushReplacementNamed('/login'));
          return;
        }
        if (oauthErr == AuthProvider.kGoogleAccountAlreadyExists ||
            oauthErr == AuthProvider.kGoogleNoAccountFound) {
          final mismatchMsg = oauthErr!;
          AppSessionLifecycle.splashNavigationCompleted = true;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(mismatchMsg),
                backgroundColor: Colors.orange.shade800,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
              ),
            );
          }
          unawaited(Navigator.of(context).pushReplacementNamed('/login'));
          return;
        }
        if (oauthErr != null && oauthErr.isNotEmpty) {
          AppLogger.warn('Splash', 'Google OAuth web: $oauthErr');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(oauthErr),
                backgroundColor: Colors.red.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      } catch (e, st) {
        AppLogger.error('Splash', 'فشل إكمال Google OAuth على الويب', e, st);
      }
    }
    if (!_bootStillActive()) return;

    try {
      await _showTargetedRoyalMessageIfAny().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );
    } catch (e, st) {
      AppLogger.error('Splash', 'فشل رسالة المالك المخصصة', e, st);
    }

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!_bootStillActive()) return;

    if (!auth.deviceOwnerBound) {
      // Phase A (Atomic): يمنع أي دخول تشغيلي قبل ربط الجهاز بمالك.
      // إذا وجدت جلسة قديمة غير مربوطة، نغلقها ثم نعيد المستخدم إلى Gmail login.
      if (auth.isLoggedIn) {
        await auth.logout();
        if (!_bootStillActive()) return;
      }
      AppSessionLifecycle.splashNavigationCompleted = true;
      unawaited(Navigator.of(context).pushReplacementNamed('/login'));
      return;
    }

    if (auth.deviceOwnerBound) {
      try {
        await auth.ensureCloudSessionActive();
      } catch (e, st) {
        AppLogger.warn('Splash', 'ensureCloudSessionActive: $e');
        AppLogger.error('Splash', 'cloud session restore stack', e, st);
      }
    }

    if (Supabase.instance.client.auth.currentUser != null) {
      try {
        final needsImport = !(await BusinessSetupSettingsData.isCompleted(
          AppSettingsRepository.instance,
        ));
        await auth.hydrateCloudAccountData(
          timeout: const Duration(seconds: 12),
          forcePull: true,
          forceImportOnPull: needsImport,
          maxAttempts: needsImport ? 2 : 1,
        );
      } catch (e, st) {
        AppLogger.error(
          'Splash',
          'hydrateCloudAccountData — الإقلاع يستمر',
          e,
          st,
        );
      }
      if (_bootStillActive()) {
        try {
          await context.read<BusinessFeaturesProvider>().refresh();
        } catch (e, st) {
          AppLogger.error('Splash', 'فشل refresh BusinessFeatures', e, st);
        }
      }
    }
    if (!_bootStillActive()) return;

    await _navigateAfterBootstrap(auth);
  }

  Future<void> _navigateAfterBootstrap(AuthProvider auth) async {
    final target = await _resolveStartupRoute(auth).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        AppLogger.warn('Splash', 'resolveStartupRoute timed out — fallback');
        return auth.deviceOwnerBound ? '/employee-gate' : '/login';
      },
    );
    if (!_bootStillActive()) return;
    if (AppSessionLifecycle.splashNavigationCompleted) return;
    AppSessionLifecycle.splashNavigationCompleted = true;
    try {
      Object? routeArgs;
      if (target == '/owner-pin-restore-otp') {
        final row = await auth.getLocalOwnerRow();
        final localId = (row?['id'] as num?)?.toInt();
        routeArgs = {
          if (localId != null) 'localOwnerUserId': localId,
        };
      }
      unawaited(
        Navigator.of(context).pushReplacementNamed(
          target,
          arguments: routeArgs,
        ),
      );
    } catch (e, st) {
      AppLogger.error('Splash', 'فشل التنقل بعد الإقلاع — fallback', e, st);
      if (!_bootStillActive()) return;
      final fallback = auth.deviceOwnerBound ? '/employee-gate' : '/login';
      unawaited(Navigator.of(context).pushReplacementNamed(fallback));
    }
  }

  /// بعد ربط الجهاز: استعادة آخر جلسة تشغيل (مالك/موظف) أو بوابة PIN.
  Future<String> _resolveStartupRoute(AuthProvider auth) async {
    if (!auth.deviceOwnerBound) return '/login';
    if (auth.deviceAccessRevokedPending) return '/device-access-revoked';
    return auth.resolveStartupRouteLight();
  }

  Future<void> _showTargetedRoyalMessageIfAny() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select(
            'custom_message_title_ar,custom_message_body_ar,custom_message_active',
          )
          .eq('id', user.id)
          .maybeSingle();
      if (!_bootStillActive() || row == null) return;

      final active = row['custom_message_active'] == true;
      final body = (row['custom_message_body_ar'] ?? '').toString().trim();
      if (!active || body.isEmpty) return;
      final title = (row['custom_message_title_ar'] ?? '').toString().trim();

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: const Color(0xFF071A36),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFB8960C), width: 1.2),
            ),
            title: Text(
              title.isEmpty ? 'رسالة خاصة من الإدارة' : title,
              style: const TextStyle(
                color: Color(0xFFFFE08A),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.start,
            ),
            content: SingleChildScrollView(
              child: Text(
                body,
                style: const TextStyle(color: Color(0xFFFFF2B2), height: 1.5),
                textAlign: TextAlign.start,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFFE08A),
                ),
                child: const Text('تم'),
              ),
            ],
          );
        },
      );
    } catch (e, st) {
      AppLogger.error('Splash', 'custom royal message — تخطي', e, st);
    }
  }

  @override
  void dispose() {
    _startupFailsafeTimer?.cancel();
    _stampCtrl.dispose();
    try {
      _player?.dispose();
    } catch (e) {
      AppLogger.warn('Splash', 'تعذّر dispose للصوت: $e');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final licenseChecking =
        context.watch<LicenseService>().state.status == LicenseStatus.checking;
    final statusText = licenseChecking
        ? 'جارٍ التحقق من الترخيص…'
        : 'جاري تهيئة النظام…';

    // 2026-05 (Phase 2): الـ logo scale factor صار يعتمد على DeviceVariant
    // بدل breakpoints رقمية. النسب نفسها لكن المنطق واضح ومحاذٍ للدستور.
    // (Width الفعلي يبقى ضرورياً لـ clamp والـ wordmark scaling.)
    final variant = context.screenLayout.layoutVariant;
    final logoScale = switch (variant) {
      DeviceVariant.desktopSM || DeviceVariant.desktopLG => 0.30,
      DeviceVariant.tabletSM || DeviceVariant.tabletLG => 0.45,
      DeviceVariant.phoneXS || DeviceVariant.phoneSM => 0.60,
    };
    var logoW = w * logoScale;
    // Always keep the stamp/logo visually dominant.
    logoW = logoW.clamp(320.0, 980.0);
    // Force "logo much larger than wordmark" on huge screens.
    if (w >= 2000) {
      logoW = logoW.clamp(860.0, 980.0);
    }

    // Wordmark size derived from logo size (always much smaller).
    final wordSize = (logoW * 0.10).clamp(14.0, 56.0);
    final pullUp = (logoW * 0.04).clamp(0.0, 12.0);
    final progressSize = (w * 0.08).clamp(18.0, 44.0);

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.primary,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // خلفية صلبة أولاً (مطابقة للـ native splash) ثم الصورة فوقها.
            const ColoredBox(color: AppColors.primary),
            const DecoratedBox(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/splash_bg.png'),
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.primary.withValues(alpha: 0.22),
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: _logoOpacity,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: logoW,
                        height: logoW,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: logoW * 0.92,
                              height: logoW * 0.92,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    const Color(
                                      0xFF071A36,
                                    ).withValues(alpha: 0.55),
                                    const Color(
                                      0xFF071A36,
                                    ).withValues(alpha: 0.18),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFB8960C,
                                    ).withValues(alpha: 0.18),
                                    blurRadius: 38,
                                    spreadRadius: 6,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.30),
                                    blurRadius: 44,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: (logoW * 0.02).clamp(4.0, 10.0)),
                      FadeTransition(
                        opacity: _textOpacity,
                        child: Transform.translate(
                          offset: Offset(0, -pullUp),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF071A36,
                              ).withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (Rect bounds) {
                                    return const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFFFF2B2),
                                        Color(0xFFF2D36B),
                                        Color(0xFFB8960C),
                                      ],
                                      stops: [0.0, 0.45, 1.0],
                                    ).createShader(bounds);
                                  },
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: logoW * 0.92,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'NABOO',
                                        textDirection: TextDirection.ltr,
                                        maxLines: 1,
                                        softWrap: false,
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: wordSize,
                                          fontWeight: FontWeight.w800,
                                          fontStyle: FontStyle.normal,
                                          letterSpacing: wordSize * 0.035,
                                          height: 1.0,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 18,
                                              color: Colors.black.withValues(
                                                alpha: 0.35,
                                              ),
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  GlassSurface(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(999),
                    ),
                    blurSigma: 12,
                    tintColor: AppGlass.surfaceTint,
                    strokeColor: AppGlass.stroke,
                    padding: const EdgeInsets.all(10),
                    child: SizedBox(
                      width: progressSize + 4,
                      height: progressSize + 4,
                      child: CircularProgressIndicator(
                        strokeWidth: (progressSize * 0.08).clamp(1.5, 3.0),
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.accentGold.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: (progressSize * 0.35).clamp(8.0, 16.0)),
                  Text(
                    statusText,
                    style: GoogleFonts.tajawal(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: (w * 0.03).clamp(12.0, 16.0),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
