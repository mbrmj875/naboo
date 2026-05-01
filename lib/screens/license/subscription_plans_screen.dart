import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/license/license_token.dart';
import '../../services/license_service.dart';
import '../../theme/design_tokens.dart';

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
    return PopScope(
      canPop: !shouldForceContinue,
      child: Scaffold(
        backgroundColor: AppColors.surfaceDark,
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
        body: ListenableBuilder(
          listenable: LicenseService.instance,
          builder: (context, _) {
            final jwtMode = LicenseService.instance.usesSignedLicenseJwt;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
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
                        ? 'البطاقات للمقارنة والأسعار فقط. بعد الدفع تستلم رمزاً موقّعاً (JWT): الصقه في المربع أدناه — الخطة وحد الأجهزة يقرآن من الرمز وليس من شكل البطاقة.'
                        : 'البطاقة الأولى: تجربة تلقائية 15 يوماً (جهازان على نفس الحساب). البطاقات التالية خطط مدفوعة (مفتاح من الإدارة).',
                    style: const TextStyle(
                      color: _SubPlanText.secondary,
                      fontSize: 13,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (jwtMode) ...[
                    const SizedBox(height: 20),
                    const _JwtActivatePanel(),
                  ],
                  const SizedBox(height: 28),
                  _PlanCard(
                    plan: SubscriptionPlan.trial,
                    isPopular: false,
                    isCurrent: currentPlan?.key == 'trial',
                    accentColor: _kTrialTeal,
                    icon: Icons.timer_outlined,
                    allowLicenseKeyEntry: false,
                  ),
                  const SizedBox(height: 16),
                  _PlanCard(
                    plan: SubscriptionPlan.basic,
                    isPopular: false,
                    isCurrent: currentPlan?.key == 'basic',
                    accentColor: _kSilver,
                    icon: Icons.store_outlined,
                    allowLicenseKeyEntry: !jwtMode,
                  ),
                  const SizedBox(height: 16),
                  _PlanCard(
                    plan: SubscriptionPlan.pro,
                    isPopular: true,
                    isCurrent: currentPlan?.key == 'pro',
                    accentColor: _kAccent,
                    icon: Icons.business_outlined,
                    allowLicenseKeyEntry: !jwtMode,
                  ),
                  const SizedBox(height: 16),
                  _PlanCard(
                    plan: SubscriptionPlan.unlimited,
                    isPopular: false,
                    isCurrent: currentPlan?.key == 'unlimited',
                    accentColor: _kGold,
                    icon: Icons.all_inclusive_outlined,
                    allowLicenseKeyEntry: !jwtMode,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.cardDark,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.accent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
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
                                    '٤. الصق الرمز في مربع «تفعيل رمز الترخيص» في أعلى الصفحة — لا حاجة للضغط على بطاقة معيّنة'
                              : '١. تواصل مع فريق NaBoo عبر الطرق أدناه\n'
                                    '٢. أخبرنا بالخطة التي تريدها وأكمل الدفع\n'
                                    '٣. استلم مفتاح الترخيص أو رمز التفعيل من الإدارة\n'
                                    '٤. للخطط المدفوعة: اضغط البطاقة ثم الصق المفتاح واضغط «تفعيل المفتاح»',
                          style: const TextStyle(
                            color: _SubPlanText.body,
                            fontSize: 13,
                            height: 1.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _ContactRow(
                    icon: Icons.phone_outlined,
                    label: 'واتساب / هاتف',
                    value: '+964 7XX XXX XXXX',
                  ),
                  const SizedBox(height: 8),
                  _ContactRow(
                    icon: Icons.email_outlined,
                    label: 'البريد الإلكتروني',
                    value: 'support@naboo.app',
                  ),
                  if (shouldForceContinue) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).pushReplacementNamed(nextRouteName!);
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('متابعة'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.vpn_key_rounded, color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              const Expanded(
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
              style: const TextStyle(color: _SubPlanText.primary, fontSize: 13),
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceDark,
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
                  borderSide: BorderSide(color: AppColors.accent, width: 1.5),
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

class _PlanCard extends StatefulWidget {
  const _PlanCard({
    required this.plan,
    required this.isPopular,
    required this.isCurrent,
    required this.accentColor,
    required this.icon,
    this.allowLicenseKeyEntry = true,
  });

  final SubscriptionPlan plan;
  final bool isPopular;
  final bool isCurrent;
  final Color accentColor;
  final IconData icon;

  /// التجربة المجانية لا تُفعَّل بمفتاح — المفتاح للخطط المدفوعة فقط.
  final bool allowLicenseKeyEntry;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _showKeyField = false;
  final _keyCtrl = TextEditingController();
  bool _activating = false;
  String? _error;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final key = normalizeJwtCompactInput(_keyCtrl.text);
    if (key.isEmpty) {
      setState(() => _error = 'الصق مفتاح الترخيص أو رمز التفعيل أولاً');
      return;
    }
    setState(() {
      _activating = true;
      _error = null;
    });
    final isJwt = key.split('.').length == 3;
    final result = isJwt
        ? await LicenseService.instance.activateSignedToken(key)
        : await LicenseService.instance.activateLicense(key);
    if (!mounted) return;
    setState(() => _activating = false);
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
    setState(() {
      _showKeyField = false;
      _keyCtrl.clear();
    });
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final accentColor = widget.accentColor;
    final isCurrent = widget.isCurrent;
    final isPopular = widget.isPopular;
    final allowKey = widget.allowLicenseKeyEntry;
    final tapForKey = allowKey && !isCurrent;

    final cardFill = isCurrent
        ? Color.alphaBlend(accentColor.withOpacity(0.12), AppColors.cardDark)
        : AppColors.cardDark;
    final priceColor = _priceHighlightOnDark(accentColor);

    final inner = Ink(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrent
              ? accentColor.withOpacity(0.85)
              : isPopular
              ? accentColor.withOpacity(0.65)
              : AppColors.borderDark,
          width: isCurrent
              ? 2
              : isPopular
              ? 1.5
              : 1,
        ),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: accentColor, size: 24),
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
                    Text(
                      '15 يوماً',
                      style: const TextStyle(
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
                          _formatPrice(plan.priceIQD),
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
          Divider(color: AppColors.borderDark.withOpacity(0.7)),
          const SizedBox(height: 12),
          ...plan.features.map(
            (f) => Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: accentColor,
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
          const SizedBox(height: 16),
          if (isCurrent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  accentColor.withOpacity(0.35),
                  AppColors.cardDark,
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
          else if (!allowKey) ...[
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: Text(
                plan.isIntroTrialTier
                    ? 'لا يوجد مفتاح للتجربة — تبدأ تلقائياً. عند شراء خطة ستستلم رمز التفعيل وتلصقه في مربع «تفعيل رمز الترخيص» أعلى الصفحة.'
                    : LicenseService.instance.usesSignedLicenseJwt
                    ? 'لتفعيل خطة مدفوعة استخدم المربع أعلاه فقط. هذه البطاقة للمقارنة؛ الخطة وحد الأجهزة يحددهما الرمز وليس مكان لصقه.'
                    : 'للتفعيل تواصل مع الدعم لاستلام المفتاح المناسب لخطتك.',
                style: const TextStyle(
                  color: _SubPlanText.secondary,
                  fontSize: 12,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ] else ...[
            if (!_showKeyField)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 4),
                child: Text(
                  'اضغط على البطاقة لإظهار حقل المفتاح',
                  style: const TextStyle(
                    color: _SubPlanText.tertiary,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_showKeyField) ...[
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _keyCtrl,
                  style: const TextStyle(
                    color: _SubPlanText.primary,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.start,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surfaceDark,
                    hintText: 'الصق مفتاح الترخيص أو رمز التفعيل',
                    hintStyle: TextStyle(
                      color: _SubPlanText.tertiary.withOpacity(0.85),
                    ),
                    contentPadding: const EdgeInsetsDirectional.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: accentColor.withOpacity(0.5),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.borderDark),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: accentColor, width: 1.5),
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
                  textAlign: TextAlign.start,
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _activating ? null : _activate,
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _activating
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
              ),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => _showContactDialog(context, plan),
                  child: Text(
                    'ليس لدي مفتاح — تواصل للدفع',
                    style: TextStyle(
                      color: accentColor.withOpacity(0.95),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.transparent,
          child: tapForKey
              ? InkWell(
                  onTap: () {
                    setState(() {
                      _showKeyField = !_showKeyField;
                      _error = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: inner,
                )
              : inner,
        ),
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

  void _showContactDialog(BuildContext context, SubscriptionPlan plan) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('الاشتراك في خطة ${plan.nameAr}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'السعر: ${plan.priceLabel}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                'الأجهزة: ${plan.devicesLabel}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text('للاشتراك، تواصل معنا:'),
              const SizedBox(height: 12),
              _ContactTile(
                icon: Icons.phone_outlined,
                text: '+964 7XX XXX XXXX',
                onCopy: () {
                  Clipboard.setData(
                    const ClipboardData(text: '+964 7XX XXX XXXX'),
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ الرقم'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              _ContactTile(
                icon: Icons.email_outlined,
                text: 'support@naboo.app',
                onCopy: () {
                  Clipboard.setData(
                    const ClipboardData(text: 'support@naboo.app'),
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ الإيميل'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Row(
        children: [
          Icon(icon, color: _SubPlanText.secondary, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _SubPlanText.tertiary,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: _SubPlanText.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(
              Icons.copy_outlined,
              color: _SubPlanText.secondary,
              size: 18,
            ),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            tooltip: 'نسخ',
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.text,
    required this.onCopy,
  });
  final IconData icon;
  final String text;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCopy,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _kAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.copy_outlined, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
