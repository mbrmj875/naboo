import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/app_settings_repository.dart';
import '../services/business_setup_settings.dart';
import '../services/app_remote_config_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _stampCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _textOpacity;

  AudioPlayer? _player;
  bool _stampSoundPlayed = false;

  @override
  void initState() {
    super.initState();

    // One controller for the full "royal stamp" sequence (0..1300ms)
    _stampCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );

    // Phase 2 (0..900ms): 0.3 -> 1.0 with elasticOut, then
    // Phase 4 (900..1300ms): one pulse 1.0 -> 1.06 -> 1.0.
    _logoScale = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.3, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 900,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.0, end: 1.06)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 200,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.06, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 200,
      ),
    ]).animate(_stampCtrl);

    // Opacity: 0 -> 1 within first 400ms, then stay at 1
    _logoOpacity = TweenSequence<double>([
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 400,
      ),
      TweenSequenceItem<double>(
        tween: ConstantTween<double>(1.0),
        weight: 900,
      ),
    ]).animate(_stampCtrl);

    // Text appears after 600ms from start (same controller, via Interval)
    _textOpacity = CurvedAnimation(
      parent: _stampCtrl,
      curve: const Interval(600 / 1300, 1.0, curve: Curves.easeIn),
    );

    _stampCtrl.addListener(() {
      // Play sound around 750ms when the logo "settles" near 1.0.
      if (_stampSoundPlayed) return;
      if (_stampCtrl.value < (750 / 1300)) return;
      _stampSoundPlayed = true;
      _playStampSound();
    });

    _stampCtrl.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) => _goNext());
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
    final auth = context.read<AuthProvider>();

    // إعدادات سحابية: صيانة، تحديث، إلخ — تصل لكل من ثبّت التطبيق سابقاً عند فتحه مع إنترنت.
    try {
      await AppRemoteConfigService.instance.refresh(force: true).timeout(
        const Duration(seconds: 6),
      );
    } catch (_) {}
    if (!mounted) return;

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
    if (cfg.forceUpdate &&
        AppRemoteConfigService.compareVersions(v, cfg.minSupportedVersion) <
            0) {
      if (!mounted) return;
      final msg = cfg.updateMessageAr.isNotEmpty
          ? cfg.updateMessageAr
          : 'يجب تحديث التطبيق للمتابعة.';
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('تحديث مطلوب'),
          content: SingleChildScrollView(child: Text(msg)),
          actions: [
            if (cfg.updateDownloadUrl.isNotEmpty)
              TextButton(
                onPressed: () async {
                  final u = Uri.tryParse(cfg.updateDownloadUrl);
                  if (u != null) {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('تحميل التحديث'),
              ),
          ],
        ),
      );
      return;
    }

    if (cfg.updateMessageAr.isNotEmpty &&
        AppRemoteConfigService.compareVersions(v, cfg.latestVersion) < 0) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          title: const Text('تحديث متوفر'),
          content: SingleChildScrollView(child: Text(cfg.updateMessageAr)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('لاحقاً'),
            ),
            if (cfg.updateDownloadUrl.isNotEmpty)
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final u = Uri.tryParse(cfg.updateDownloadUrl);
                  if (u != null) {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text('تحميل'),
              ),
          ],
        ),
      );
    }

    // إعلان عام (مناسبات، تنبيهات، عروض…) — يظهر مرة لكل محتوى جديد (بصمة MD5).
    final annDigest = cfg.announcementContentDigest;
    if (annDigest.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final seen =
          prefs.getString('naboo.announcement_digest_seen') ?? '';
      if (seen != annDigest) {
        if (!mounted) return;
        final title = cfg.announcementTitleAr.isNotEmpty
            ? cfg.announcementTitleAr
            : 'رسالة من الإدارة';
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Text(cfg.announcementBodyAr),
            ),
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
                      await launchUrl(
                        u,
                        mode: LaunchMode.externalApplication,
                      );
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

    try {
      await auth.restoreSession().timeout(
        const Duration(seconds: 6),
        onTimeout: () {},
      );
    } catch (_) {}
    if (!mounted) return;

    await _showTargetedRoyalMessageIfAny();

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    var target = auth.isLoggedIn ? '/open-shift' : '/login';
    if (auth.isLoggedIn) {
      try {
        final completed = await BusinessSetupSettingsData.isCompleted(
          AppSettingsRepository.instance,
        );
        if (!completed) target = '/onboarding';
      } catch (_) {}
    }
    try {
      Navigator.of(context).pushReplacementNamed(target);
    } catch (_) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
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
      if (!mounted || row == null) return;

      final active = row['custom_message_active'] == true;
      final body = (row['custom_message_body_ar'] ?? '').toString().trim();
      if (!active || body.isEmpty) return;
      final title = (row['custom_message_title_ar'] ?? '')
          .toString()
          .trim();

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
                style: const TextStyle(
                  color: Color(0xFFFFF2B2),
                  height: 1.5,
                ),
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
    } catch (_) {
      // نتجاهل أي خطأ شبكة/صلاحيات حتى لا يتعطل الدخول.
    }
  }

  @override
  void dispose() {
    _stampCtrl.dispose();
    try {
      _player?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    // Responsive sizing (no hardcoded widths/heights)
    var logoW = w > 1024 ? w * 0.30 : (w > 600 ? w * 0.45 : w * 0.60);
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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/splash_bg.png'),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: const Color(0xFF071A36).withAlpha(55),
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
                                    const Color(0xFF071A36)
                                        .withValues(alpha: 0.55),
                                    const Color(0xFF071A36)
                                        .withValues(alpha: 0.18),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.55, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFB8960C)
                                        .withValues(alpha: 0.18),
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
                              color: const Color(0xFF071A36)
                                  .withValues(alpha: 0.22),
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
                                        constraints:
                                            BoxConstraints(maxWidth: logoW * 0.92),
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
                                                  color: Colors.black
                                                      .withValues(alpha: 0.35),
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
              child: FadeTransition(
                opacity: _textOpacity,
                child: Column(
                  children: [
                    SizedBox(
                      width: progressSize,
                      height: progressSize,
                      child: CircularProgressIndicator(
                        strokeWidth: (progressSize * 0.12).clamp(2.0, 4.0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFFB8960C).withOpacity(0.95),
                        ),
                      ),
                    ),
                    SizedBox(height: (progressSize * 0.35).clamp(6.0, 14.0)),
                    Text(
                      'جاري التحميل...',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: (w * 0.028).clamp(10.0, 14.0),
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
