import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/inputs/app_input.dart';
import 'forgot_password_otp_screen.dart';

class ForgotPasswordEmailScreen extends StatefulWidget {
  const ForgotPasswordEmailScreen({super.key});

  @override
  State<ForgotPasswordEmailScreen> createState() =>
      _ForgotPasswordEmailScreenState();
}

class _ForgotPasswordEmailScreenState extends State<ForgotPasswordEmailScreen> {
  static const Color _navy2 = Color(0xFF0D1F3C);
  static const Color _navyPrimary = Color(0xFF1A2340);

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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_reset_rounded, size: 46, color: _navy2),
                      const SizedBox(height: 14),
                      const Text(
                        'أدخل بريدك الإلكتروني',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _navy2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'سنرسل لك رمز تحقق إلى Gmail لإعادة تعيين رمز الدخول',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      AppInput(
                        label: ' ',
                        showLabel: false,
                        hint: 'example@domain.com',
                        controller: _emailController,
                        focusNode: _focusEmail,
                        fillColor: Colors.white,
                        cursorColor: _navy2,
                        suffixIcon: Icon(
                          Icons.email_outlined,
                          color: cs.primary,
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
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _send,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navyPrimary,
                            foregroundColor: Colors.white,
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
