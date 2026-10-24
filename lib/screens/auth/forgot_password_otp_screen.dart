import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/otp_config.dart';
import '../../providers/auth_provider.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/inputs/email_otp_boxes.dart';
import '../../widgets/secure_screen.dart';
import 'reset_password_screen.dart';

class ForgotPasswordOtpScreen extends StatefulWidget {
  const ForgotPasswordOtpScreen({super.key, required this.email});

  final String email;

  @override
  State<ForgotPasswordOtpScreen> createState() =>
      _ForgotPasswordOtpScreenState();
}

class _ForgotPasswordOtpScreenState extends State<ForgotPasswordOtpScreen> {
  static const int _digits = OtpConfig.emailOtpLength;

  final _otpBoxesKey = GlobalKey<EmailOtpBoxesState>();

  bool _busy = false;
  String? _error;

  int _resendCountdown = 60;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _otpBoxesKey.currentState?.focusFirst(),
    );
  }

  @override
  void dispose() {
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

  Future<void> _verify() async {
    final otp = (_otpBoxesKey.currentState?.value ?? '').trim();
    if (otp.length < _digits) {
      setState(
        () => _error = 'أدخل الرمز كاملاً ($_digits أرقام كما في البريد)',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final err = await auth.verifyPasswordResetOtp(
      email: widget.email,
      otp: otp,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    await nav.pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => ResetPasswordScreen(email: widget.email),
      ),
    );
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final err = await auth.sendPasswordResetOtp(widget.email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _otpBoxesKey.currentState?.clear();
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
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = kb > 0;
    final isNarrow = MediaQuery.sizeOf(context).width < 640;

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
                  Align(
                    alignment: AlignmentDirectional.center,
                    child: SingleChildScrollView(
                      padding: emailOtpScrollPadding(context),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: GlassSurface(
                          borderRadius:
                              const BorderRadius.all(Radius.circular(16)),
                          tintColor: AppGlass.surfaceTint,
                          strokeColor: AppGlass.stroke,
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            18,
                            16,
                            18,
                            16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                height:
                                    keyboardVisible && isNarrow ? 0 : null,
                                child: keyboardVisible && isNarrow
                                    ? const SizedBox.shrink()
                                    : Column(
                                        children: [
                                          const Icon(
                                            Icons.mark_email_read_outlined,
                                            size: 46,
                                            color: AppColors.accentGold,
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'أدخل رمز التحقق',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'أُرسل رمز مكوّن من $_digits أرقام إلى:\n${widget.email}',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.white
                                                  .withValues(alpha: 0.72),
                                              height: 1.5,
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                        ],
                                      ),
                              ),
                              EmailOtpBoxes(
                                key: _otpBoxesKey,
                                enabled: !_busy,
                                onChanged: (_) => setState(() => _error = null),
                                onCompleted: (_) {
                                  if (!_busy) _verify();
                                },
                              ),
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color:
                                          Colors.red.withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        size: 18,
                                        color: Colors.red.shade200,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            color: Colors.red.shade100,
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
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _busy ? null : _verify,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0D1F3C),
                                    foregroundColor: Colors.white,
                                    disabledForegroundColor: Colors.white70,
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
                                      : const Text('متابعة'),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Center(
                                child: _resendCountdown > 0
                                    ? Text(
                                        'إعادة الإرسال خلال $_resendCountdown ثانية',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white
                                              .withValues(alpha: 0.55),
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: _busy ? null : _resend,
                                        child: const Text(
                                          'إعادة إرسال الرمز',
                                          style: TextStyle(
                                            color: AppColors.accentGold,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                              ),
                              TextButton.icon(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                                label: Text(
                                  'تعديل البريد',
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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

}
