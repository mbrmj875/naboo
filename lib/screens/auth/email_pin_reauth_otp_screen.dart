import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/otp_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/business_features_provider.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_logger.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/secure_screen.dart';

/// تأكيد البريد عند إعادة الدخول بـ PIN على جهاز بلا جلسة محلية محفوظة.
class EmailPinReauthOtpScreen extends StatefulWidget {
  const EmailPinReauthOtpScreen({super.key, required this.email});

  final String email;

  @override
  State<EmailPinReauthOtpScreen> createState() =>
      _EmailPinReauthOtpScreenState();
}

class _EmailPinReauthOtpScreenState extends State<EmailPinReauthOtpScreen> {
  static const int _digits = OtpConfig.emailOtpLength;

  final _controllers = List.generate(_digits, (_) => TextEditingController());
  final _focusNodes = List.generate(_digits, (_) => FocusNode());

  bool _busy = false;
  String? _error;
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
    final err = await auth.completeEmailPinLoginAfterOtp(otp: otp);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    try {
      await context.read<BusinessFeaturesProvider>().refresh();
    } catch (e, st) {
      AppLogger.error('EmailPinReauth', 'refresh features failed', e, st);
    }
    if (!mounted) return;
    final target = await auth.resolveRouteAfterAuthenticatedSession();
    if (!mounted) return;
    setState(() => _busy = false);
    unawaited(nav.pushNamedAndRemoveUntil(target, (r) => false));
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AuthProvider>().resendEmailPinReauthOtp();
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
              child: Align(
                alignment: AlignmentDirectional.center,
                child: SingleChildScrollView(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    20,
                    18,
                    20,
                    24 + kb,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: GlassSurface(
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
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
                            height: keyboardVisible && isNarrow ? 0 : null,
                            child: keyboardVisible && isNarrow
                                ? const SizedBox.shrink()
                                : Column(
                                    children: [
                                      const Icon(
                                        Icons.verified_user_outlined,
                                        size: 46,
                                        color: AppColors.accentGold,
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'تأكيد الدخول',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'تأكيد هذا الجهاز برمز أُرسل إلى:\n${widget.email}\nبعدها يُستخدم البريد ورمز PIN للدخول مباشرة.',
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
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                const gap = 6.0;
                                final cellW = ((constraints.maxWidth -
                                            (gap * (_digits - 1))) /
                                        _digits)
                                    .clamp(28.0, 44.0);
                                return Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: gap,
                                  runSpacing: 8,
                                  children: List.generate(
                                    _digits,
                                    (i) => _otpBox(i, width: cellW),
                                  ),
                                );
                              },
                            ),
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
                                  color: Colors.red.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.red.shade100,
                                  fontSize: 13,
                                ),
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
                                  : const Text('تأكيد ودخول'),
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
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    context
                                        .read<AuthProvider>()
                                        .clearPendingEmailReauth();
                                    Navigator.of(context).pop();
                                  },
                            child: Text(
                              'رجوع',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int index, {required double width}) {
    final isActive = _focusNodes[index].hasFocus;
    final hasFill = _controllers[index].text.isNotEmpty;
    return SizedBox(
      width: width,
      height: 52,
      child: KeyboardListener(
        focusNode: FocusNode(skipTraversal: true, canRequestFocus: false),
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
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
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          cursorColor: AppColors.accentGold,
          decoration: InputDecoration(
            filled: true,
            fillColor: hasFill
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.06),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isActive
                    ? AppColors.accentGold
                    : Colors.white.withValues(alpha: 0.22),
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
