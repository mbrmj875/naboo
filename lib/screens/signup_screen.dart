import 'dart:math' show Random, pi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_brand_mark.dart';

/// نفس [login_screen] — نصوص الحقول الفاتحة لا ترث لون الثيم الداكن للتطبيق.
ThemeData _authPanelLightThemeSignup(BuildContext context) {
  const onSurface = Color(0xFF0D1F3C);
  const onVariant = Color(0xFF5C6570);
  final base = Theme.of(context);
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.light,
      surface: const Color(0xFFF7F8FA),
      onSurface: onSurface,
      onSurfaceVariant: onVariant,
      outline: const Color(0xFFC5CAD3),
      primary: const Color(0xFF1A3A6B),
    ),
    textTheme: base.textTheme.apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    ),
  );
}

// ── Design tokens (identical to login_screen) ──────────────────────────────
const Color _navy1 = Color(0xFF050A14);
const Color _navy2 = Color(0xFF0D1F3C);
const Color _navy3 = Color(0xFF1A3A6B);
const Color _gold  = Color(0xFFB8960C);

// ═══════════════════════════════════════════════════════════════════════════
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // ── Controllers ────────────────────────────────────────────────────────
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();

  // ── State ──────────────────────────────────────────────────────────────
  bool   _obscurePass    = true;
  bool   _obscureConfirm = true;
  bool   _isLoading      = false;
  bool   _acceptTerms    = false;
  String _dialCode       = '+964'; // العراق افتراضيًا

  // ── Captcha ─────────────────────────────────────────────────────────────
  late int _captchaA;
  late int _captchaB;
  int get _captchaAnswer => _captchaA + _captchaB;

  // ── Animations ─────────────────────────────────────────────────────────
  late AnimationController _anim;
  late Animation<double>   _slideAnim;
  late Animation<double>   _fadeAnim;

  // ── Country codes ───────────────────────────────────────────────────────
  static const _countryCodes = [
    {'flag': '🇮🇶', 'name': 'العراق',         'code': '+964'},
    {'flag': '🇸🇦', 'name': 'السعودية',        'code': '+966'},
    {'flag': '🇦🇪', 'name': 'الإمارات',        'code': '+971'},
    {'flag': '🇰🇼', 'name': 'الكويت',          'code': '+965'},
    {'flag': '🇸🇾', 'name': 'سوريا',           'code': '+963'},
    {'flag': '🇯🇴', 'name': 'الأردن',          'code': '+962'},
    {'flag': '🇱🇧', 'name': 'لبنان',           'code': '+961'},
    {'flag': '🇪🇬', 'name': 'مصر',             'code': '+20'},
    {'flag': '🇹🇷', 'name': 'تركيا',           'code': '+90'},
    {'flag': '🇩🇪', 'name': 'ألمانيا',         'code': '+49'},
    {'flag': '🇬🇧', 'name': 'المملكة المتحدة', 'code': '+44'},
    {'flag': '🇺🇸', 'name': 'الولايات المتحدة','code': '+1'},
  ];

  @override
  void initState() {
    super.initState();
    _refreshCaptcha();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _slideAnim = Tween<double>(begin: 40, end: 0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
    _fadeAnim = CurvedAnimation(parent: _anim, curve: Curves.easeIn);
    _anim.forward();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _captchaCtrl.dispose();
    _anim.dispose();
    super.dispose();
  }

  void _refreshCaptcha() {
    final rng = Random();
    setState(() {
      _captchaA = rng.nextInt(9) + 1;
      _captchaB = rng.nextInt(9) + 1;
      _captchaCtrl.clear();
    });
  }

  // ── Register action ──────────────────────────────────────────────────────
  Future<void> _register() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptTerms) {
      _showSnack('يجب الموافقة على الشروط والأحكام أولاً', Colors.orange.shade700);
      return;
    }
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _isLoading = false);
    _showSnack('تم إنشاء الحساب بنجاح! يرجى تسجيل الدخول.', Colors.green.shade700);
    Navigator.of(context).pop();
  }

  void _googleSignIn() =>
      _showSnack('سيتم تفعيل ميزة Google Sign-In قريباً', _navy3);

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, textAlign: TextAlign.center),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      margin: const EdgeInsets.all(20),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _navy1,
        body: isWide ? _wideLayout() : _narrowLayout(),
      ),
    );
  }

  Widget _wideLayout() => Row(children: [
    Expanded(flex: 5, child: _brandPanel(isNarrow: false)),
    Expanded(flex: 7, child: _formPanel(isNarrow: false)),
  ]);

  Widget _narrowLayout() => Column(children: [
    _brandPanel(isNarrow: true),
    Expanded(child: _formPanel(isNarrow: true)),
  ]);

  // ── Brand panel ──────────────────────────────────────────────────────────
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
          Positioned(top: -50, right: -50,
              child: _glow(_gold.withValues(alpha: 0.15), 220)),
          Positioned(bottom: -60, left: -40,
              child: _glow(_navy3.withValues(alpha: 0.35), 250)),

          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBrandMark(
                    title: 'naboo',
                    logoSize: isNarrow ? 56 : 72,
                    titleFontSize: isNarrow ? 40 : 52,
                    titleColor: const Color(0xFFF2D36B),
                    strokeColor: const Color(0xFF071A36),
                    borderColor: _gold,
                    borderWidth: 2.0,
                  ),
                  SizedBox(height: isNarrow ? 10 : 16),
                  Text('نظام إدارة الأعمال', style: TextStyle(
                    fontSize: isNarrow ? 11 : 13,
                    color: Colors.white.withValues(alpha: 0.6),
                    letterSpacing: 2.5,
                  )),

                  // intentionally simple: logo + name + subtitle only
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, Colors.transparent]),
    ),
  );

  // ── Form panel ───────────────────────────────────────────────────────────
  Widget _formPanel({required bool isNarrow}) {
    return Theme(
      data: _authPanelLightThemeSignup(context),
      child: Container(
        width: double.infinity,
        decoration: isNarrow
            ? const BoxDecoration(
                color: Color(0xFFF7F8FA),
                borderRadius: BorderRadius.zero,
              )
            : const BoxDecoration(color: Color(0xFFF7F8FA)),
        child: AnimatedBuilder(
        animation: _anim,
        builder: (_, child) => Opacity(
          opacity: _fadeAnim.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnim.value), child: child),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isNarrow ? 24 : 48,
              isNarrow ? 28 : 40,
              isNarrow ? 24 : 48,
              isNarrow ? 24 : 40,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header ─────────────────────────────────────────
                    const Text('ابدأ الآن', style: TextStyle(
                      fontSize: 13, color: _gold,
                      letterSpacing: 3, fontWeight: FontWeight.w500,
                    ), textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    const Text('إنشاء حساب جديد', style: TextStyle(
                      fontSize: 26, fontWeight: FontWeight.bold, color: _navy2,
                    ), textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text('أنشئ حسابك للوصول الكامل إلى جميع الميزات',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),

                    // ── Google button ──────────────────────────────────
                    _googleButton(),
                    const SizedBox(height: 20),
                    _divider(),
                    const SizedBox(height: 20),

                    // ── Name ──────────────────────────────────────────
                    _label('الاسم التجاري / الاسم الكامل'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: _navy2),
                      decoration: _dec(
                        hint: 'مثال: مؤسسة البصرة للتجارة',
                        icon: Icons.storefront_outlined,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
                        if (v.trim().length < 3) return 'يجب أن يكون 3 أحرف على الأقل';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Email ─────────────────────────────────────────
                    _label('البريد الإلكتروني'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: _navy2),
                      decoration: _dec(
                        hint: 'example@domain.com',
                        icon: Icons.email_outlined,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'البريد مطلوب';
                        final re = RegExp(
                          r'^[\w\.\-]+@[\w\-]+\.[a-z]{2,}$',
                          caseSensitive: false,
                        );
                        if (!re.hasMatch(v.trim())) return 'صيغة البريد غير صحيحة';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Phone ─────────────────────────────────────────
                    _label('رقم الجوال'),
                    const SizedBox(height: 8),
                    _phoneField(),
                    const SizedBox(height: 16),

                    // ── Password ──────────────────────────────────────
                    _label('كلمة المرور'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscurePass,
                      style: const TextStyle(color: _navy2),
                      decoration: _dec(
                        hint: '8 أحرف على الأقل',
                        icon: Icons.lock_outline_rounded,
                        suffix: _eyeToggle(
                          visible: !_obscurePass,
                          onTap: () => setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'كلمة المرور مطلوبة';
                        if (v.length < 8) return '8 أحرف على الأقل';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // ── Confirm password ──────────────────────────────
                    _label('تأكيد كلمة المرور'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscureConfirm,
                      style: const TextStyle(color: _navy2),
                      decoration: _dec(
                        hint: 'أعد إدخال كلمة المرور',
                        icon: Icons.lock_outline_rounded,
                        suffix: _eyeToggle(
                          visible: !_obscureConfirm,
                          onTap: () =>
                              setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'تأكيد كلمة المرور مطلوب';
                        if (v != _passCtrl.text) return 'كلمتا المرور غير متطابقتين';
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // ── Captcha ───────────────────────────────────────
                    _captchaCard(),
                    const SizedBox(height: 18),

                    // ── Terms ─────────────────────────────────────────
                    _termsRow(),
                    const SizedBox(height: 24),

                    // ── Register button ───────────────────────────────
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _navy2,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22, width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('إنشاء الحساب', style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Back to login ─────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('لديك حساب بالفعل؟',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade600)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: const Text('تسجيل الدخول', style: TextStyle(
                              fontSize: 13,
                              color: _gold,
                              fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  // ── Google button ─────────────────────────────────────────────────────────
  Widget _googleButton() {
    return OutlinedButton(
      onPressed: _googleSignIn,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        backgroundColor: Colors.white,
        foregroundColor: _navy2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 22, height: 22,
            child: CustomPaint(painter: _GoogleLogoPainter()),
          ),
          const SizedBox(width: 10),
          const Text('التسجيل عبر Google', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── OR divider ────────────────────────────────────────────────────────────
  Widget _divider() => Row(children: [
    Expanded(child: Divider(color: Colors.grey.shade300)),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text('أو التسجيل بالبيانات',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
    ),
    Expanded(child: Divider(color: Colors.grey.shade300)),
  ]);

  // ── Phone field with dial code picker ────────────────────────────────────
  Widget _phoneField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Country code picker
        Container(
          height: 52,
          constraints: const BoxConstraints(minWidth: 110),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.zero,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _dialCode,
              icon: Icon(Icons.arrow_drop_down, color: _navy3, size: 20),
              style: const TextStyle(color: _navy2, fontSize: 13),
              items: _countryCodes
                  .map((c) => DropdownMenuItem<String>(
                        value: c['code'],
                        child: Text('${c['flag']}  ${c['code']}',
                            style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _dialCode = v!),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(
                _dialCode == '+964' ? 11 : 15,
              ),
            ],
            style: const TextStyle(color: _navy2),
            decoration: _dec(
              hint: _dialCode == '+964' ? '07701234567' : 'أدخل الرقم',
              icon: Icons.phone_outlined,
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return 'رقم الجوال مطلوب';
              if (_dialCode == '+964') {
                if (!RegExp(r'^07\d{9}$').hasMatch(t)) {
                  return 'رقم عراقي: 11 رقماً يبدأ بـ 07';
                }
              } else if (t.length < 7) {
                return 'رقم غير صحيح';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  // ── Captcha ────────────────────────────────────────────────────────────────
  Widget _captchaCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        border: Border.all(color: const Color(0xFFFFCA28)),
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(children: [
            const Icon(Icons.verified_user_rounded,
                color: Color(0xFF856404), size: 16),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('التحقق من الهوية — أجب على السؤال البسيط',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF856404))),
            ),
            GestureDetector(
              onTap: _refreshCaptcha,
              child: const Row(children: [
                Icon(Icons.refresh_rounded, color: Color(0xFF856404), size: 16),
                SizedBox(width: 4),
                Text('تغيير', style: TextStyle(
                    fontSize: 11, color: Color(0xFF856404))),
              ]),
            ),
          ]),
          const SizedBox(height: 12),

          // Equation + answer field
          Row(children: [
            // Math equation badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: _navy2,
                borderRadius: BorderRadius.zero,
                boxShadow: [BoxShadow(
                  color: _navy2.withValues(alpha: 0.4),
                  blurRadius: 8, offset: const Offset(0, 3),
                )],
              ),
              child: Text(
                '$_captchaA  +  $_captchaB  = ?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _captchaCtrl,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    color: _navy2,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
                textAlign: TextAlign.center,
                decoration: _dec(hint: 'الجواب', icon: Icons.calculate_outlined),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'أدخل الجواب';
                  final n = int.tryParse(v.trim());
                  if (n == null || n != _captchaAnswer) return 'إجابة غير صحيحة';
                  return null;
                },
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Terms checkbox ────────────────────────────────────────────────────────
  Widget _termsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24, height: 24,
          child: Checkbox(
            value: _acceptTerms,
            onChanged: (v) => setState(() => _acceptTerms = v ?? false),
            activeColor: _navy2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.6),
              children: [
                const TextSpan(text: 'أوافق على '),
                WidgetSpan(child: GestureDetector(
                  onTap: () {},
                  child: const Text('شروط الاستخدام', style: TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      decoration: TextDecoration.underline)),
                )),
                const TextSpan(text: '  و  '),
                WidgetSpan(child: GestureDetector(
                  onTap: () {},
                  child: const Text('سياسة الخصوصية', style: TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      decoration: TextDecoration.underline)),
                )),
                const TextSpan(text: ' الخاصة بـ Naboo.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────
  Widget _label(String text) => Text(text, style: const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600, color: _navy2));

  Widget _eyeToggle({required bool visible, required VoidCallback onTap}) =>
      IconButton(
        icon: Icon(visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: Colors.grey, size: 20),
        onPressed: onTap,
      );

  InputDecoration _dec({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      prefixIcon: Icon(icon, color: _navy3, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Colors.grey.shade200)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: _navy3, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: Colors.red, width: 1)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: const BorderSide(color: Colors.red, width: 1.5)),
    );
  }
}

// ── Google logo (4-arc approximation) ─────────────────────────────────────
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width * 0.36;
    final sw = size.width * 0.22;

    final paint = Paint()
      ..style    = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap   = StrokeCap.round;

    const arcs = [
      // [startDeg, sweepDeg, color]
      [-20.0,  202.0, Color(0xFF4285F4)],
      [182.0,  176.0, Color(0xFF34A853)],
      [358.0,  182.0, Color(0xFFFBBC05)],
      [180.0,  -2.0,  Color(0xFFEA4335)],
    ];

    for (final a in arcs) {
      paint.color = a[2] as Color;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r),
        (a[0] as double) * pi / 180,
        (a[1] as double) * pi / 180,
        false,
        paint,
      );
    }

    // Horizontal bar (the "->" part of G)
    paint
      ..color       = const Color(0xFF4285F4)
      ..strokeWidth = sw * 0.9;
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + r, cy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
