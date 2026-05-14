import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/design_tokens.dart';
import '../../services/app_settings_repository.dart';
import '../../services/business_setup_settings.dart';
import '../../services/license_service.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/secure_screen.dart';
import '../license/subscription_plans_screen.dart';

class EmailOtpScreen extends StatefulWidget {
  const EmailOtpScreen({
    super.key,
    required this.email,
    required this.displayName,
    required this.phone,
    required this.password,
  });

  final String email;
  final String displayName;
  final String phone;
  final String password;

  @override
  State<EmailOtpScreen> createState() => _EmailOtpScreenState();
}

class _EmailOtpScreenState extends State<EmailOtpScreen> {
  /// يطابق إعداد Supabase الافتراضي لقوالب البريد (غالباً 8 أرقام).
  static const int _digits = 8;

  final _controllers = List.generate(_digits, (_) => TextEditingController());
  final _focusNodes = List.generate(_digits, (_) => FocusNode());

  bool _busy = false;
  String? _error;

  // Resend countdown
  int _resendCountdown = 60;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNodes.first.requestFocus(),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _resendCountdown = 60;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  String get _otp => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty) {
      if (index < _digits - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }
    setState(() => _error = null);
  }

  Future<void> _verify() async {
    final otp = _otp.trim();
    if (otp.length < _digits) {
      setState(() => _error = 'أدخل الرمز كاملاً ($_digits أرقام كما في البريد)');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final err = await auth.verifyOtpAndRegister(
      email: widget.email,
      otp: otp,
      displayName: widget.displayName,
      phone: widget.phone,
      password: widget.password,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    var target = '/open-shift';
    try {
      final completed = await BusinessSetupSettingsData.isCompleted(
        AppSettingsRepository.instance,
      );
      if (!completed) target = '/onboarding';
    } catch (_) {}
    unawaited(nav.pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionPlansScreen(
          currentPlan: LicenseService.instance.state.plan,
          nextRouteName: target,
        ),
      ),
    ));
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final err = await auth.sendEmailOtp(widget.email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    _startCountdown();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إعادة إرسال رمز التحقق'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isWide = w >= 760;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = kb > 0;
    final isNarrow = w < 640;

    final base = Theme.of(context);
    final glassAuthTheme = base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        primary: AppColors.accentBlue,
        secondary: AppColors.accentGold,
        surface: AppColors.primary,
        onSurface: Colors.white,
        onSurfaceVariant: Colors.white.withValues(alpha: 0.72),
        outline: AppGlass.stroke,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: AppColors.primaryDark.withValues(alpha: 0.95),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );

    final card = _contentCard(
      context,
      keyboardVisible: keyboardVisible,
      isNarrow: isNarrow,
      bottomInset: kb,
    );

    return SecureScreen(
      child: Theme(
      data: glassAuthTheme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GlassBackground(
          backgroundImage: const AssetImage('assets/images/splash_bg.png'),
          child: SafeArea(
            child: Stack(
              children: [
                isWide
                    ? Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _headerSide(
                              collapsed: false,
                              isNarrow: false,
                            ),
                          ),
                          Expanded(flex: 6, child: card),
                        ],
                      )
                    : Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            height: keyboardVisible ? 120 : 210,
                            width: double.infinity,
                            child: _headerSide(
                              collapsed: keyboardVisible,
                              isNarrow: true,
                            ),
                          ),
                          Expanded(child: card),
                        ],
                      ),
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: IconButton(
                    tooltip: 'رجوع',
                    onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _headerSide({required bool collapsed, required bool isNarrow}) {
    final iconSize = isNarrow ? (collapsed ? 34.0 : 52.0) : 72.0;
    final titleSize = isNarrow ? (collapsed ? 18.0 : 20.0) : 24.0;

    return Center(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          top: isNarrow ? (collapsed ? 8 : 18) : 0,
          start: isNarrow ? 16 : 32,
          end: isNarrow ? 16 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mark_email_read_rounded,
              size: iconSize,
              color: AppColors.accentGold,
            ),
            SizedBox(height: collapsed ? 6 : 10),
            Text(
              'التحقق من البريد',
              style: TextStyle(
                color: Colors.white,
                fontSize: titleSize,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(height: 10),
              Text(
                'أرسلنا رمزاً من $_digits أرقام إلى بريدك الإلكتروني',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _contentCard(
    BuildContext context, {
    required bool keyboardVisible,
    required bool isNarrow,
    required double bottomInset,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(
          20,
          18,
          20,
          24 + bottomInset,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: GlassSurface(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            tintColor: AppGlass.surfaceTint,
            strokeColor: AppGlass.stroke,
            padding: const EdgeInsetsDirectional.fromSTEB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!(keyboardVisible && isNarrow)) ...[
                  const Text(
                    'أدخل رمز التحقق',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'أُرسل رمز مكوّن من $_digits أرقام إلى\n${widget.email}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.72),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = 8.0;
                      const height = 54.0;

                      // Try single-row first.
                      final maxW = constraints.maxWidth;
                      final cellW1 =
                          (maxW - spacing * (_digits - 1)) / _digits;
                      final canFitOneRow = cellW1 >= 34;

                      if (canFitOneRow) {
                        final cellW = cellW1.clamp(34.0, 46.0);
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(_digits, (i) {
                            return Padding(
                              padding: EdgeInsetsDirectional.only(
                                start: i == 0 ? 0 : spacing,
                              ),
                              child: _otpBox(i, width: cellW, height: height),
                            );
                          }),
                        );
                      }

                      // Fallback: 2 rows (4 + 4) — always balanced.
                      const perRow = 4;
                      final cellW2 =
                          (maxW - spacing * (perRow - 1)) / perRow;
                      final cellW = cellW2.clamp(34.0, 54.0);

                      Widget rowOf(int start) {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(perRow, (j) {
                            final i = start + j;
                            return Padding(
                              padding: EdgeInsetsDirectional.only(
                                start: j == 0 ? 0 : spacing,
                              ),
                              child: _otpBox(i, width: cellW, height: height),
                            );
                          }),
                        );
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          rowOf(0),
                          const SizedBox(height: 12),
                          rowOf(perRow),
                        ],
                      );
                    },
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: const Color(0x33EF4444),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x55EF4444)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: Color(0xFFEF4444),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFFFE4E6),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF071A36), Color(0xFF0D1F3C)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _busy ? null : _verify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'تحقق وأنشئ الحساب',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: _resendCountdown > 0
                      ? Text(
                          'إعادة الإرسال خلال $_resendCountdown ثانية',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.60),
                          ),
                        )
                      : TextButton(
                          onPressed: _busy ? null : _resend,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.accentGold,
                          ),
                          child: const Text(
                            'إعادة إرسال الرمز',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: cs.onSurface.withValues(alpha: 0.80),
                  ),
                  label: Text(
                    'تعديل البيانات',
                    style: TextStyle(color: cs.onSurface.withValues(alpha: 0.80)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int index, {required double width, required double height}) {
    final isActive = _focusNodes[index].hasFocus;
    final hasFill = _controllers[index].text.isNotEmpty;
    return SizedBox(
      width: width,
      height: height,
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) {
          if (event is RawKeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.backspace) {
            if (_controllers[index].text.isEmpty && index > 0) {
              _controllers[index - 1].clear();
              _focusNodes[index - 1].requestFocus();
            }
          }
        },
        child: TextField(
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor:
                hasFill ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.06),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isActive
                    ? AppColors.accentGold
                    : Colors.white.withValues(alpha: 0.18),
                width: isActive ? 2 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasFill
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.18),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.accentGold,
                width: 2,
              ),
            ),
          ),
          onChanged: (v) => _onDigitChanged(index, v),
        ),
      ),
    );
  }
}
