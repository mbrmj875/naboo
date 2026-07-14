import 'dart:async' show TimeoutException, unawaited, Completer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/business_features_provider.dart';
import '../models/google_sign_in_intent.dart';
import '../models/google_auth_result.dart';
import '../widgets/app_brand_mark.dart';
import '../widgets/inputs/app_input.dart';
import '../theme/erp_input_constants.dart';
import '../theme/design_tokens.dart';
import '../widgets/secure_screen.dart';
import 'auth/email_otp_screen.dart';
import 'auth/complete_owner_profile_screen.dart';
import 'auth/forgot_password_email_screen.dart';
import '../widgets/glass/glass_background.dart';
import '../widgets/glass/glass_surface.dart';
import '../widgets/auth/google_g_logo.dart';
import '../utils/app_logger.dart';
import '../utils/auth_validators.dart';
import '../services/auth/auth_user_messages.dart';
import '../utils/pin_input_constraints.dart';
import '../utils/screen_layout.dart';
import '../widgets/inputs/pin_four_boxes_field.dart';

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

  bool get _signupPinOk =>
      AuthValidators.isValidPin(_signupPasswordController.text);

  bool get _signupSubmissionReady {
    if (_nameController.text.trim().length < 3) return false;
    if (!_emailFormatOk(_emailController.text.trim())) return false;
    if (!_iraqMobileOk(_phoneController.text.trim())) return false;
    if (!_signupPinOk) return false;
    final c = _confirmSignupPasswordController.text.trim();
    if (c.isEmpty || c != _signupPasswordController.text.trim()) return false;
    return true;
  }

  bool _emailFormatOk(String t) {
    if (t.isEmpty) return false;
    return RegExp(
      r'^[\w.\-+]+@[\w-]+\.[a-z]{2,}$',
      caseSensitive: false,
    ).hasMatch(t.trim());
  }

  bool _iraqMobileOk(String raw) => AuthValidators.isValidIraqiPhone(raw);

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
    _signupPasswordController.addListener(_onSignupPinChanged);
    _confirmSignupPasswordController.addListener(_onSignupPinChanged);
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

  void _onSignupPinChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _signupPasswordController.removeListener(_onSignupPinChanged);
    _confirmSignupPasswordController.removeListener(_onSignupPinChanged);
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

  void _toggleMode() => _setSignUpMode(!_isSignUpMode);

  bool _looksLikeEmail(String value) {
    final s = value.trim().toLowerCase();
    if (s.isEmpty || !s.contains('@')) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }

  /// يبدّل بين تبويبي الدخول/التسجيل. يُستدعى يدوياً أو تلقائياً بعد Google
  /// (مثل «لديك حساب» → الدخول، أو «لا يوجد حساب» → التسجيل).
  void _setSignUpMode(bool signUp) {
    if (_isSignUpMode == signUp) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      _isSignUpMode = signUp;
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
    messenger.clearSnackBars();
    final success = await auth.login(
      _usernameController.text.trim(),
      _passwordController.text.trim(),
    );
    if (!mounted) return;
    if (!success) {
      setState(() => _isLoading = false);
      if (auth.deviceAccessRevokedPending) {
        unawaited(nav.pushReplacementNamed('/device-access-revoked'));
        return;
      }
      final err = auth.lastLoginErrorMessage ??
          AuthUserMessages.wrongCredentials;
      if (AuthUserMessages.isAccountNotFound(err)) {
        _setSignUpMode(true);
        if (_looksLikeEmail(_usernameController.text.trim())) {
          _emailController.text = _usernameController.text.trim();
        }
      }
      _showAuthFeedback(err);
      return;
    }
    try {
      final target = await _withWorkspaceBootstrapOverlay(
        () => auth.resolveRouteAfterAuthenticatedSession(),
      );
      if (!mounted) return;
      try {
        await context.read<BusinessFeaturesProvider>().refresh();
      } catch (e, st) {
        AppLogger.error('Login', 'فشل refresh BusinessFeatures بعد الدخول', e, st);
      }
      if (!mounted) return;
      unawaited(nav.pushReplacementNamed(target));
    } on TimeoutException {
      if (!mounted) return;
      _showAuthFeedback(
        'استغرقت تهيئة مساحة العمل وقتاً طويلاً. جارٍ فتح التطبيق…',
        warning: true,
      );
      unawaited(
        nav.pushReplacementNamed(
          auth.deviceOwnerBound ? '/employee-gate' : '/home',
        ),
      );
    } catch (e, st) {
      AppLogger.error('Login', 'resolveRoute بعد الدخول', e, st);
      if (!mounted) return;
      _showAuthFeedback(
        'تعذّر تحميل بيانات السحابة. جارٍ فتح التطبيق…',
        warning: true,
      );
      unawaited(
        nav.pushReplacementNamed(
          auth.deviceOwnerBound ? '/employee-gate' : '/home',
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<T> _withAuthOverlay<T>(
    String message,
    Future<T> Function() task, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    bool dialogShowing = true;
    final completer = Completer<T>();

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    message,
                    style: GoogleFonts.tajawal(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).then((_) => dialogShowing = false),
    );

    try {
      task().then((res) {
        if (!completer.isCompleted) completer.complete(res);
      }).catchError((e, StackTrace st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      });

      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('استغرقت العملية وقتاً طويلاً. حاول مرة أخرى');
        },
      );
    } catch (e) {
      if (e is SocketException) {
        throw Exception('الخدمة السحابية غير متاحة مؤقتاً');
      }
      rethrow;
    } finally {
      if (dialogShowing && mounted) {
        dialogShowing = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<T> _withWorkspaceBootstrapOverlay<T>(Future<T> Function() task) =>
      _withAuthOverlay('جاري تهيئة مساحة العمل…', task);

  void _showWarningSnackBar(String message) {
    _showAuthFeedback(message, warning: true);
  }

  void _showAuthFeedback(String message, {bool warning = false}) {
    final network = AuthUserMessages.isNetworkRelated(message);
    final google = AuthUserMessages.isGoogleRelated(message);
    final useWarning = warning || network || google;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              network
                  ? Icons.wifi_off_rounded
                  : (useWarning
                      ? Icons.warning_amber_rounded
                      : Icons.error_outline_rounded),
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                textAlign: TextAlign.start,
              ),
            ),
          ],
        ),
        backgroundColor: useWarning
            ? Colors.orange.shade800
            : Colors.red.shade700,
        duration: Duration(seconds: network ? 7 : 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    final authProvider = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final intent = _isSignUpMode 
      ? GoogleSignInIntent.signup 
      : GoogleSignInIntent.login;
    
    GoogleAuthResult? result;
    try {
      result = await _withAuthOverlay(
        'جاري تسجيل الدخول بـ Google…',
        () => authProvider.handleGoogleAuth(intent: intent),
        timeout: const Duration(seconds: 120),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (e is TimeoutException) {
        _showAuthFeedback(AuthUserMessages.operationTimeout, warning: true);
      } else if (e is SocketException) {
        _showAuthFeedback(AuthUserMessages.networkUnavailable, warning: true);
      } else {
        _showAuthFeedback(AuthUserMessages.cloudServiceUnavailable, warning: true);
      }
      return;
    }
    
    if (!mounted || result == null) return;
    
    result.when(
      loginSuccess: () async {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('أهلاً بعودتك!'),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          )
        );
        try {
          final target = await _withWorkspaceBootstrapOverlay(
            () => authProvider.resolveRouteAfterAuthenticatedSession(),
          );
          if (!mounted) return;
          try {
            await context.read<BusinessFeaturesProvider>().refresh();
          } catch (e, st) {
            AppLogger.error('Login', 'فشل refresh BusinessFeatures بعد Google', e, st);
          }
          if (!mounted) return;
          unawaited(nav.pushReplacementNamed(target));
        } on TimeoutException {
          if (!mounted) return;
          _showAuthFeedback(
            'استغرقت تهيئة مساحة العمل وقتاً طويلاً. جارٍ فتح التطبيق…',
            warning: true,
          );
          unawaited(
            nav.pushReplacementNamed(
              authProvider.deviceOwnerBound ? '/employee-gate' : '/home',
            ),
          );
        } catch (e, st) {
          AppLogger.error('Login', 'resolveRoute بعد Google', e, st);
          if (!mounted) return;
          _showAuthFeedback(
            'تعذّر تحميل بيانات السحابة. جارٍ فتح التطبيق…',
            warning: true,
          );
          unawaited(
            nav.pushReplacementNamed(
              authProvider.deviceOwnerBound ? '/employee-gate' : '/home',
            ),
          );
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      },
      
      noAccountFound: () {
        setState(() => _isLoading = false);
        messenger.clearSnackBars();
        _setSignUpMode(true);
        _showWarningSnackBar(
          'لا يوجد حساب مسجل بهذا البريد الإلكتروني.\n'
          'أكمل إنشاء حساب جديد',
        );
      },
      
      accountAlreadyExists: () {
        setState(() => _isLoading = false);
        _setSignUpMode(false);
        _showWarningSnackBar(
          'لديك حساب مسجل مسبقاً بهذا البريد الإلكتروني.\n'
          'سجّل الدخول للمتابعة'
        );
      },
      
      needsProfileCompletion: () {
        setState(() => _isLoading = false);
        nav.pushReplacement(
          MaterialPageRoute(
            builder: (_) => const CompleteOwnerProfileScreen(),
          ),
        );
      },

      pinRestoreOtpRequired: () {
        setState(() => _isLoading = false);
        unawaited(
          nav.pushReplacementNamed(
            '/owner-pin-restore-otp',
            arguments: const {'otpAlreadySent': true},
          ),
        );
      },

      // على الويب: بدأت إعادة التوجيه لصفحة Google؛ نُبقي مؤشر التحميل
      // لأن الصفحة ستُعاد تحميلها والإكمال يتم في شاشة الإقلاع.
      redirectStarted: () {},

      networkError: () {
        setState(() => _isLoading = false);
        _showAuthFeedback(AuthUserMessages.networkUnavailable, warning: true);
      },

      timeout: () {
        setState(() => _isLoading = false);
        _showAuthFeedback(AuthUserMessages.operationTimeout, warning: true);
      },
      
      cancelled: () {
        setState(() => _isLoading = false);
      },
      
      error: (msg) {
        setState(() => _isLoading = false);
        _showAuthFeedback(
          msg ?? 'حدث خطأ. حاول مرة أخرى',
          warning: AuthUserMessages.isNetworkRelated(msg ?? '') ||
              AuthUserMessages.isGoogleRelated(msg ?? ''),
        );
      },
    );
  }

  Widget _googleSignInDivider() {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.22),
              height: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
            child: Text(
              'أو',
              style: GoogleFonts.tajawal(
                color: Colors.white.withValues(alpha: 0.62),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.white.withValues(alpha: 0.22),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _googleSignInButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.72),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const GoogleGLogo(size: 20),
            const SizedBox(width: 12),
            Text(
              'تسجيل بـ Google',
              style: GoogleFonts.tajawal(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F1F1F),
              ),
            ),
          ],
        ),
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
    messenger.clearSnackBars();
    final email = _emailController.text.trim();
    final err = await auth.registerManualWithPin(
      email: email,
      phone: _phoneController.text.trim(),
      pin: _signupPasswordController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (err != null) {
      _showAuthFeedback(err);
      return;
    }
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EmailOtpScreen(
          email: email,
          displayName: _nameController.text.trim(),
          // الصيغة المحلية 07XXXXXXXXX هي الكانوني في التطبيق؛ لا نُضيف رمز
          // الدولة هنا (كان يُنتج +96407… خاطئاً). التطبيع يتم في المزوّد.
          phone: _phoneController.text.trim(),
          pin: _signupPasswordController.text.trim(),
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
    final layout = context.screenLayout;
    final variant = layout.layoutVariant;
    final isWide = variant.index >= DeviceVariant.tabletLG.index;
    final isPhoneCompact = layout.isPhoneVariant;
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

    return SecureScreen(
      child: Theme(
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
                        height: isPhoneCompact
                            ? (keyboardVisible ? 56.0 : 76.0)
                            : (keyboardVisible ? 120.0 : 290.0),
                        width: double.infinity,
                        child: _brandPanel(
                          isNarrow: true,
                          collapsed: keyboardVisible,
                          logoOnly: isPhoneCompact,
                        ),
                      ),
                      Expanded(child: _formPanel(isNarrow: true)),
                    ],
                  ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _brandPanel({
    required bool isNarrow,
    required bool collapsed,
    bool logoOnly = false,
  }) {
    final showFullBrand = !logoOnly;
    final logoSize = isNarrow
        ? (logoOnly
            ? (collapsed ? 40.0 : 48.0)
            : (collapsed ? 44.0 : 64.0))
        : 96.0;
    final titleSize = isNarrow ? (collapsed ? 34.0 : 44.0) : 64.0;
    final topPad = isNarrow
        ? (logoOnly ? 8.0 : (collapsed ? 8.0 : 18.0))
        : 0.0;
    final alignment = isNarrow && logoOnly
        ? AlignmentDirectional.topCenter
        : Alignment.center;

    final panelBody = Padding(
      padding: EdgeInsetsDirectional.only(
        top: topPad,
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
            showTitle: showFullBrand,
          ),
          if (showFullBrand && !collapsed) ...[
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
    );

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxH = constraints.maxHeight;
          if (isNarrow && maxH.isFinite) {
            return Align(
              alignment: alignment,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: alignment,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: (maxH - topPad).clamp(0.0, maxH),
                  ),
                  child: panelBody,
                ),
              ),
            );
          }
          return Align(alignment: alignment, child: panelBody);
        },
      ),
    );
  }

  Widget _feature(IconData icon, String title) {
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      blurSigma: 10,
      tintColor: Colors.white.withValues(alpha: 0.07),
      strokeColor: Colors.white.withValues(alpha: 0.10),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 18,
        vertical: 10,
      ),
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
                        : 'أدخل البريد الإلكتروني ورمز PIN للدخول',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _googleSignInButton(),
                  _googleSignInDivider(),
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
                      padding: const EdgeInsetsDirectional.symmetric(
                        vertical: 10,
                      ),
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
      final t = (value ?? '').trim();
      if (t.isEmpty) return 'هذا الحقل مطلوب';
      if (!AuthValidators.isValidPin(t)) {
        return PinInputConstraints.invalidMessage;
      }
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
          PinFourBoxesField(
            useGlass: true,
            controller: _passwordController,
            focusNode: _focusLoginPass,
            label: 'رمز PIN *',
            obscureText: _obscurePassword,
            onToggleObscure: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            textInputAction: TextInputAction.done,
            onCompleted: (_) {
              if (!_isLoading) _login();
            },
            onEditingComplete: () {
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
                'نسيت رمز PIN؟',
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
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🇮🇶',
                  style: TextStyle(
                    fontSize: 22,
                    height: 1,
                    fontFamilyFallback: ['Segoe UI Emoji', 'Apple Color Emoji'],
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

    String? validateSignupPin(String? value) {
      final t = (value ?? '').trim();
      if (!_blurredSignupPwd) return null;
      if (t.isEmpty) return 'رمز PIN مطلوب';
      if (!AuthValidators.isValidPin(t)) {
        return PinInputConstraints.invalidMessage;
      }
      return null;
    }

    String? validateConfirm(String? value) {
      final t = (value ?? '').trim();
      if (t.isNotEmpty && t != _signupPasswordController.text.trim()) {
        return 'رمز PIN غير مطابق';
      }
      if (t.isEmpty) {
        if (!_blurredSignupConfirm) return null;
        return 'الرجاء تأكيد رمز PIN';
      }
      return null;
    }

    final confirmHasText = _confirmSignupPasswordController.text.isNotEmpty;
    final mismatchLabelVisible =
        confirmHasText &&
        _confirmSignupPasswordController.text.trim() !=
            _signupPasswordController.text.trim();

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
          PinFourBoxesField(
            useGlass: true,
            controller: _signupPasswordController,
            focusNode: _focusSignupPwd,
            label: 'رمز PIN *',
            obscureText: _obscureSignupPassword,
            onToggleObscure: () => setState(
              () => _obscureSignupPassword = !_obscureSignupPassword,
            ),
            textInputAction: TextInputAction.next,
            onCompleted: (_) =>
                FocusScope.of(context).requestFocus(_focusSignupConfirm),
            onEditingComplete: () =>
                FocusScope.of(context).requestFocus(_focusSignupConfirm),
            validator: validateSignupPin,
          ),
          const SizedBox(height: 14),
          PinFourBoxesField(
            useGlass: true,
            controller: _confirmSignupPasswordController,
            focusNode: _focusSignupConfirm,
            label: mismatchLabelVisible
                ? 'تأكيد رمز PIN * — غير مطابق'
                : 'تأكيد رمز PIN *',
            obscureText: _obscureConfirmSignupPassword,
            onToggleObscure: () => setState(
              () => _obscureConfirmSignupPassword =
                  !_obscureConfirmSignupPassword,
            ),
            textInputAction: TextInputAction.done,
            onCompleted: (_) {
              setState(() {});
              if (!_isLoading && _signupSubmissionReady) _signup();
            },
            onEditingComplete: () {
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
}
