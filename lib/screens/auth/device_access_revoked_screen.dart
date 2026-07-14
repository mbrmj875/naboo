import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../services/cloud_sync_service.dart';

const _kBg = Color(0xFF0F172A);
const _kCard = Color(0xFF1E293B);
const _kCardBorder = Color(0xFF334155);
const _kTeal = Color(0xFF0D9488);
const _kGold = Color(0xFFF59E0B);
const _kGoldLight = Color(0xFFFDE68A);
const _kTextPrimary = Color(0xFFF8FAFC);
const _kTextMuted = Color(0xFF94A3B8);

/// يُعرض عندما يكون هذا الجهاز `revoked` في [account_devices].
class DeviceAccessRevokedScreen extends StatefulWidget {
  const DeviceAccessRevokedScreen({super.key});

  @override
  State<DeviceAccessRevokedScreen> createState() =>
      _DeviceAccessRevokedScreenState();
}

class _DeviceAccessRevokedScreenState extends State<DeviceAccessRevokedScreen> {
  static const int _otpDigits = 8;

  bool _retryBusy = false;
  bool _otpSent = false;
  bool _otpBusy = false;
  String? _otpError;
  int _resendCountdown = 0;
  Timer? _countdownTimer;

  late final TextEditingController _emailController;
  late final List<TextEditingController> _otpControllers;
  late final List<FocusNode> _otpFocusNodes;

