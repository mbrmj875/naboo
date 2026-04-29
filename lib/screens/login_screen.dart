import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_brand_mark.dart';
import '../widgets/inputs/app_input.dart';
import '../theme/erp_input_constants.dart';
import 'auth/email_otp_screen.dart';
import 'auth/forgot_password_email_screen.dart';
import '../services/app_settings_repository.dart';
import '../services/business_setup_settings.dart';

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
  final String _dialCode = '+964';

  late AnimationController _animController;
  late Animation<double> _slideAnim;
  late Animation<double> _fadeAnim;

  static const Color _navy1 = Color(0xFF050A14);
  static const Color _navy2 = Color(0xFF0D1F3C);
  static const Color _navy3 = Color(0xFF1A3A6B);
  static const Color _gold = Color(0xFFB8960C);
  static const Color _navyPrimary = Color(0xFF1A2340);
  static const Color _goldLink = Color(0xFFF5C518);

  final _focusLoginUser = FocusNode();
  final _focusLoginPass = FocusNode();
  final _focusSignupName = FocusNode();
  final _focusSignupEmail = FocusNode();
  final _focusSignupPhone = FocusNode();
  final _focusSignupPwd = FocusNode();
  final _focusSignupConfirm = FocusNode();

  bool _blurredLoginUser = false;
  bool _blurredLoginPass = false;
  bool _blurredSignupName = false;
  bool _blurredSignupEmail = false;
  bool _blurredSignupPhone = false;
  bool _blurredSignupPwd = false;
  bool _blurredSignupConfirm = false;
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
  bool get _allPasswordRequirementsMet =>
      _hasMinLength &&
      _hasUppercase &&
      _hasLowercase &&
      _hasDigit &&
      _hasSpecialChar;

  bool get _showPasswordRequirementsPanel {
    final t = _signupPasswordController.text;
    if (t.isEmpty) return false;
    if (_allPasswordRequirementsMet && !_focusSignupPwd.hasFocus) {
      return false;
    }
    return true;
  }

  bool get _signupSubmissionReady {
    if (_nameController.text.trim().length < 3) return false;
    if (!_emailFormatOk(_emailController.text.trim())) return false;
    if (!_iraqMobileOk(_phoneController.text.trim())) return false;
    if (!_allPasswordRequirementsMet) return false;
    final c = _confirmSignupPasswordController.text;
    if (c.isEmpty || c != _signupPasswordController.text) return false;
    return true;
  }

  bool _emailFormatOk(String t) {
    if (t.isEmpty) return false;
    return RegExp(
      r'^[\w.\-+]+@[\w-]+\.[a-z]{2,}$',
      caseSensitive: false,
    ).hasMatch(t.trim());
  }

  bool _iraqMobileOk(String raw) => RegExp(r'^07\d{8}$').hasMatch(raw.trim());

  bool get _passwordsMatch =>
      _confirmSignupPasswordController.text.isNotEmpty &&
      _confirmSignupPasswordController.text == _signupPasswordController.text;

  void _registerBlurListeners() {
    void userTick() {
      if (!_focusLoginUser.hasFocus && mounted) {
        setState(() => _blurredLoginUser = true);
      }
    }

    void passTick() {
      if (!_focusLoginPass.hasFocus && mounted) {
        setState(() => _blurredLoginPass = true);
      }
    }

    _focusLoginUser.addListener(userTick);
    _focusLoginPass.addListener(passTick);

    void signupNameTick() {
      if (!_focusSignupName.hasFocus && mounted) {
        setState(() => _blurredSignupName = true);
      }
    }

    void signupEmailTick() {
      if (!_focusSignupEmail.hasFocus && mounted) {
        setState(() => _blurredSignupEmail = true);
      }
    }

    void signupPhoneTick() {
      if (!_focusSignupPhone.hasFocus && mounted) {
        setState(() => _blurredSignupPhone = true);
      }
    }

    void signupPwdTick() {
      if (!_focusSignupPwd.hasFocus && mounted) {
        setState(() => _blurredSignupPwd = true);
      } else if (mounted) {
        setState(() {});
      }
    }

    void signupConfirmTick() {
      if (!_focusSignupConfirm.hasFocus && mounted) {
        setState(() => _blurredSignupConfirm = true);
      }
    }

    _focusSignupName.addListener(signupNameTick);
    _focusSignupEmail.addListener(signupEmailTick);
    _focusSignupPhone.addListener(signupPhoneTick);
    _focusSignupPwd.addListener(signupPwdTick);
    _focusSignupConfirm.addListener(signupConfirmTick);
  }

  @override
  void initState() {
    super.initState();
    _registerBlurListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusLoginUser.requestFocus();
    });
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
    _focusLoginUser.dispose();
    _focusLoginPass.dispose();
    _focusSignupName.dispose();
    _focusSignupEmail.dispose();
    _focusSignupPhone.dispose();
    _focusSignupPwd.dispose();
    _focusSignupConfirm.dispose();
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
      _blurredSignupName = false;
      _blurredSignupEmail = false;
      _blurredSignupPhone = false;
      _blurredSignupPwd = false;
      _blurredSignupConfirm = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isSignUpMode) {
        _focusSignupName.requestFocus();
      } else {
        _focusLoginUser.requestFocus();
      }
    });
  }

  Future<void> _login() async {
    setState(() {
      _blurredLoginUser = true;
      _blurredLoginPass = true;
    });
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
      var target = '/open-shift';
      try {
        final completed = await BusinessSetupSettingsData.isCompleted(
          AppSettingsRepository.instance,
        );
        if (!completed) target = '/onboarding';
      } catch (_) {}
      nav.pushReplacementNamed(target);
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
    setState(() {
      _blurredSignupName = true;
      _blurredSignupEmail = true;
      _blurredSignupPhone = true;
      _blurredSignupPwd = true;
      _blurredSignupConfirm = true;
    });
    if (!_signupFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final email = _emailController.text.trim();
    final err = await auth.sendEmailOtp(email);
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
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EmailOtpScreen(
          email: email,
          displayName: _nameController.text.trim(),
          phone: '$_dialCode${_phoneController.text.trim()}',
          password: _signupPasswordController.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 760;
    return Scaffold(
      backgroundColor: _navy1,
      body: isWide
          ? Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: _formPanel(isNarrow: false),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: _brandPanel(isNarrow: false),
                    ),
                  ),
                ],
              ),
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
                        ? 'سيصلك رمز تحقق على بريدك الإلكتروني لتأكيد حسابك'
                        : 'أدخل البريد الإلكتروني وكلمة السر للدخول',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 20),
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
                        color: _goldLink,
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
    String? validateUser(String? value) {
      final t = (value ?? '').trim();
      if (!_blurredLoginUser) return null;
      if (t.isEmpty) return 'هذا الحقل مطلوب';
      if (t.length < 3) return 'يجب أن يكون 3 أحرف على الأقل';
      return null;
    }

    String? validatePass(String? value) {
      if (!_blurredLoginPass) return null;
      if ((value ?? '').trim().isEmpty) return 'هذا الحقل مطلوب';
      return null;
    }

    return Form(
      key: _loginFormKey,
      child: Column(
        key: const ValueKey('login'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppInput(
            label: 'البريد أو اسم المستخدم',
            labelFontWeight: FontWeight.w700,
            isRequired: true,
            hint: 'البريد أو اسم الدخول',
            controller: _usernameController,
            focusNode: _focusLoginUser,
            fillColor: Colors.white,
            cursorColor: _navy2,
            suffixIcon: Icon(
              Icons.person_outline_rounded,
              color: _navy3,
              size: 20,
            ),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_focusLoginPass),
            validator: validateUser,
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'رمز الدخول',
            labelFontWeight: FontWeight.w700,
            isRequired: true,
            hint: 'أدخل رمز الدخول',
            controller: _passwordController,
            focusNode: _focusLoginPass,
            obscureText: _obscurePassword,
            fillColor: Colors.white,
            cursorColor: _navy2,
            textDirection: TextDirection.ltr,
            densePrefixConstraints: const BoxConstraints(
              minHeight: 48,
              minWidth: 48,
            ),
            prefixIcon: IconButton(
              tooltip: _obscurePassword ? 'إظهار الرمز' : 'إخفاء الرمز',
              splashRadius: 22,
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _navy3,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            suffixIcon: Icon(
              Icons.lock_outline_rounded,
              color: _navy3,
              size: 20,
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) {
              if (!_isLoading) _login();
            },
            validator: validatePass,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const ForgotPasswordEmailScreen(),
                        ),
                      );
                    },
              style: TextButton.styleFrom(
                padding: EdgeInsetsDirectional.zero,
                foregroundColor: _goldLink,
              ),
              child: const Text(
                'نسيت رمز الدخول؟',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyPrimary,
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

  Widget _iraqDialChip() {
    return Tooltip(
      message: '+964 العراق — سيتوفر اختيار دول أخرى لاحقاً',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {},
          borderRadius: ErpInputConstants.borderRadius,
          child: Container(
            constraints: BoxConstraints(
              minHeight: ErpInputConstants.minHeightSingleLine + 14,
            ),
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: ErpInputConstants.borderRadius,
              border: Border.all(color: Colors.grey.shade300, width: 1.25),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🇮🇶',
                  style: TextStyle(
                    fontSize: 22,
                    height: 1,
                    fontFamilyFallback: const [
                      'Segoe UI Emoji',
                      'Apple Color Emoji',
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text('+964'),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _navy3,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _signUpForm() {
    String? validateSignupName(String? value) {
      final t = (value ?? '').trim();
      if (!_blurredSignupName) return null;
      if (t.isEmpty) return 'الاسم مطلوب';
      if (t.length < 3) return 'الاسم مطلوب (3 أحرف على الأقل)';
      return null;
    }

    String? validateSignupEmail(String? value) {
      final t = (value ?? '').trim();
      if (!_blurredSignupEmail) return null;
      if (t.isEmpty) return 'البريد مطلوب';
      if (!_emailFormatOk(t)) return 'صيغة البريد غير صحيحة';
      return null;
    }

    String? validateSignupPhone(String? value) {
      final raw = (value ?? '').trim();
      if (!_blurredSignupPhone) return null;
      if (!_iraqMobileOk(raw)) return 'رقم الجوال غير صحيح';
      return null;
    }

    String? validateSignupPassword(String? value) {
      final t = value ?? '';
      if (t.isEmpty) {
        if (!_blurredSignupPwd) return null;
        return 'كلمة السر مطلوبة';
      }
      if (!_allPasswordRequirementsMet) {
        return 'كلمة السر لا تحقق الشروط المطلوبة';
      }
      return null;
    }

    String? validateConfirm(String? value) {
      final t = value ?? '';
      if (t.isNotEmpty && !_passwordsMatch) {
        return 'كلمتا السر غير متطابقتين';
      }
      if (t.isEmpty) {
        if (!_blurredSignupConfirm) return null;
        return 'الرجاء إعادة كتابة كلمة السر';
      }
      return null;
    }

    final confirmHasText = _confirmSignupPasswordController.text.isNotEmpty;
    final mismatchLabelVisible = confirmHasText && !_passwordsMatch;

    return Form(
      key: _signupFormKey,
      autovalidateMode: AutovalidateMode.always,
      child: Column(
        key: const ValueKey('signup'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppInput(
            label: 'الاسم التجاري/الشخصي',
            labelFontWeight: FontWeight.w700,
            isRequired: true,
            hint: 'أدخل الاسم',
            controller: _nameController,
            focusNode: _focusSignupName,
            fillColor: Colors.white,
            cursorColor: _navy2,
            suffixIcon: Icon(
              Icons.storefront_outlined,
              color: _navy3,
              size: 20,
            ),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_focusSignupEmail),
            validator: validateSignupName,
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'البريد الإلكتروني',
            labelFontWeight: FontWeight.w700,
            isRequired: true,
            hint: 'example@domain.com',
            controller: _emailController,
            focusNode: _focusSignupEmail,
            fillColor: Colors.white,
            cursorColor: _navy2,
            suffixIcon: Icon(Icons.email_outlined, color: _navy3, size: 20),
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_focusSignupPhone),
            validator: validateSignupEmail,
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  'رقم الجوال',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _navy2,
                  ),
                  maxLines: 2,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Text(
                  '*',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _iraqDialChip(),
                const SizedBox(width: 10),
                Expanded(
                  child: AppInput(
                    label: ' ',
                    showLabel: false,
                    hint: '7700000000',
                    controller: _phoneController,
                    focusNode: _focusSignupPhone,
                    fillColor: Colors.white,
                    cursorColor: _navy2,
                    suffixIcon: Icon(
                      Icons.phone_outlined,
                      color: _navy3,
                      size: 20,
                    ),
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    overlayShadowOnFocus: false,
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) =>
                        FocusScope.of(context).requestFocus(_focusSignupPwd),
                    validator: validateSignupPhone,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppInput(
            label: 'كلمة السر',
            labelFontWeight: FontWeight.w700,
            isRequired: true,
            hint: '8 أحرف على الأقل',
            controller: _signupPasswordController,
            focusNode: _focusSignupPwd,
            obscureText: _obscureSignupPassword,
            fillColor: Colors.white,
            cursorColor: _navy2,
            textDirection: TextDirection.ltr,
            densePrefixConstraints: const BoxConstraints(
              minHeight: 48,
              minWidth: 48,
            ),
            prefixIcon: IconButton(
              tooltip: _obscureSignupPassword ? 'إظهار الرمز' : 'إخفاء الرمز',
              splashRadius: 22,
              icon: Icon(
                _obscureSignupPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _navy3,
              ),
              onPressed: () => setState(
                () => _obscureSignupPassword = !_obscureSignupPassword,
              ),
            ),
            suffixIcon: Icon(
              Icons.lock_outline_rounded,
              color: _navy3,
              size: 20,
            ),
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) =>
                FocusScope.of(context).requestFocus(_focusSignupConfirm),
            validator: validateSignupPassword,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _showPasswordRequirementsPanel
                ? Padding(
                    key: const ValueKey('pwdRules'),
                    padding: const EdgeInsets.only(top: 10),
                    child: _passwordRulesCard(),
                  )
                : const SizedBox(height: 0, key: ValueKey('noPwd')),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  'إعادة كتابة رمز الدخول',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: mismatchLabelVisible ? Colors.red.shade700 : _navy2,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Text(
                  '*',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 13,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AppInput(
            label: ' ',
            showLabel: false,
            hint: 'أعد كتابة كلمة السر',
            controller: _confirmSignupPasswordController,
            focusNode: _focusSignupConfirm,
            obscureText: _obscureConfirmSignupPassword,
            fillColor: Colors.white,
            cursorColor: _navy2,
            textDirection: TextDirection.ltr,
            densePrefixConstraints: BoxConstraints(
              minWidth: confirmHasText ? 112 : 48,
              minHeight: 48,
            ),
            prefixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _obscureConfirmSignupPassword
                      ? 'إظهار الرمز'
                      : 'إخفاء الرمز',
                  splashRadius: 22,
                  icon: Icon(
                    _obscureConfirmSignupPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _navy3,
                  ),
                  onPressed: () => setState(
                    () => _obscureConfirmSignupPassword =
                        !_obscureConfirmSignupPassword,
                  ),
                ),
                if (confirmHasText)
                  IconButton(
                    tooltip: 'مسح',
                    splashRadius: 22,
                    icon: Icon(
                      Icons.cancel_rounded,
                      color: Colors.red.shade600,
                      size: 22,
                    ),
                    onPressed: () {
                      _confirmSignupPasswordController.clear();
                      setState(() {});
                    },
                  ),
              ],
            ),
            suffixIcon: Icon(Icons.task_alt_rounded, color: _navy3, size: 20),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) {
              if (!_isLoading && _signupSubmissionReady) _signup();
            },
            validator: validateConfirm,
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (_isLoading || !_signupSubmissionReady)
                  ? null
                  : _signup,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyPrimary,
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

  Widget _passwordRulesCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: ErpInputConstants.borderRadius,
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'شروط كلمة السر (احترافي)',
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
          _ruleItem(_hasSpecialChar, 'رمز خاص واحد على الأقل (@#!...)'),
        ],
      ),
    );
  }

  Widget _ruleItem(bool ok, String label) {
    const amberUnmet = Color(0xFFF59E0B);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 16,
            color: ok ? Colors.green.shade700 : amberUnmet,
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
}
