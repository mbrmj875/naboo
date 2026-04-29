import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/app_settings_repository.dart';
import '../../services/business_setup_settings.dart';
import '../../services/license_service.dart';
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
  static const Color _navy1 = Color(0xFF050A14);
  static const Color _navy2 = Color(0xFF0D1F3C);
  static const Color _navy3 = Color(0xFF1A3A6B);
  static const Color _gold = Color(0xFFB8960C);

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
    nav.pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionPlansScreen(
          currentPlan: LicenseService.instance.state.plan,
          nextRouteName: target,
        ),
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
    final isWide = MediaQuery.of(context).size.width >= 760;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _navy1,
        body: isWide
            ? Row(
                children: [
                  Expanded(flex: 5, child: _brandPanel()),
                  Expanded(flex: 6, child: _contentPanel()),
                ],
              )
            : Column(
                children: [
                  _brandPanelNarrow(),
                  Expanded(child: _contentPanel()),
                ],
              ),
      ),
    );
  }

  Widget _brandPanel() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy1, _navy2, _navy3],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_read_rounded,
                size: 72, color: _gold),
            const SizedBox(height: 20),
            const Text(
              'التحقق من البريد',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'أرسلنا رمزاً من $_digits أرقام إلى بريدك الإلكتروني',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _brandPanelNarrow() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy1, _navy2, _navy3],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_rounded, size: 52, color: _gold),
            SizedBox(height: 10),
            Text(
              'التحقق من البريد',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contentPanel() {
    return Container(
      color: const Color(0xFFF7F8FA),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'أدخل رمز التحقق',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _navy2,
                  ),
                ),
                const SizedBox(height: 10),
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(
                          text: 'أُرسل رمز مكوّن من $_digits أرقام إلى\n'),
                      TextSpan(
                        text: widget.email,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _navy3,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 8,
                    children: List.generate(_digits, (i) => _otpBox(i)),
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
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 18, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _verify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy2,
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
                        : const Text(
                            'تحقق وأنشئ الحساب',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: _resendCountdown > 0
                      ? Text(
                          'إعادة الإرسال خلال $_resendCountdown ثانية',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        )
                      : TextButton(
                          onPressed: _busy ? null : _resend,
                          child: const Text(
                            'إعادة إرسال الرمز',
                            style: TextStyle(
                              color: _gold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_forward_rounded,
                      size: 16, color: _navy3),
                  label: const Text(
                    'تعديل البيانات',
                    style: TextStyle(color: _navy3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _otpBox(int index) {
    final isActive = _focusNodes[index].hasFocus;
    final hasFill = _controllers[index].text.isNotEmpty;
    return SizedBox(
      width: 40,
      height: 54,
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
            color: _navy2,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: hasFill
                ? _navy2.withValues(alpha: 0.06)
                : Colors.white,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(
                color: isActive ? _gold : Colors.grey.shade300,
                width: isActive ? 2 : 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(
                color: hasFill ? _navy3 : Colors.grey.shade300,
              ),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: _gold, width: 2),
            ),
          ),
          onChanged: (v) => _onDigitChanged(index, v),
        ),
      ),
    );
  }
}
