import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/cloud_sync_service.dart';
import '../widgets/app_brand_mark.dart';
import 'auth/device_revoked_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _loginFormKey = GlobalKey<FormState>();
  final _signupFormKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _confirmSignupPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isSignUpMode = false;
  bool _obscurePassword = true;
  bool _obscureSignupPassword = true;
  bool _obscureConfirmSignupPassword = true;
  String _dialCode = '+964';

  late AnimationController _animController;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;

  static const Color _navy1 = Color(0xFF050A14);
  static const Color _navy2 = Color(0xFF0D1F3C);
  static const Color _navy3 = Color(0xFF1A3A6B);
  static const Color _gold = Color(0xFFB8960C);

  bool get _hasMinLength => _signupPasswordController.text.length >= 8;
  bool get _hasUppercase =>
      RegExp(r'[A-Z]').hasMatch(_signupPasswordController.text);
  bool get _hasLowercase =>
      RegExp(r'[a-z]').hasMatch(_signupPasswordController.text);
  bool get _hasDigit =>
      RegExp(r'[0-9]').hasMatch(_signupPasswordController.text);
  bool get _hasSpecialChar => RegExp(
    r'[!@#\$%\^&\*\(\)_\+\-\=\[\]\{\};:,.<>\/\?\\|`~]',
  ).hasMatch(_signupPasswordController.text);
  bool get _passwordsMatch =>
      _confirmSignupPasswordController.text.isNotEmpty &&
      _confirmSignupPasswordController.text == _signupPasswordController.text;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _slideAnim = Tween<double>(
      begin: 30,
      end: 0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _signupPasswordController.dispose();
    _confirmSignupPasswordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isSignUpMode = !_isSignUpMode;
    });
  }

  Future<void> _login() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final success = await auth.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (success) {
      nav.pushReplacementNamed('/open-shift');
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: const Text('اسم المستخدم أو رمز الدخول غير صحيح'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _signup() async {
    if (!_signupFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final err = await auth.register(
      displayName: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: '$_dialCode${_phoneController.text.trim()}',
      password: _signupPasswordController.text,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
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
      SnackBar(
        content: Text(
          auth.isAdmin
              ? 'تم إنشاء حساب المدير الأول وتسجيل الدخول'
              : 'تم إنشاء الحساب وتسجيل الدخول',
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
    nav.pushReplacementNamed('/open-shift');
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final err = await auth.signInWithGoogle();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (err != null) {
      if (err == kDeviceAccessRevokedCode) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const DeviceRevokedScreen(),
          ),
        );
        return;
      }
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
      SnackBar(
        content: Text(
          auth.isAdmin
              ? 'تم تسجيل الدخول عبر Google كمدير'
              : 'تم تسجيل الدخول عبر Google',
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
    nav.pushReplacementNamed('/open-shift');
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 760;
    return Scaffold(
      backgroundColor: _navy1,
      body: isWide
          ? Row(
              children: [
                Expanded(flex: 5, child: _brandPanel(isNarrow: false)),
                Expanded(flex: 6, child: _formPanel(isNarrow: false)),
              ],
            )
          : Column(
              children: [
                _brandPanel(isNarrow: true),
                Expanded(child: _formPanel(isNarrow: true)),
              ],
            ),
    );
  }

  Widget _brandPanel({required bool isNarrow}) {
    return Container(
      height: isNarrow ? 300 : double.infinity,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy1, _navy2, _navy3],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -50,
            right: -50,
            child: _glow(_gold.withValues(alpha: 0.16), 230),
          ),
          Positioned(
            bottom: -60,
            left: -40,
            child: _glow(_navy3.withValues(alpha: 0.35), 260),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBrandMark(
                  title: 'naboo',
                  logoSize: isNarrow ? 64 : 84,
                  titleFontSize: isNarrow ? 44 : 60,
                  titleColor: const Color(0xFFF2D36B),
                  strokeColor: const Color(0xFF071A36),
                  borderColor: _gold,
                  borderWidth: isNarrow ? 2.0 : 2.2,
                ),
                SizedBox(height: isNarrow ? 10 : 16),
                Text(
                  'نظام إدارة الأعمال',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: isNarrow ? 12 : 16,
                    letterSpacing: 2.5,
                  ),
                ),
                if (!isNarrow) ...[
                  const SizedBox(height: 24),
                  _feature(Icons.receipt_long_rounded, 'المبيعات والفواتير'),
                  _feature(Icons.account_balance_rounded, 'الحسابات والتقارير'),
                  _feature(Icons.inventory_2_rounded, 'المخزون والمستودعات'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _feature(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }

  Widget _formPanel({required bool isNarrow}) {
    return Container(
      width: double.infinity,
      decoration: isNarrow
          ? const BoxDecoration(
              color: Color(0xFFF7F8FA),
              borderRadius: BorderRadius.zero,
            )
          : const BoxDecoration(color: Color(0xFFF7F8FA)),
      child: AnimatedBuilder(
        animation: _animController,
        builder: (_, child) => Opacity(
          opacity: _fadeAnim.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnim.value),
            child: child,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isNarrow ? 24 : 40,
              isNarrow ? 28 : 40,
              isNarrow ? 24 : 40,
              isNarrow ? 24 : 40,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isSignUpMode ? 'إنشاء حساب جديد' : 'تسجيل الدخول',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _navy2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUpMode
                        ? 'أنشئ حسابك الآن بدون الانتقال لصفحة أخرى'
                        : 'أدخل البريد (أو اسم المستخدم) وكلمة السر، أو استخدم Google',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _signInWithGoogle,
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                    label: Text(
                      _isSignUpMode
                          ? 'التسجيل عبر Google'
                          : 'الدخول عبر Google',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _navy2,
                      side: BorderSide(color: Colors.grey.shade300),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: _isSignUpMode ? _signUpForm() : _loginForm(),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading ? null : _toggleMode,
                    child: Text(
                      _isSignUpMode
                          ? 'لديك حساب؟ العودة إلى تسجيل الدخول'
                          : 'ليس لديك حساب؟ إنشاء حساب جديد',
                      style: const TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w700,
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

  Widget _loginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        key: const ValueKey('login'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('البريد أو اسم المستخدم'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _usernameController,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: _dec(
              'البريد أو اسم الدخول',
              Icons.person_outline_rounded,
            ),
            validator: (v) => v == null || v.trim().isEmpty
                ? 'أدخل البريد أو اسم المستخدم'
                : null,
          ),
          const SizedBox(height: 14),
          _label('رمز الدخول'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: _dec(
              'أدخل رمز الدخول',
              Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'أدخل رمز الدخول' : null,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy2,
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('تسجيل الدخول'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _signUpForm() {
    return Form(
      key: _signupFormKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        key: const ValueKey('signup'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('الاسم التجاري/الشخصي'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nameController,
            decoration: _dec('أدخل الاسم', Icons.storefront_outlined),
            validator: (v) => v == null || v.trim().length < 3
                ? 'الاسم مطلوب (3 أحرف على الأقل)'
                : null,
          ),
          const SizedBox(height: 12),
          _label('البريد الإلكتروني'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: _dec('example@domain.com', Icons.email_outlined),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'البريد مطلوب';
              final ok = RegExp(
                r'^[\w\.\-]+@[\w\-]+\.[a-z]{2,}$',
                caseSensitive: false,
              ).hasMatch(v.trim());
              return ok ? null : 'البريد غير صحيح';
            },
          ),
          const SizedBox(height: 12),
          _label('رقم الجوال'),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.zero,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _dialCode,
                    items: const ['+964', '+966', '+971', '+965', '+20', '+1']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _dialCode = v!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _dec('7700000000', Icons.phone_outlined),
                  validator: (v) => v == null || v.trim().length < 7
                      ? 'رقم الجوال غير صحيح'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _label('كلمة السر'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _signupPasswordController,
            obscureText: _obscureSignupPassword,
            onChanged: (_) => setState(() {}),
            decoration: _dec(
              '8 أحرف على الأقل',
              Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  _obscureSignupPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(
                  () => _obscureSignupPassword = !_obscureSignupPassword,
                ),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'كلمة السر مطلوبة';
              if (!_hasMinLength ||
                  !_hasUppercase ||
                  !_hasLowercase ||
                  !_hasDigit ||
                  !_hasSpecialChar) {
                return 'كلمة السر لا تحقق الشروط المطلوبة';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          _passwordRulesCard(),
          const SizedBox(height: 12),
          _label('إعادة كتابة رمز الدخول'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _confirmSignupPasswordController,
            obscureText: _obscureConfirmSignupPassword,
            onChanged: (_) => setState(() {}),
            decoration: _dec(
              'أعد كتابة كلمة السر',
              Icons.lock_reset_rounded,
              suffix: IconButton(
                icon: Icon(
                  _obscureConfirmSignupPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(
                  () => _obscureConfirmSignupPassword =
                      !_obscureConfirmSignupPassword,
                ),
              ),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'الرجاء إعادة كتابة كلمة السر';
              if (v != _signupPasswordController.text) {
                return 'كلمتا السر غير متطابقتين';
              }
              return null;
            },
          ),
          const SizedBox(height: 6),
          _liveMatchHint(),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _signup,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy2,
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('إنشاء الحساب'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _navy2,
      ),
    );
  }

  Widget _passwordRulesCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'شروط كلمة السر (احترافي):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _navy2,
            ),
          ),
          const SizedBox(height: 8),
          _ruleItem(_hasMinLength, '8 أحرف على الأقل'),
          _ruleItem(_hasUppercase, 'حرف كبير واحد على الأقل (A-Z)'),
          _ruleItem(_hasLowercase, 'حرف صغير واحد على الأقل (a-z)'),
          _ruleItem(_hasDigit, 'رقم واحد على الأقل (0-9)'),
          _ruleItem(_hasSpecialChar, 'رمز خاص واحد على الأقل (!@#...)'),
        ],
      ),
    );
  }

  Widget _ruleItem(bool ok, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 16,
            color: ok ? Colors.green.shade700 : Colors.grey.shade500,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: ok ? Colors.green.shade800 : Colors.grey.shade700,
              fontWeight: ok ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveMatchHint() {
    if (_confirmSignupPasswordController.text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Icon(
          _passwordsMatch ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 16,
          color: _passwordsMatch ? Colors.green.shade700 : Colors.red.shade700,
        ),
        const SizedBox(width: 6),
        Text(
          _passwordsMatch ? 'كلمتا السر متطابقتان' : 'كلمتا السر غير متطابقتين',
          style: TextStyle(
            fontSize: 12,
            color: _passwordsMatch
                ? Colors.green.shade700
                : Colors.red.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  InputDecoration _dec(String hint, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      prefixIcon: Icon(icon, color: _navy3, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: const BorderSide(color: _navy3, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }
}
