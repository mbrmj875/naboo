import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/license/license_token.dart';
import '../../services/license_service.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../widgets/secure_screen.dart';

const Color _kAccent = Color(0xFF1E3A5F);
const Color _kGold = Color(0xFFB8860B);
const Color _kSilver = Color(0xFF607D8B);
const Color _kTrialTeal = Color(0xFF00897B);

/// نصوص واضحة على بطاقات داكنة (متناسقة مع ثيم التطبيق).
abstract class _SubPlanText {
  static const Color primary = Color(0xFFF8FAFC);
  static const Color body = Color(0xFFE2E8F0);
  static const Color secondary = Color(0xFFCBD5E1);
  static const Color tertiary = Color(0xFF94A3B8);
}

Color _priceHighlightOnDark(Color accent) {
  if (accent == _kAccent) return const Color(0xFF93C5FD);
  if (accent == _kSilver) return const Color(0xFFCFD8DC);
  if (accent == _kGold) return const Color(0xFFFCD34D);
  if (accent == _kTrialTeal) return const Color(0xFF5EEAD4);
  return _SubPlanText.primary;
}

/// عرض للواجهة — نسخ الرقم للواتساب/الاتصال.
const String _kSupportPhoneDisplay = '0780 428 9711';
const String _kSupportPhoneCopy = '07884289711';
const String _kSupportEmail = 'mbrmjbaqer@gmail.com';

