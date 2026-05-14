import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/inputs/app_input.dart';
import 'forgot_password_otp_screen.dart';

class ForgotPasswordEmailScreen extends StatefulWidget {
  const ForgotPasswordEmailScreen({super.key});

  @override
  State<ForgotPasswordEmailScreen> createState() =>
      _ForgotPasswordEmailScreenState();
}

class _ForgotPasswordEmailScreenState extends State<ForgotPasswordEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _focusEmail = FocusNode();
  bool _busy = false;
  bool _blurredEmail = false;

  @override
  void initState() {
    super.initState();
    _focusEmail.addListener(_emailFocusTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusEmail.requestFocus();
    });
  }

  void _emailFocusTick() {
    if (!_focusEmail.hasFocus && mounted) {
      setState(() => _blurredEmail = true);
    }
  }

  @override
  void dispose() {
    _focusEmail.removeListener(_emailFocusTick);
    _focusEmail.dispose();
    _emailController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final t = (value ?? '').trim();
    if (!_blurredEmail) return null;
    if (t.isEmpty) return 'البريد الإلكتروني مطلوب';
    final ok = RegExp(r'^[^\s]+@[^\s]+\.[^\s]+$').hasMatch(t);
    return ok ? null : 'صيغة البريد غير صحيحة';
  }

  Future<void> _send() async {
    setState(() => _blurredEmail = true);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final email = _emailController.text.trim();
    final err = await auth.sendPasswordResetOtp(email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ForgotPasswordOtpScreen(email: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = kb > 0;
    final w = MediaQuery.sizeOf(context).width;
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

    return Theme(
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
                    padding: EdgeInsetsDirectional.fromSTEB(
                      20,
                      18,
                      20,
                      24 + kb,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Form(
                        key: _formKey,
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
                                height: keyboardVisible && isNarrow ? 0 : null,
                                child: keyboardVisible && isNarrow
                                    ? const SizedBox.shrink()
                                    : Column(
                                        children: [
                                          const Icon(
                                            Icons.lock_reset_rounded,
                                            size: 46,
                                            color: AppColors.accentGold,
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'أدخل بريدك الإلكتروني',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'سنرسل لك رمز تحقق لإعادة تعيين رمز الدخول',
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
                              AppInput(
                                label: ' ',
                                showLabel: false,
                                hint: 'example@domain.com',
                                controller: _emailController,
                                focusNode: _focusEmail,
                                useGlass: true,
                                cursorColor: Colors.white,
                                suffixIcon: Icon(
                                  Icons.email_outlined,
                                  color: cs.onSurface.withValues(alpha: 0.82),
                                  size: 20,
                                ),
                                keyboardType: TextInputType.emailAddress,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.start,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) {
                                  if (!_busy) _send();
                                },
                                validator: _validateEmail,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 52,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF071A36),
                                        Color(0xFF0D1F3C),
                                      ],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.28,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: _busy ? null : _send,
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
                                        : const Text('إرسال رمز التحقق'),
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
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: IconButton(
                    tooltip: 'رجوع',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
