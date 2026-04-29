import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static const Color _navy2 = Color(0xFF0D1F3C);
  static const Color _gold = Color(0xFFB8960C);

  final _formKey = GlobalKey<FormState>();
  final _passController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _busy = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  bool get _hasMinLength => _passController.text.length >= 8;
  bool get _hasUppercase => RegExp(r'[A-Z]').hasMatch(_passController.text);
  bool get _hasLowercase => RegExp(r'[a-z]').hasMatch(_passController.text);
  bool get _hasDigit => RegExp(r'[0-9]').hasMatch(_passController.text);
  bool get _hasSpecialChar => RegExp(
        r'[!@#\$%\^&\*\(\)_\+\-\=\[\]\{\};:,.<>\/\?\\|`~]',
      ).hasMatch(_passController.text);

  @override
  void dispose() {
    _passController.dispose();
    _confirmController.dispose();
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
        content: Text('تم تحديث رمز الدخول بنجاح'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final confirmHasText = _confirmController.text.isNotEmpty;
    final confirmMatches = confirmHasText &&
        _passController.text.isNotEmpty &&
        _confirmController.text == _passController.text;
    final confirmBorderColor = !confirmHasText
        ? Colors.grey.shade300
        : (confirmMatches ? Colors.green.shade600 : Colors.red.shade600);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _navy2,
          elevation: 0.5,
          title: const Text('تعيين رمز دخول جديد'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'البريد: ${widget.email}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _label('رمز الدخول الجديد'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passController,
                      obscureText: _obscure1,
                      textDirection: TextDirection.ltr,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: _navy2, fontSize: 14),
                      cursorColor: _navy2,
                      decoration: _dec(
                        'أدخل رمز الدخول الجديد',
                        Icons.lock_outline_rounded,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure1
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                          onPressed: () => setState(() => _obscure1 = !_obscure1),
                        ),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'أدخل رمز الدخول';
                        if (t.length < 8) return 'يجب أن يكون 8 أحرف على الأقل';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _label('إعادة كتابة رمز الدخول'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscure2,
                      textDirection: TextDirection.ltr,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(color: _navy2, fontSize: 14),
                      cursorColor: _navy2,
                      decoration: _dec(
                        'أعد كتابة رمز الدخول',
                        Icons.lock_outline_rounded,
                        borderColor: confirmBorderColor,
                        focusedBorderColor: confirmBorderColor,
                        suffix: SizedBox(
                          width: 96,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (confirmHasText)
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: confirmMatches
                                        ? Colors.green.shade600
                                        : Colors.red.shade600,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    confirmMatches ? Icons.check : Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              const Spacer(),
                              IconButton(
                                icon: Icon(
                                  _obscure2
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure2 = !_obscure2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      validator: (v) {
                        final t = (v ?? '');
                        if (t.trim().isEmpty) return 'أعد كتابة رمز الدخول';
                        if (t != _passController.text) return 'رمز الدخول غير متطابق';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _requirements(),
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _save,
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
    );
  }

  Widget _requirements() {
    Widget item(String text, bool ok) => Row(
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: ok ? Colors.green.shade700 : Colors.grey.shade500,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: ok ? Colors.green.shade700 : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'شروط رمز الدخول (اختياري)',
            style: TextStyle(fontWeight: FontWeight.bold, color: _navy2),
          ),
          const SizedBox(height: 8),
          item('8 أحرف على الأقل', _hasMinLength),
          item('حرف كبير (A-Z)', _hasUppercase),
          item('حرف صغير (a-z)', _hasLowercase),
          item('رقم (0-9)', _hasDigit),
          item('رمز خاص (!@#...)', _hasSpecialChar),
        ],
      ),
    );
  }

  Widget _label(String t) => Text(
        t,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: _navy2,
        ),
      );

  InputDecoration _dec(
    String hint,
    IconData icon, {
    Widget? suffix,
    Color? fillColor,
    Color? borderColor,
    Color? focusedBorderColor,
  }) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: fillColor ?? Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: borderColor ?? Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: borderColor ?? Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: focusedBorderColor ?? _gold, width: 2),
        ),
      );
}


