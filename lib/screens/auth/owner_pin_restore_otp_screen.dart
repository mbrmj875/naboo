import 'dart:async' show Timer, TimeoutException, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/otp_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/business_features_provider.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/secure_screen.dart';

/// OTP قبل استعادة PIN المالك من السحابة على جهاز جديد (القرار 1).
class OwnerPinRestoreOtpScreen extends StatefulWidget {
  const OwnerPinRestoreOtpScreen({
    super.key,
    this.otpAlreadySent = false,
    this.initialLocalOwnerUserId,
  });

  /// `true` إذا أُرسل OTP مسبقاً من [AuthProvider.handleGoogleAuth].
  final bool otpAlreadySent;

  /// يُمرَّر من الإقلاع عند توفر صف المالك قبل ضبط [AuthProvider.userId].
  final int? initialLocalOwnerUserId;

  @override
  State<OwnerPinRestoreOtpScreen> createState() =>
      _OwnerPinRestoreOtpScreenState();
}

class _OwnerPinRestoreOtpScreenState extends State<OwnerPinRestoreOtpScreen> {
  static const int _digits = OtpConfig.emailOtpLength;

  final _controllers = List.generate(_digits, (_) => TextEditingController());
  final _focusNodes = List.generate(_digits, (_) => FocusNode());

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

  String get _otp => _controllers.map((c) => c.text).join();

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
      (_) => _focusNodes.first.requestFocus(),
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
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
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
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }

    try {
      final target = await _withWorkspaceBootstrapOverlay(
        () => auth.resolveRouteAfterAuthenticatedSession(),
      );
      if (!mounted) return;
      try {
        await context.read<BusinessFeaturesProvider>().refresh();
      } catch (_) {}
      if (!mounted) return;
      unawaited(Navigator.of(context).pushReplacementNamed(target));
    } on TimeoutException {
      if (!mounted) return;
      setState(() =>
          _error = 'استغرقت تهيئة مساحة العمل وقتاً طويلاً. تحقق من الإنترنت وأعد المحاولة.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<T> _withWorkspaceBootstrapOverlay<T>(
    Future<T> Function() task, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!mounted) return task();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: const Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text('جاري تهيئة مساحة العمل…'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      return await task().timeout(timeout);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _resend() async {
    if (_resendCountdown > 0 || _busy || _sending) return;
    await _sendOtp();
    if (!mounted || _error != null) return;
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
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
                  padding: const EdgeInsetsDirectional.all(24),
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
                          const Text(
                            'أدخل الرمز المرسل إلى بريدك للتحقق من هويتك',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _email.isEmpty
                                ? 'تحقق من بريدك الإلكتروني'
                                : 'أرسلنا رمزاً من $_digits أرقام إلى\n$_email',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                const spacing = 8.0;
                                const perRow = 4;
                                final cellW =
                                    ((constraints.maxWidth -
                                                spacing * (perRow - 1)) /
                                            perRow)
                                        .clamp(36.0, 48.0);

                                Widget rowOf(int start) {
                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(perRow, (j) {
                                      final index = start + j;
                                      return Padding(
                                        padding: EdgeInsetsDirectional.only(
                                          start: j == 0 ? 0 : spacing,
                                        ),
                                        child: SizedBox(
                                          width: cellW,
                                          child: TextField(
                                            controller: _controllers[index],
                                            focusNode: _focusNodes[index],
                                            enabled: !_busy && !_sending,
                                            textAlign: TextAlign.center,
                                            keyboardType: TextInputType.number,
                                            maxLength: 1,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            inputFormatters: [
                                              FilteringTextInputFormatter
                                                  .digitsOnly,
                                            ],
                                            decoration: InputDecoration(
                                              counterText: '',
                                              filled: true,
                                              fillColor: Colors.black26,
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                borderSide: BorderSide.none,
                                              ),
                                            ),
                                            onChanged: (v) =>
                                                _onDigitChanged(index, v),
                                          ),
                                        ),
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
