import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/design_tokens.dart';
import '../../utils/auth_validators.dart';
import '../../utils/pin_input_constraints.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/inputs/pin_four_boxes_field.dart';
import '../../widgets/secure_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.email,
    this.returnToEmployeeGate = false,
  });

  final String email;

  /// بعد الحفظ: العودة إلى «من سيبدأ العمل؟» مع الإبقاء على جلسة Google.
  final bool returnToEmployeeGate;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passController = TextEditingController();
  final _confirmController = TextEditingController();
  final _focusPin = FocusNode();
  final _focusConfirm = FocusNode();

  bool _busy = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  bool get _isValidPin => AuthValidators.isValidPin(_passController.text);

  @override
  void initState() {
    super.initState();
    _passController.addListener(() => setState(() {}));
    _confirmController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusPin.requestFocus();
    });
  }

  @override
  void dispose() {
    _passController.dispose();
    _confirmController.dispose();
    _focusPin.dispose();
    _focusConfirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final err = await auth.resetLocalAndServerPassword(
      email: widget.email,
      newPassword: _passController.text,
      signOutAfterReset: !widget.returnToEmployeeGate,
    );
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
    messenger.showSnackBar(
      const SnackBar(
        content: Text('تم تحديث رمز PIN بنجاح'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (widget.returnToEmployeeGate) {
      unawaited(nav.pushReplacementNamed('/employee-gate'));
      return;
    }
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = kb > 0;
    final isNarrow = MediaQuery.sizeOf(context).width < 640;
    final confirmHasText = _confirmController.text.isNotEmpty;
    final confirmMatches = confirmHasText &&
        _passController.text.isNotEmpty &&
        _confirmController.text == _passController.text;

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
                                  height:
                                      keyboardVisible && isNarrow ? 0 : null,
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
                                              'تعيين رمز PIN جديد',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'البريد: ${widget.email}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.white
                                                    .withValues(alpha: 0.72),
                                              ),
                                            ),
                                            const SizedBox(height: 18),
                                          ],
                                        ),
                                ),
                                PinFourBoxesField(
                                  useGlass: true,
                                  controller: _passController,
                                  focusNode: _focusPin,
                                  label: 'رمز PIN *',
                                  obscureText: _obscure1,
                                  onToggleObscure: () => setState(
                                    () => _obscure1 = !_obscure1,
                                  ),
                                  textInputAction: TextInputAction.next,
                                  onCompleted: (_) => FocusScope.of(context)
                                      .requestFocus(_focusConfirm),
                                  validator: (v) {
                                    final t = (v ?? '').trim();
                                    if (t.isEmpty) return 'أدخل رمز الدخول';
                                    if (!AuthValidators.isValidPin(t)) {
                                      return PinInputConstraints.invalidMessage;
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),
                                PinFourBoxesField(
                                  useGlass: true,
                                  controller: _confirmController,
                                  focusNode: _focusConfirm,
                                  label: 'تأكيد رمز PIN *',
                                  obscureText: _obscure2,
                                  onToggleObscure: () => setState(
                                    () => _obscure2 = !_obscure2,
                                  ),
                                  textInputAction: TextInputAction.done,
                                  onCompleted: (_) {
                                    if (!_busy &&
                                        _isValidPin &&
                                        confirmMatches) {
                                      _save();
                                    }
                                  },
                                  validator: (v) {
                                    final t = (v ?? '').trim();
                                    if (t.isEmpty) {
                                      return 'أعد كتابة رمز الدخول';
                                    }
                                    if (t != _passController.text.trim()) {
                                      return PinInputConstraints
                                          .mismatchMessage;
                                    }
                                    return null;
                                  },
                                ),
                                if (confirmHasText && !confirmMatches) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    PinInputConstraints.mismatchMessage,
                                    style: TextStyle(
                                      color: Colors.red.shade200,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _requirements(),
                                const SizedBox(height: 18),
                                SizedBox(
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: _busy ? null : _save,
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
                                        : const Text('حفظ'),
                                  ),
                                ),
                              ],
                            ),
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

  Widget _requirements() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(
            _isValidPin ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: _isValidPin
                ? Colors.greenAccent.shade200
                : Colors.white.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'يتكون من 4 أرقام',
              style: TextStyle(
                fontSize: 12,
                color: _isValidPin
                    ? Colors.greenAccent.shade200
                    : Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