  @override
  void initState() {
    super.initState();
    final cloudEmail =
        Supabase.instance.client.auth.currentUser?.email?.trim() ?? '';
    _emailController = TextEditingController(text: cloudEmail);
    _otpControllers = List.generate(_otpDigits, (_) => TextEditingController());
    _otpFocusNodes = List.generate(_otpDigits, (_) => FocusNode());
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otp => _otpControllers.map((c) => c.text).join();

  void _startResendCountdown() {
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

  void _clearOtpFields() {
    for (final c in _otpControllers) {
      c.clear();
    }
    _otpFocusNodes.first.requestFocus();
  }

  Future<void> _navigateAfterRecovery() async {
    final auth = context.read<AuthProvider>();
    final target = await auth.resolveRouteAfterAuthenticatedSession();
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushNamedAndRemoveUntil(target, (_) => false),
    );
  }

  Future<void> _retryAccess() async {
    if (_retryBusy) return;
    setState(() => _retryBusy = true);
    try {
      final auth = context.read<AuthProvider>();
      final ok = await auth.retryDeviceAccessRegistration();
      if (!mounted) return;
      if (ok) {
        await _navigateAfterRecovery();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ما زال هذا الجهاز مفصولاً. اطلب السماح من جهاز نشط '
            'أو استخدم استعادة البريد أدناه.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _retryBusy = false);
    }
  }

  Future<void> _sendRecoveryOtp({bool isResend = false}) async {
    if (_otpBusy) return;
    if (isResend && _resendCountdown > 0) return;

    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _otpError = 'أدخل بريد صاحب الحساب (Gmail) الصحيح.');
      return;
    }
    setState(() {
      _otpBusy = true;
      _otpError = null;
    });
    final err = await context.read<AuthProvider>().sendDeviceAccessRecoveryOtp(
          email: email,
        );
    if (!mounted) return;
    setState(() {
      _otpBusy = false;
      if (err == null) {
        _otpSent = true;
        _startResendCountdown();
        if (isResend) _clearOtpFields();
      } else {
        _otpError = err;
      }
    });
    if (err == null && mounted) {
      _otpFocusNodes.first.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isResend
                ? 'تم إعادة إرسال رمز التحقق'
                : 'تم إرسال رمز التحقق إلى بريدك',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _confirmOwnerEmailRecovery() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد استعادة صاحب العمل'),
          content: const Text(
            'سيتم تفعيل هذا الجهاز وفصل جميع الأجهزة الأخرى المرتبطة '
            'بالحساب (مثل جهاز موظف سابق).\n\n'
            'تأكد أنك صاحب الحساب وأن لديك وصولاً إلى البريد.',
            style: TextStyle(height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _verifyRecoveryOtp() async {
    if (_otpBusy) return;
    final otp = _otp.trim();
    if (otp.length < _otpDigits) {
      setState(
        () => _otpError =
            'أدخل الرمز كاملاً ($_otpDigits أرقام كما في البريد)',
      );
      return;
    }
    final confirmed = await _confirmOwnerEmailRecovery();
    if (!confirmed || !mounted) return;

    setState(() {
      _otpBusy = true;
      _otpError = null;
    });
    final auth = context.read<AuthProvider>();
    final err = await auth.recoverDeviceAccessViaEmailOtp(
      email: _emailController.text.trim().toLowerCase(),
      otp: otp,
      revokeOtherDevices: true,
    );
    if (!mounted) return;
    setState(() => _otpBusy = false);
    if (err != null) {
      setState(() => _otpError = err);
      return;
    }
    await _navigateAfterRecovery();
  }

  Future<void> _signOutCompletely() async {
    final auth = context.read<AuthProvider>();
    await auth.abandonRevokedDeviceSession();
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false),
    );
  }

  void _onOtpDigitChanged(int index, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      _applyPastedOtp(digits, startIndex: index);
      return;
    }
    if (digits.isNotEmpty && index < _otpDigits - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    setState(() => _otpError = null);
  }

  void _applyPastedOtp(String raw, {required int startIndex}) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    var i = startIndex;
    for (final ch in digits.split('')) {
      if (i >= _otpDigits) break;
      _otpControllers[i].text = ch;
      i++;
    }
    if (i < _otpDigits) {
      _otpFocusNodes[i].requestFocus();
    } else {
      _otpFocusNodes.last.unfocus();
    }
    setState(() => _otpError = null);
  }

  Widget _otpBox(int index, {required double width, required double height}) {
    final focused = _otpFocusNodes[index].hasFocus;
    final filled = _otpControllers[index].text.isNotEmpty;
    return SizedBox(
      width: width,
      height: height,
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _otpFocusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: const TextStyle(
          color: _kTextPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
        decoration: InputDecoration(
          filled: true,
          fillColor: filled
              ? _kGold.withValues(alpha: 0.12)
              : const Color(0xFF334155),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: focused ? _kGold : _kCardBorder,
              width: focused ? 2 : 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: filled ? _kGold.withValues(alpha: 0.5) : _kCardBorder,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _kGold, width: 2),
          ),
        ),
        onChanged: (v) => _onOtpDigitChanged(index, v),
      ),
    );
  }

  Widget _otpGrid() {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 8.0;
          const height = 52.0;
          const perRow = 4;
          final maxW = constraints.maxWidth;
          final cellW = ((maxW - spacing * (perRow - 1)) / perRow).clamp(36.0, 52.0);

          Widget rowOf(int start) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(perRow, (j) {
                final i = start + j;
                return Padding(
                  padding: EdgeInsetsDirectional.only(start: j == 0 ? 0 : spacing),
                  child: _otpBox(i, width: cellW, height: height),
                );
              }),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              rowOf(0),
              const SizedBox(height: 10),
              rowOf(4),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color accent,
    required List<Widget> children,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kCardBorder),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _kTextPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _stepLabel(String number, String text) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kTeal.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: _kTeal,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0x33EF4444),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x55EF4444)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFFFCA5A5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFCA5A5),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResendRow() {
    final canResend = _resendCountdown <= 0 && !_otpBusy;
    return Row(
      children: [
        Expanded(
          child: Text(
            _resendCountdown > 0
                ? 'يمكنك إعادة الإرسال خلال $_resendCountdown ث'
                : 'لم يصل الرمز؟ تحقق من «البريد غير المرغوب»',
            style: const TextStyle(
              color: _kTextMuted,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: canResend ? () => _sendRecoveryOtp(isResend: true) : null,
          icon: _otpBusy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('إعادة إرسال الرمز'),
          style: OutlinedButton.styleFrom(
            foregroundColor: canResend ? _kGoldLight : _kTextMuted,
            side: BorderSide(
              color: canResend ? _kGold : _kCardBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final busy = _retryBusy || _otpBusy;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: _kTextPrimary,
          title: const Text(
            'طلب السماح بالعودة',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.phonelink_lock_rounded,
                      size: 64,
                      color: Color(0xFFFB923C),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'هذا الجهاز مفصول من الحساب',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _kTextPrimary,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'اختر إحدى الطريقتين أدناه لاستعادة الدخول',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionCard(
                      title: 'من جهاز نشط آخر',
                      icon: Icons.devices_other_outlined,
                      accent: _kTeal,
                      children: [
                        _stepLabel(
                          '١',
                          'افتح التطبيق على جهاز ما زال نشطاً.',
                        ),
                        _stepLabel(
                          '٢',
                          'الحساب والاشتراك ← «السماح بالعودة» لهذا الجهاز.',
                        ),
                        _stepLabel('٣', 'ارجع هنا واضغط «إعادة المحاولة».'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: busy ? null : _retryAccess,
                          icon: _retryBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: Text(
                            _retryBusy ? 'جاري التحقق…' : 'إعادة المحاولة',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: _kTeal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => unawaited(
                                    CloudSyncService.instance.refreshDevices(),
                                  ),
                          icon: const Icon(Icons.sync, size: 18),
                          label: const Text('تحديث قائمة الأجهزة'),
                          style: TextButton.styleFrom(
                            foregroundColor: _kTextMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionCard(
                      title: 'استعادة صاحب العمل بالبريد',
                      icon: Icons.mail_lock_outlined,
                      accent: _kGold,
                      children: [
                        Text(
                          'عندما لا تصل لجهاز نشط (مثل بعد طرد موظف). '
                          'يُرسل رمز $_otpDigits أرقام إلى Gmail صاحب الحساب.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _emailController,
                          readOnly: _otpSent,
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: _kTextPrimary),
                          decoration: InputDecoration(
                            labelText: 'بريد صاحب الحساب',
                            labelStyle: const TextStyle(color: _kTextMuted),
                            prefixIcon: const Icon(
                              Icons.alternate_email,
                              color: _kTextMuted,
                              size: 20,
                            ),
                            filled: true,
                            fillColor: const Color(0xFF334155),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!_otpSent) ...[
                          FilledButton.icon(
                            onPressed: busy ? null : () => _sendRecoveryOtp(),
                            icon: const Icon(Icons.send_rounded),
                            label: Text(
                              _otpBusy ? 'جاري الإرسال…' : 'إرسال رمز التحقق',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: _kGold,
                              foregroundColor: const Color(0xFF1E293B),
                            ),
                          ),
                          if (_otpError != null) ...[
                            const SizedBox(height: 10),
                            _errorBanner(_otpError!),
                          ],
                        ] else ...[
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFF334155).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _kCardBorder),
                            ),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                14,
                                14,
                                14,
                                14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'أدخل الرمز المرسل إلى',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _emailController.text,
                                    textDirection: TextDirection.ltr,
                                    textAlign: TextAlign.start,
                                    style: const TextStyle(
                                      color: _kGoldLight,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'استخدم آخر بريد وصل (موضوع: «رمز الدخول» أو «تأكيد التسجيل»). '
                                    'الرمز صالح 60 دقيقة.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.55),
                                      fontSize: 11,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _otpGrid(),
                                  const SizedBox(height: 14),
                                  _buildResendRow(),
                                ],
                              ),
                            ),
                          ),
                          if (_otpError != null) ...[
                            const SizedBox(height: 10),
                            _errorBanner(_otpError!),
                          ],
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: busy ? null : _verifyRecoveryOtp,
                            icon: _otpBusy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF1E293B),
                                    ),
                                  )
                                : const Icon(Icons.verified_user_outlined),
                            label: Text(
                              _otpBusy
                                  ? 'جاري التحقق…'
                                  : 'تأكيد واستعادة الحساب',
                            ),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              backgroundColor: _kGold,
                              foregroundColor: const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () {
                                    setState(() {
                                      _otpSent = false;
                                      _otpError = null;
                                      _resendCountdown = 0;
                                      _countdownTimer?.cancel();
                                    });
                                    _clearOtpFields();
                                  },
                            child: const Text(
                              'تعديل البريد',
                              style: TextStyle(color: _kTextMuted),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: busy ? null : _signOutCompletely,
                      child: const Text(
                        'خروج من الحساب على هذا الجهاز',
                        style: TextStyle(color: Color(0xFFFCA5A5)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
