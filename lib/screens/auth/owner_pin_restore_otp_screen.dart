import 'dart:async' show Timer, unawaited;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/otp_config.dart';
import '../../providers/auth_provider.dart';
import 'reset_password_screen.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/inputs/email_otp_boxes.dart';
import '../../widgets/secure_screen.dart';

/// OTP قبل استعادة PIN المالك من السحابة على جهاز جديد (القرار 1).
class OwnerPinRestoreOtpScreen extends StatefulWidget {
  const OwnerPinRestoreOtpScreen({
    super.key,
    this.otpAlreadySent = false,
    this.initialLocalOwnerUserId,
    this.setNewPin = false,
  });

  /// `true` إذا أُرسل OTP مسبقاً من [AuthProvider.handleGoogleAuth].
  final bool otpAlreadySent;

  /// يُمرَّر من الإقلاع عند توفر صف المالك قبل ضبط [AuthProvider.userId].
  final int? initialLocalOwnerUserId;

  /// فقط زر «نسيت رمز PIN». تسجيل الدخول بحساب موجود يبقى false.
  final bool setNewPin;

  @override
  State<OwnerPinRestoreOtpScreen> createState() =>
      _OwnerPinRestoreOtpScreenState();
}

class _OwnerPinRestoreOtpScreenState extends State<OwnerPinRestoreOtpScreen> {
  static const int _digits = OtpConfig.emailOtpLength;

  final _otpBoxesKey = GlobalKey<EmailOtpBoxesState>();

  bool _busy = false;
  bool _sending = false;
  bool _resolvingOwner = true;
  int? _localOwnerUserId;
  String? _error;
  String? _ownerResolutionError;
  int _resendCountdown = 0;
  Timer? _countdownTimer;

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_resolveLocalOwner());
    if (widget.otpAlreadySent) {
      _startCountdown();
    } else {
      unawaited(_sendOtp());
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _otpBoxesKey.currentState?.focusFirst(),
    );
  }

  Future<void> _resolveLocalOwner() async {
    final presetId = widget.initialLocalOwnerUserId;
    if (presetId != null && presetId > 0) {
      if (!mounted) return;
      setState(() {
        _resolvingOwner = false;
        _localOwnerUserId = presetId;
      });
      return;
    }

    final auth = context.read<AuthProvider>();
    final row = await auth.getLocalOwnerRow();
    if (!mounted) return;
    final id = (row?['id'] as num?)?.toInt();
    setState(() {
      _resolvingOwner = false;
      _localOwnerUserId = id;
      if (id == null) {
        _ownerResolutionError =
            'تعذر تحديد حساب المالك على هذا الجهاز. '
            'ارجع وسجّل الدخول من جديد، أو جرّب من بوابة الموظفين.';
      }
    });
  }

  Future<int?> _resolveLocalOwnerUserId() async {
    if (_localOwnerUserId != null) return _localOwnerUserId;
    final auth = context.read<AuthProvider>();
    final row = await auth.getLocalOwnerRow();
    final id = (row?['id'] as num?)?.toInt();
    if (mounted && id != null) {
      setState(() => _localOwnerUserId = id);
    }
    return id;
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

  Future<void> _sendOtp() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final err = await auth.beginOwnerPinRestoreOtpFlow();
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _startCountdown();
  }

  Future<void> _verify() async {
    final otp = (_otpBoxesKey.currentState?.value ?? '').trim();
    if (otp.length < _digits) {
      setState(
        () => _error = 'أدخل الرمز كاملاً ($_digits أرقام كما في البريد)',
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final localUserId = await _resolveLocalOwnerUserId();
    if (localUserId == null) {
      setState(() {
        _error = _ownerResolutionError ??
            'تعذر تحديد حساب المالك. ارجع وسجّل الدخول من جديد.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final err = await auth.verifyOwnerPinRestoreOtpAndApply(
      localUserId: localUserId,
      otp: otp,
      setNewPin: widget.setNewPin,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }

    if (widget.setNewPin) {
      final returnToEmployeeGate = auth.deviceOwnerBound;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => ResetPasswordScreen(
            email: _email,
            returnToEmployeeGate: returnToEmployeeGate,
          ),
        ),
      );
      return;
    }

    final target = await auth.resolveRouteAfterAuthenticatedSession();
    if (!mounted) return;
    unawaited(Navigator.of(context).pushReplacementNamed(target));
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0 || _busy || _sending) return;
    await _sendOtp();
    if (!mounted || _error != null) return;
    _otpBoxesKey.currentState?.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إعادة إرسال رمز التحقق'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreen(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: GlassBackground(
          backgroundImage: const AssetImage('assets/images/splash_bg.png'),
          overlayOpacity: 0.5,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text('التحقق من الهوية'),
            ),
            body: SafeArea(
              child: Center(
                child: _resolvingOwner
                    ? const CircularProgressIndicator()
                    : _ownerResolutionError != null
                    ? Padding(
                        padding: const EdgeInsetsDirectional.all(24),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: GlassSurface(
                            borderRadius: BorderRadius.circular(20),
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 48,
                                  color: Colors.orange.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _ownerResolutionError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: () {
                                    final auth = context.read<AuthProvider>();
                                    final target = auth.deviceOwnerBound
                                        ? '/employee-gate'
                                        : '/login';
                                    Navigator.of(context)
                                        .pushReplacementNamed(target);
                                  },
                                  child: const Text('العودة لتسجيل الدخول'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                  padding: emailOtpScrollPadding(context),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: GlassSurface(
                      borderRadius: BorderRadius.circular(20),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.mark_email_read_outlined,
                            size: 48,
                            color: AppColors.accentGold,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.setNewPin
                                ? 'تحقق من بريدك لتعيين رمز PIN جديد'
                                : 'أدخل الرمز المرسل لتأكيد دخولك',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _email.isEmpty
                                ? (widget.setNewPin
                                    ? 'بعد التأكيد ستُنشئ رمزاً من 4 أرقام'
                                    : 'بعد التأكيد يُفتح الحساب مباشرة')
                                : widget.setNewPin
                                    ? 'أرسلنا رمزاً من $_digits أرقام إلى\n$_email\n'
                                        'بعد التأكيد ستُنشئ رمز PIN جديداً (4 أرقام).'
                                    : 'أرسلنا رمزاً من $_digits أرقام إلى\n$_email\n'
                                        'بعد التأكيد يُفتح الحساب مباشرة.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 24),
                          EmailOtpBoxes(
                            key: _otpBoxesKey,
                            enabled: !_busy && !_sending,
                            onChanged: (_) => setState(() => _error = null),
                            onCompleted: (_) {
                              if (!_busy && !_sending) {
                                unawaited(_verify());
                              }
                            },
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (_sending || _busy)
                            const Padding(
                              padding: EdgeInsets.only(top: 20),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.accentGold,
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: (_busy || _sending) ? null : () => unawaited(_verify()),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accentGold,
                              foregroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text(
                              'تأكيد',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: (_resendCountdown > 0 || _busy || _sending)
                                ? null
                                : () => unawaited(_resend()),
                            child: Text(
                              _resendCountdown > 0
                                  ? 'إعادة الإرسال ($_resendCountdown)'
                                  : 'إعادة إرسال الرمز',
                              style: const TextStyle(color: AppColors.accentGold),
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
}
