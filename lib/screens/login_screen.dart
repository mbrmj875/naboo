import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_brand_mark.dart';
import '../widgets/inputs/app_input.dart';
import '../theme/erp_input_constants.dart';
import '../theme/design_tokens.dart';
import 'auth/email_otp_screen.dart';
import 'auth/forgot_password_email_screen.dart';
import '../services/app_settings_repository.dart';
import '../services/business_setup_settings.dart';
import '../widgets/glass/glass_background.dart';
import '../widgets/glass/glass_surface.dart';
import '../utils/screen_layout.dart';

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

  static const Color _gold = AppColors.accentGold;
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

  /// جوال عراقي محلي: 11 رقماً يبدأ بـ 07 (بدون +964 في هذا الحقل).
  bool _iraqMobileOk(String raw) => RegExp(r'^07\d{9}$').hasMatch(raw.trim());

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
      unawaited(nav.pushReplacementNamed(target));
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
    // 2026-05 (Phase 2): قرار التخطيط أصبح يعتمد على DeviceVariant
    // (Single Source of Truth) بدل breakpoint رقمي 760. الـ side-by-side
    // (Brand | Form) يظهر في tabletLG+ (≥840dp). أصغر ⇒ Column مع
    // Brand مضغوط فوق الفورم.
    final variant = context.screenLayout.layoutVariant;
    final isWide = variant.index >= DeviceVariant.tabletLG.index;
    final keyboardH = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = keyboardH > 0;

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
            child: isWide
                ? Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _brandPanel(isNarrow: false, collapsed: false),
                      ),
                      Expanded(flex: 6, child: _formPanel(isNarrow: false)),
                    ],
                  )
                : Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        height: keyboardVisible ? 120 : 290,
                        width: double.infinity,
                        child: _brandPanel(
                          isNarrow: true,
                          collapsed: keyboardVisible,
                        ),
                      ),
                      Expanded(child: _formPanel(isNarrow: true)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _brandPanel({required bool isNarrow, required bool collapsed}) {
    final logoSize = isNarrow ? (collapsed ? 44.0 : 64.0) : 96.0;
    final titleSize = isNarrow ? (collapsed ? 34.0 : 44.0) : 64.0;
    final content = Center(
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          top: isNarrow ? (collapsed ? 8 : 18) : 0,
          start: isNarrow ? 16 : 32,
          end: isNarrow ? 16 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBrandMark(
              title: 'naboo',
              logoSize: logoSize,
              titleFontSize: titleSize,
              titleColor: const Color(0xFFF2D36B),
              strokeColor: AppColors.primary,
              borderColor: _gold,
              borderWidth: isNarrow ? 2.0 : 2.4,
            ),
            if (!collapsed) ...[
              SizedBox(height: isNarrow ? 10 : 20),
              Text(
                'نظام إدارة الأعمال',
                style: GoogleFonts.tajawal(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontSize: isNarrow ? 13 : 17,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 3.0,
                ),
              ),
            ],
            if (!isNarrow) ...[
              const SizedBox(height: 36),
              _feature(Icons.receipt_long_rounded, 'المبيعات والفواتير'),
              const SizedBox(height: 10),
              _feature(Icons.account_balance_rounded, 'الحسابات والتقارير'),
              const SizedBox(height: 10),
              _feature(Icons.inventory_2_rounded, 'المخزون والمستودعات'),
            ],
          ],
        ),
      ),
    );

    return SizedBox(
      width: double.infinity,
      child: content,
    );
  }

  Widget _feature(IconData icon, String title) {
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      blurSigma: 10,
      tintColor: Colors.white.withValues(alpha: 0.07),
      strokeColor: Colors.white.withValues(alpha: 0.10),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFFF2D36B)),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: GoogleFonts.tajawal(
              color: Colors.white.withValues(alpha: 0.86),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _formPanel({required bool isNarrow}) {
    return AnimatedBuilder(
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
          padding: EdgeInsetsDirectional.fromSTEB(
            isNarrow ? 20 : 32,
            isNarrow ? 18 : 28,
            isNarrow ? 20 : 32,
            (isNarrow ? 24 : 28) + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: GlassSurface(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              tintColor: AppGlass.surfaceTint,
              strokeColor: AppGlass.stroke,
              padding: const EdgeInsetsDirectional.fromSTEB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB8960C), Color(0xFFFFE08A)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isSignUpMode ? 'إنشاء حساب جديد' : 'تسجيل الدخول',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(
                      fontSize: isNarrow ? 24 : 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isSignUpMode
                        ? 'سيصلك رمز تحقق على بريدك الإلكتروني لتأكيد حسابك'
                        : 'أدخل البريد الإلكتروني وكلمة السر للدخول',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _isSignUpMode ? _signUpForm() : _loginForm(),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading ? null : _toggleMode,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsetsDirectional.symmetric(vertical: 10),
                      foregroundColor: const Color(0xFFF5C518),
                    ),
                    child: Text(
                      _isSignUpMode
                          ? 'لديك حساب؟ العودة إلى تسجيل الدخول'
                          : 'ليس لديك حساب؟ إنشاء حساب جديد',
                      style: GoogleFonts.tajawal(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
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
            useGlass: true,
            cursorColor: Colors.white,
            suffixIcon: Icon(
              Icons.person_outline_rounded,
              color: Colors.white.withValues(alpha: 0.82),
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
            useGlass: true,
            cursorColor: Colors.white,
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
                color: Colors.white.withValues(alpha: 0.82),
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            suffixIcon: Icon(
              Icons.lock_outline_rounded,
              color: Colors.white.withValues(alpha: 0.82),
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
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF071A36), Color(0xFF0D1F3C)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'تسجيل الدخول',
                        style: GoogleFonts.tajawal(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
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
            constraints: const BoxConstraints(
              minHeight: ErpInputConstants.minHeightSingleLine + 14,
            ),
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: ErpInputConstants.borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🇮🇶',
                  style: TextStyle(
                    fontSize: 22,
                    height: 1,
                    fontFamilyFallback: [
                      'Segoe UI Emoji',
                      'Apple Color Emoji',
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text('+964', style: TextStyle(color: Colors.white)),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withValues(alpha: 0.85),
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
      if (!_iraqMobileOk(raw)) {
        return 'رقم عراقي: 11 رقماً يبدأ بـ 07 (مثال: 07701234567)';
      }
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
            useGlass: true,
            cursorColor: Colors.white,
            suffixIcon: Icon(
              Icons.storefront_outlined,
              color: Colors.white.withValues(alpha: 0.82),
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
            useGlass: true,
            cursorColor: Colors.white,
            suffixIcon: Icon(
              Icons.email_outlined,
              color: Colors.white.withValues(alpha: 0.82),
              size: 20,
            ),
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
                    color: Colors.white,
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
                    hint: '07701234567',
                    controller: _phoneController,
                    focusNode: _focusSignupPhone,
                    useGlass: true,
                    cursorColor: Colors.white,
                    suffixIcon: Icon(
                      Icons.phone_outlined,
                      color: Colors.white.withValues(alpha: 0.82),
                      size: 20,
                    ),
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
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
            useGlass: true,
            cursorColor: Colors.white,
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
                color: Colors.white.withValues(alpha: 0.82),
              ),
              onPressed: () => setState(
                () => _obscureSignupPassword = !_obscureSignupPassword,
              ),
            ),
            suffixIcon: Icon(
              Icons.lock_outline_rounded,
              color: Colors.white.withValues(alpha: 0.82),
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
                    color: mismatchLabelVisible
                        ? const Color(0xFFEF4444)
                        : Colors.white,
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
            useGlass: true,
            cursorColor: Colors.white,
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
                    color: Colors.white.withValues(alpha: 0.82),
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
                    icon: const Icon(
                      Icons.cancel_rounded,
                      color: Color(0xFFEF4444),
                      size: 22,
                    ),
                    onPressed: () {
                      _confirmSignupPasswordController.clear();
                      setState(() {});
                    },
                  ),
              ],
            ),
            suffixIcon: Icon(
              Icons.task_alt_rounded,
              color: Colors.white.withValues(alpha: 0.82),
              size: 20,
            ),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onFieldSubmitted: (_) {
              if (!_isLoading && _signupSubmissionReady) _signup();
            },
            validator: validateConfirm,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _signupSubmissionReady ? 1.0 : 0.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF071A36), Color(0xFF0D1F3C)],
                  ),
                  boxShadow: _signupSubmissionReady
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: ElevatedButton(
                  onPressed: (_isLoading || !_signupSubmissionReady)
                      ? null
                      : _signup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white70,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'إنشاء الحساب',
                          style: GoogleFonts.tajawal(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _passwordRulesCard() {
    final metCount = [_hasMinLength, _hasUppercase, _hasLowercase, _hasDigit, _hasSpecialChar]
        .where((v) => v).length;
    final strength = metCount / 5.0;
    final strengthColor = strength < 0.4
        ? Colors.red.shade400
        : strength < 0.8
            ? const Color(0xFFF59E0B)
            : Colors.green.shade600;
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      blurSigma: 10,
      tintColor: AppGlass.surfaceTintStrong,
      strokeColor: Colors.white.withValues(alpha: 0.14),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 16,
                color: Colors.white.withValues(alpha: 0.86),
              ),
              const SizedBox(width: 6),
              Text(
                'شروط كلمة السر',
                style: GoogleFonts.tajawal(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Strength bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: strength),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                color: strengthColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
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
            color: ok ? const Color(0xFF22C55E) : amberUnmet,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: ok
                  ? const Color(0xFFBBF7D0)
                  : Colors.white.withValues(alpha: 0.72),
              fontWeight: ok ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