String _formatPriceIQD(int price) {
  final s = price.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

class SubscriptionPlansScreen extends StatelessWidget {
  const SubscriptionPlansScreen({
    super.key,
    this.currentPlan,
    this.highlightPlan,
    this.nextRouteName,
  });

  final SubscriptionPlan? currentPlan;
  final SubscriptionPlan? highlightPlan;
  final String? nextRouteName;

  @override
  Widget build(BuildContext context) {
    final shouldForceContinue = nextRouteName != null;
    return SecureScreen(
      child: PopScope(
        canPop: !shouldForceContinue,
        child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: shouldForceContinue
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: _SubPlanText.primary,
                    size: 18,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
          title: const Text(
            'خطط الاشتراك',
            style: TextStyle(
              color: _SubPlanText.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: GlassBackground(
          backgroundImage: const AssetImage('assets/images/splash_bg.png'),
          child: ListenableBuilder(
            listenable: LicenseService.instance,
            builder: (context, _) {
              final jwtMode = LicenseService.instance.usesSignedLicenseJwt;
              return SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    40 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        children: [
                          const Text(
                            'اختر الخطة المناسبة لنشاطك',
                            style: TextStyle(
                              color: _SubPlanText.primary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            jwtMode
                                ? 'البطاقات أدناه للمقارنة والأسعار فقط. بعد الدفع تستلم رمزاً موقّعاً (JWT) — الصقه في حقل التفعيل أسفل البطاقات مباشرة.'
                                : 'البطاقة الأولى: تجربة تلقائية 15 يوماً (جهازان). البطاقات التالية خطط مدفوعة — بعد الدفع تُدخل المفتاح في الحقل الموحّد أسفل الصفحة.',
                            style: const TextStyle(
                              color: _SubPlanText.secondary,
                              fontSize: 13,
                              height: 1.45,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          _PlanCard(
                            plan: SubscriptionPlan.trial,
                            isPopular: false,
                            isCurrent: currentPlan?.key == 'trial',
                            accentColor: _kTrialTeal,
                            icon: Icons.timer_outlined,
                            jwtMode: jwtMode,
                          ),
                          const SizedBox(height: 14),
                          _PlanCard(
                            plan: SubscriptionPlan.basic,
                            isPopular: false,
                            isCurrent: currentPlan?.key == 'basic',
                            accentColor: _kSilver,
                            icon: Icons.store_outlined,
                            jwtMode: jwtMode,
                          ),
                          const SizedBox(height: 14),
                          _PlanCard(
                            plan: SubscriptionPlan.pro,
                            isPopular: true,
                            isCurrent: currentPlan?.key == 'pro',
                            accentColor: _kAccent,
                            icon: Icons.business_outlined,
                            jwtMode: jwtMode,
                          ),
                          const SizedBox(height: 14),
                          _PlanCard(
                            plan: SubscriptionPlan.unlimited,
                            isPopular: false,
                            isCurrent: currentPlan?.key == 'unlimited',
                            accentColor: _kGold,
                            icon: Icons.all_inclusive_outlined,
                            jwtMode: jwtMode,
                          ),
                          const SizedBox(height: 24),
                          if (jwtMode)
                            const _JwtActivatePanel()
                          else
                            const _LegacyLicenseKeyPanel(),
                          const SizedBox(height: 24),
                          GlassSurface(
                            borderRadius:
                                const BorderRadius.all(Radius.circular(16)),
                            tintColor: AppGlass.surfaceTint,
                            strokeColor: AppGlass.stroke,
                            blurSigma: 12,
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: AppColors.accentGold,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'كيفية الاشتراك',
                                      style: TextStyle(
                                        color: _SubPlanText.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  jwtMode
                                      ? '١. تواصل مع فريق NaBoo عبر الطرق أدناه\n'
                                            '٢. أكمل الدفع للخطة التي تريدها\n'
                                            '٣. استلم رمز التفعيل الكامل (JWT) من الإدارة\n'
                                            '٤. الصق الرمز في الحقل الموحّد أسفل بطاقات الخطط — الخطة وحد الأجهزة يُستنتجان من الرمز'
                                      : '١. تواصل مع فريق NaBoo عبر الطرق أدناه\n'
                                            '٢. أخبرنا بالخطة التي تريدها وأكمل الدفع\n'
                                            '٣. استلم مفتاح الترخيص من الإدارة\n'
                                            '٤. الصق المفتاح في الحقل الموحّد أسفل بطاقات الخطط ثم اضغط «تفعيل المفتاح»',
                                  style: const TextStyle(
                                    color: _SubPlanText.body,
                                    fontSize: 13,
                                    height: 1.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const _ContactRow(
                            icon: Icons.phone_outlined,
                            label: 'واتساب / هاتف',
                            value: _kSupportPhoneDisplay,
                            copyValue: _kSupportPhoneCopy,
                          ),
                          const SizedBox(height: 10),
                          const _ContactRow(
                            icon: Icons.email_outlined,
                            label: 'البريد الإلكتروني',
                            value: _kSupportEmail,
                            copyValue: _kSupportEmail,
                          ),
                          if (shouldForceContinue) ...[
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushReplacementNamed(
                                    nextRouteName!,
                                  );
                                },
                                icon: const Icon(Icons.arrow_back_rounded),
                                label: const Text('متابعة'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      ),
    );
  }
}

class _JwtActivatePanel extends StatefulWidget {
  const _JwtActivatePanel();

  @override
  State<_JwtActivatePanel> createState() => _JwtActivatePanelState();
}

class _JwtActivatePanelState extends State<_JwtActivatePanel> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final key = normalizeJwtCompactInput(_ctrl.text);
    if (key.isEmpty) {
      setState(() => _error = 'الصق رمز الترخيص أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await LicenseService.instance.activateSignedToken(key);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => _error = result.message);
      return;
    }
    await LicenseService.instance.checkLicense(forceRemote: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() => _ctrl.clear());
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      tintColor: AppGlass.surfaceTint,
      strokeColor: AppColors.accent.withOpacity(0.45),
      blurSigma: 12,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.vpn_key_rounded, color: AppColors.accentGold, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تفعيل رمز الترخيص',
                  style: TextStyle(
                    color: _SubPlanText.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'الصق الرمز الكامل الذي أرسلته الإدارة. الخطة وحد الأجهزة يُستنتجان من داخل الرمز وليس من شكل البطاقة.',
            style: TextStyle(
              color: _SubPlanText.secondary,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(
                color: _SubPlanText.primary,
                fontSize: 13,
              ),
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceDark.withOpacity(0.65),
                hintText: 'الصق رمز التفعيل هنا',
                hintStyle: TextStyle(
                  color: _SubPlanText.tertiary.withOpacity(0.85),
                ),
                contentPadding: const EdgeInsetsDirectional.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.accent.withOpacity(0.5),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.borderDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFFFB4AB),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _activate,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('تفعيل الرمز'),
          ),
        ],
      ),
    );
  }
}

class _LegacyLicenseKeyPanel extends StatefulWidget {
  const _LegacyLicenseKeyPanel();

  @override
  State<_LegacyLicenseKeyPanel> createState() => _LegacyLicenseKeyPanelState();
}

class _LegacyLicenseKeyPanelState extends State<_LegacyLicenseKeyPanel> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final key = normalizeJwtCompactInput(_ctrl.text);
    if (key.isEmpty) {
      setState(() => _error = 'الصق مفتاح الترخيص أو رمز التفعيل أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final isJwt = key.split('.').length == 3;
    final result = isJwt
        ? await LicenseService.instance.activateSignedToken(key)
        : await LicenseService.instance.activateLicense(key);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      setState(() => _error = result.message);
      return;
    }
    await LicenseService.instance.checkLicense(forceRemote: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        behavior: SnackBarBehavior.floating,
      ),
    );
    setState(() => _ctrl.clear());
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      tintColor: AppGlass.surfaceTint,
      strokeColor: AppColors.borderDark,
      blurSigma: 12,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.key_rounded, color: AppColors.accentGold, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تفعيل المفتاح',
                  style: TextStyle(
                    color: _SubPlanText.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'الصق مفتاح الترخيص الذي استلمته بعد الدفع، أو رمز JWT إن وُجد. الخطط أعلاه للعرض والمقارنة فقط.',
            style: TextStyle(
              color: _SubPlanText.secondary,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(
                color: _SubPlanText.primary,
                fontSize: 13,
              ),
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceDark.withOpacity(0.65),
                hintText: 'الصق مفتاح الترخيص أو رمز التفعيل',
                hintStyle: TextStyle(
                  color: _SubPlanText.tertiary.withOpacity(0.85),
                ),
                contentPadding: const EdgeInsetsDirectional.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.accent.withOpacity(0.45),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.borderDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFFFB4AB),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _activate,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('تفعيل المفتاح'),
          ),
        ],
      ),
    );
  }
}

/// بطاقة خطة للعرض والمقارنة فقط — التفعيل يتم من الحقل الموحّد أسفل القائمة.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isPopular,
    required this.isCurrent,
    required this.accentColor,
    required this.icon,
    required this.jwtMode,
  });

  final SubscriptionPlan plan;
  final bool isPopular;
  final bool isCurrent;
  final Color accentColor;
  final IconData icon;
  final bool jwtMode;

  @override
  Widget build(BuildContext context) {
    final priceColor = _priceHighlightOnDark(accentColor);
    final strokeColor = isCurrent
        ? accentColor.withOpacity(0.85)
        : isPopular
            ? accentColor.withOpacity(0.55)
            : AppGlass.stroke;

    final inner = GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      tintColor: Color.alphaBlend(
        accentColor.withOpacity(isCurrent ? 0.14 : 0.07),
        AppGlass.surfaceTint,
      ),
      strokeColor: strokeColor,
      strokeWidth: isCurrent ? 2 : 1,
      blurSigma: 14,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.nameAr,
                      style: const TextStyle(
                        color: _SubPlanText.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      plan.devicesLabel,
                      style: const TextStyle(
                        color: _SubPlanText.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (plan.isIntroTrialTier)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'مجاناً',
                      style: TextStyle(
                        color: priceColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      '15 يوماً',
                      style: TextStyle(
                        color: _SubPlanText.tertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _formatPriceIQD(plan.priceIQD),
                          style: TextStyle(
                            color: priceColor,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'د.ع',
                          style: TextStyle(
                            color: _SubPlanText.secondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const Text(
                      'شهرياً',
                      style: TextStyle(
                        color: _SubPlanText.tertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: AppColors.borderDark.withOpacity(0.65)),
          const SizedBox(height: 12),
          ...plan.features.map(
            (f) => Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 2),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      f,
                      style: const TextStyle(
                        color: _SubPlanText.body,
                        fontSize: 13.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (isCurrent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accentColor.withOpacity(0.32),
                  Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor.withOpacity(0.55)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check,
                    size: 16,
                    color: _SubPlanText.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    plan.isIntroTrialTier ? 'تجربتك الحالية' : 'خطتك الحالية',
                    style: const TextStyle(
                      color: _SubPlanText.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              plan.isIntroTrialTier
                  ? 'التجربة تبدأ تلقائياً — لا مفتاح. عند الترقية استلم الرمز من الإدارة والصقه في الحقل الموحّد أسفل البطاقات.'
                  : jwtMode
                      ? 'هذه البطاقة للعرض والمقارنة فقط. بعد الدفع الصق رمز التفعيل (JWT) في الحقل الموحّد أسفل البطاقات مباشرة.'
                      : 'هذه البطاقة للعرض والمقارنة فقط. بعد الدفع الصق مفتاح الترخيص في الحقل الموحّد أسفل البطاقات.',
              style: const TextStyle(
                color: _SubPlanText.secondary,
                fontSize: 12,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        inner,
        if (isPopular)
          PositionedDirectional(
            top: -12,
            start: 0,
            end: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'الأكثر طلباً',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    this.copyValue,
  });
  final IconData icon;
  final String label;
  final String value;
  final String? copyValue;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      tintColor: AppGlass.surfaceTint,
      strokeColor: AppGlass.stroke,
      blurSigma: 10,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: _SubPlanText.secondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _SubPlanText.tertiary,
                    fontSize: 11,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      value,
                      style: const TextStyle(
                        color: _SubPlanText.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.copy_outlined,
              color: _SubPlanText.secondary,
              size: 18,
            ),
            onPressed: () {
              final text = copyValue ?? value;
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    label.contains('هاتف') || label.contains('واتساب')
                        ? 'تم نسخ الرقم'
                        : 'تم نسخ البريد',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            tooltip: 'نسخ',
          ),
        ],
      ),
    );
  }
}
