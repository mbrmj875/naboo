import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/sale_pos_settings_data.dart';
import '../../providers/loyalty_settings_provider.dart';
import '../../services/app_settings_repository.dart';
import '../../services/business_setup_settings.dart';
import '../../theme/design_tokens.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';

class BusinessSetupWizardScreen extends StatefulWidget {
  const BusinessSetupWizardScreen({
    super.key,
    this.openedFromSettings = false,
  });

  final bool openedFromSettings;

  @override
  State<BusinessSetupWizardScreen> createState() =>
      _BusinessSetupWizardScreenState();
}

class _StepCopy {
  const _StepCopy({
    required this.icon,
    required this.question,
    required this.paragraphs,
    this.examples = const [],
    required this.switchLabel,
    this.footnote,
  });

  final IconData icon;
  final String question;
  final List<String> paragraphs;
  final List<String> examples;
  final String switchLabel;
  final String? footnote;
}

class _BusinessSetupWizardScreenState extends State<BusinessSetupWizardScreen> {
  static const int _stepCount = 9;

  final _repo = AppSettingsRepository.instance;
  bool _loading = true;
  bool _saving = false;
  int _step = 0;

  bool _enableDebts = false;
  bool _enableInstallments = false;
  bool _enableWeightSales = false;
  bool _enableClothingVariants = false;
  bool _enableServices = true;
  bool _enableCustomers = true;
  bool _enableLoyalty = false;
  bool _enableTaxOnSale = false;
  bool _enableInvoiceDiscount = true;

  late final List<_StepCopy> _copy;

  @override
  void initState() {
    super.initState();
    _copy = _buildCopy();
    _load();
  }

  List<_StepCopy> _buildCopy() {
    return [
      const _StepCopy(
        icon: Icons.people_alt_outlined,
        question: 'هل تستخدم العملاء في نشاطك؟',
        paragraphs: [
          'عند التفعيل تظهر لك وحدة العملاء الكاملة: بطاقة لكل عميل، سجل مشتريات، ومتابعة سريعة من الفاتورة.',
          'يمكنك ربط كل عملية بيع بعميل معيّن، ما يسهّل التقارير لاحقاً ويوحّد تجربة المتجر أمام الزبائن الذين يتكررون.',
          'إذا عملت بيعاً نقدياً سريعاً دون اسم، يبقى ذلك متاحاً؛ التفعيل لا يفرض اختيار عميل في كل مرة.',
        ],
        examples: [
          'مثال: زبون دائم يشتري يومياً، تحفظ اسمه وترى آخر فواتيره بسرعة.',
          'مثال: عند وجود دين أو نقاط ولاء، تظهر مرتبطة بنفس العميل بدل البحث اليدوي.',
        ],
        switchLabel: 'تفعيل وحدة العملاء',
      ),
      const _StepCopy(
        icon: Icons.card_giftcard_outlined,
        question: 'هل تريد برنامج نقاط الولاء؟',
        paragraphs: [
          'الولاء يمنح الزبائن نقاطاً عند الشراء، ويمكنهم استبدالها وفق القواعد التي تضبطها من الإعدادات.',
          'البرنامج مرتبط بملفات العملاء؛ كلما كانت بيانات العملاء أوضح، كانت المتابعة أسهل.',
          'يمكنك تشغيل الميزة الآن وتعديل نسب الجمع والاستبدال لاحقاً دون إعادة هذا المعالج.',
        ],
        examples: [
          'مثال: كل 10,000 د.ع تمنح 10 نقاط حسب القاعدة التي تختارها.',
          'مثال: عميل جمع نقاطاً كافية فيستبدلها بخصم في فاتورة لاحقة.',
        ],
        switchLabel: 'تفعيل نقاط الولاء',
        footnote:
            'يتطلّب تفعيل وحدة العملاء في الخطوة السابقة؛ إن لم تكن مفعّلة، لن يعمل الولاء حتى تعيد تفعيل العملاء.',
      ),
      const _StepCopy(
        icon: Icons.receipt_long_outlined,
        question: 'هل تستخدم الضريبة عند البيع؟',
        paragraphs: [
          'عند التفعيل يظهر في فاتورة البيع حقل واضح للضريبة بحيث تحسب مع الإجمالي بطريقة متسقة.',
          'مناسب للمتاجر التي تطبّق نسبة ضريبة معروفة على السلع أو الخدمات.',
          'يمكنك ضبط السلوك التفصيلي من إعدادات نقطة البيع بعد إنهاء الإعداد السريع.',
        ],
        examples: [
          'مثال: فاتورة قيمتها 100,000 د.ع وتضيف عليها نسبة ضريبة محددة.',
          'مثال: الموظف يرى الضريبة والإجمالي النهائي داخل نفس فاتورة البيع.',
        ],
        switchLabel: 'إظهار الضريبة في فاتورة البيع',
      ),
      const _StepCopy(
        icon: Icons.percent_outlined,
        question: 'هل تسمح بالخصم على إجمالي الفاتورة؟',
        paragraphs: [
          'الخصم الإجمالي مفيد للعروض الموسمية أو التفاوض على السعر أمام الزبون دون تعديل سعر كل صنف.',
          'يظهر الحقل في شاشة البيع بحيث يكمّل الفاتورة دون تعقيد إضافي للموظف.',
          'يمكنك إيقافه لاحقاً إذا قررت العمل بأسعار ثابتة فقط.',
        ],
        examples: [
          'مثال: تمنح خصماً عاماً 5,000 د.ع على فاتورة كبيرة.',
          'مثال: عرض خاص ليوم واحد دون تغيير أسعار المنتجات الأساسية.',
        ],
        switchLabel: 'إظهار الخصم الإجمالي في الفاتورة',
      ),
      const _StepCopy(
        icon: Icons.account_balance_wallet_outlined,
        question: 'هل تبيع بالدّين (بيع آجل)؟',
        paragraphs: [
          'التفعيل يفتح لوحة الديون ومتابعة المبالغ المستحقة على كل عميل مع تنبيهات وسقوف يمكن ضبطها.',
          'يناسب التجار الذين يثقون بزبائن معروفين ويحتاجون أرشيفاً واضحاً للآجلات.',
          'لا يمنع البيع النقدي؛ يضيف فقط خيار التسجيل كدين عند اختيار العميل والصلاحيات المناسبة.',
        ],
        examples: [
          'مثال: زبون يأخذ بضاعة اليوم ويدفع نهاية الأسبوع.',
          'مثال: تراجع كشف العميل فتجد المبلغ المدفوع والمتبقي بوضوح.',
        ],
        switchLabel: 'تفعيل البيع الآجل والديون',
      ),
      const _StepCopy(
        icon: Icons.calendar_month_outlined,
        question: 'هل تبيع بالتقسيط؟',
        paragraphs: [
          'خطط الأقساط تتيح تقسيم ثمن الفاتورة على دفعات مجدولة مع متابعة ما تبقّى على العميل.',
          'مفيد للسلع ذات السعر المرتفع أو العقود طويلة الأمد.',
          'التفاصيل الدقيقة للجدولة تُدار من الوحدات المخصصة بعد إتمام هذا الإعداد.',
        ],
        examples: [
          'مثال: جهاز قيمته 600,000 د.ع يُدفع على 6 دفعات شهرية.',
          'مثال: ترى الدفعات القادمة والمتأخرة لكل عميل من مكان واحد.',
        ],
        switchLabel: 'تفعيل البيع بالتقسيط',
      ),
      const _StepCopy(
        icon: Icons.scale_outlined,
        question: 'هل تبيع بالوزن (كيلو، غرام، إلخ)؟',
        paragraphs: [
          'التفعيل يجهّز واجهة البيع والباركود بحيث تدعم أوزاناً وكميات عشرية حيث يلزم.',
          'مناسب للمواد الغذائية، الحديد، أو أي نشاط يعتمد الميزان.',
          'يمكن ضبط أنماط الباركود بالوزن من الإعدادات المتقدمة بعد متابعة هذا المعالج.',
        ],
        examples: [
          'مثال: بيع 1.250 كغم من منتج بدلاً من قطعة واحدة.',
          'مثال: قراءة باركود ميزان يحتوي وزن المنتج وسعره تلقائياً.',
        ],
        switchLabel: 'تفعيل البيع بالوزن',
      ),
      const _StepCopy(
        icon: Icons.checkroom_rounded,
        question: 'هل تبيع ملابس (ألوان ومقاسات)؟',
        paragraphs: [
          'التفعيل يجهّز شاشات المنتجات والبيع لدعم تباين الأصناف (الألوان والقياسات المختلفة لنفس الموديل).',
          'يسهل تتبع مخزون كل لون أو مقاس على حدة وإظهار نافذة التحديد التفاعلية عند البيع.',
        ],
        examples: [
          'مثال: قميص متوفر باللون الأزرق والأسود، وبقياسات S و M و L.',
          'مثال: اختيار قطعة الملابس يفتح نافذة منبثقة سريعة لاختيار المقاس واللون المتاحين بالمخزون.',
        ],
        switchLabel: 'تفعيل وحدة الملابس والقياسات',
      ),
      const _StepCopy(
        icon: Icons.handyman_rounded,
        question: 'هل تقدّم خدمات معينة (صيانة، ورشة، إلخ)؟',
        paragraphs: [
          'التفعيل يظهر وحدة الخدمات والصيانة كاملة: تذاكر عمل، طلبات الصيانة، ودليل الخدمات والأسعار.',
          'مفيدة للمشاغل، مراكز الصيانة، وأي نشاط يعتمد تقديم خدمات للعملاء إلى جانب بيع المواد.',
        ],
        examples: [
          'مثال: فتح تذكرة صيانة لجهاز كمبيوتر أو سيارة وتعيين حالة العمل.',
          'مثال: إضافة خدمة تركيب أو صيانة سريعة لفاتورة البيع.',
        ],
        switchLabel: 'تفعيل الخدمات وتذاكر الصيانة',
      ),
    ];
  }

  Future<void> _load() async {
    final d = await BusinessSetupSettingsData.load(_repo);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _enableDebts = d.enableDebts;
      _enableInstallments = d.enableInstallments;
      _enableWeightSales = d.enableWeightSales;
      _enableClothingVariants = d.enableClothingVariants;
      _enableServices = d.enableServices;
      _enableCustomers = d.enableCustomers;
      _enableLoyalty = d.enableCustomers ? d.enableLoyalty : false;
      _enableTaxOnSale = d.enableTaxOnSale;
      _enableInvoiceDiscount = d.enableInvoiceDiscount;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final d = BusinessSetupSettingsData(
      onboardingCompleted: true,
      enableDebts: _enableDebts,
      enableInstallments: _enableInstallments,
      enableWeightSales: _enableWeightSales,
      enableClothingVariants: _enableClothingVariants,
      enableServices: _enableServices,
      enableCustomers: _enableCustomers,
      enableLoyalty: _enableLoyalty,
      enableTaxOnSale: _enableTaxOnSale,
      enableInvoiceDiscount: _enableInvoiceDiscount,
    );
    await d.save(_repo);
    BusinessFeaturesRevision.bump();

    try {
      final raw =
          await AppSettingsRepository.instance.get(SalePosSettingsKeys.jsonKey);
      final current = SalePosSettingsData.fromJsonString(raw);
      final next = current.copyWith(
        enableTaxOnSale: _enableTaxOnSale,
        enableInvoiceDiscount: _enableInvoiceDiscount,
        allowCredit: _enableDebts,
        allowInstallment: _enableInstallments,
      );
      await AppSettingsRepository.instance
          .set(SalePosSettingsKeys.jsonKey, next.toJsonString());
    } catch (_) {}

    try {
      final prov = context.read<LoyaltySettingsProvider>();
      final next = prov.data.copyWith(enabled: _enableLoyalty);
      await prov.save(next);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _saving = false);
    if (widget.openedFromSettings) {
      Navigator.of(context).pop(true);
    } else {
      unawaited(Navigator.of(context).pushReplacementNamed('/open-shift'));
    }
  }

  bool _valueForStep(int index) {
    switch (index) {
      case 0:
        return _enableCustomers;
      case 1:
        return _enableLoyalty;
      case 2:
        return _enableTaxOnSale;
      case 3:
        return _enableInvoiceDiscount;
      case 4:
        return _enableDebts;
      case 5:
        return _enableInstallments;
      case 6:
        return _enableWeightSales;
      case 7:
        return _enableClothingVariants;
      case 8:
        return _enableServices;
      default:
        return false;
    }
  }

  void _setValueForStep(int index, bool v) {
    setState(() {
      switch (index) {
        case 0:
          _enableCustomers = v;
          if (!v) {
            _enableLoyalty = false;
          }
          break;
        case 1:
          _enableLoyalty = v;
          break;
        case 2:
          _enableTaxOnSale = v;
          break;
        case 3:
          _enableInvoiceDiscount = v;
          break;
        case 4:
          _enableDebts = v;
          break;
        case 5:
          _enableInstallments = v;
          break;
        case 6:
          _enableWeightSales = v;
          break;
        case 7:
          _enableClothingVariants = v;
          break;
        case 8:
          _enableServices = v;
          break;
      }
    });
  }

  bool _switchEnabledForStep(int index) {
    if (index == 1) return _enableCustomers;
    return true;
  }

  void _goNext() {
    if (_step < _stepCount - 1) {
      setState(() => _step++);
    } else {
      _save();
    }
  }

  void _goPrev() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.openedFromSettings ? 'ميزات المتجر' : 'إعداد سريع للتطبيق';

    return PopScope(
      canPop: widget.openedFromSettings && _step == 0 && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) return;
        if (_step > 0) setState(() => _step--);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: GlassBackground(
          backgroundImage: const AssetImage('assets/images/splash_bg.png'),
          overlayOpacity: 0.38,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            resizeToAvoidBottomInset: true,
            body: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentGold,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final layout = ScreenLayout.of(context);
                      final isPhone = layout.isPhoneVariant;
                      final compact = isPhone ||
                          layout.isCompactHeight ||
                          constraints.maxHeight < 720;
                      final mediaPadding = MediaQuery.paddingOf(context);
                      final horizontalPadding = layout.isNarrowWidth
                          ? 12.0
                          : (isPhone ? 16.0 : 20.0);
                      return Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: horizontalPadding,
                          end: horizontalPadding,
                          top: mediaPadding.top + (compact ? 10 : 16),
                          bottom: mediaPadding.bottom + (compact ? 12 : 18),
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _topHeader(title, compact: compact),
                                SizedBox(height: compact ? 8 : 12),
                                _progressHeader(compact: compact),
                                SizedBox(height: compact ? 12 : 18),
                                Expanded(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 380),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) {
                                      final slide = Tween<Offset>(
                                        begin: const Offset(0, 0.06),
                                        end: Offset.zero,
                                      ).animate(
                                        CurvedAnimation(
                                          parent: animation,
                                          curve: Curves.easeOutCubic,
                                        ),
                                      );
                                      return FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: slide,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: KeyedSubtree(
                                      key: ValueKey<int>(_step),
                                      child: _glassQuestionCard(
                                        _copy[_step],
                                        _step,
                                        compact: compact,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: compact ? 12 : 16),
                                _navActions(compact: compact),
                                if (!widget.openedFromSettings) ...[
                                  SizedBox(height: compact ? 8 : 10),
                                  Text(
                                    'يمكنك تغيير هذه الخيارات لاحقاً من الإعدادات ← ميزات المتجر.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: compact ? 10.5 : 12,
                                      height: 1.35,
                                      color: Colors.white.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
                              ],
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

  Widget _topHeader(String title, {required bool compact}) {
    final showBack = widget.openedFromSettings || _step > 0;
    return SizedBox(
      height: compact ? 34 : 40,
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: showBack
                ? IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: compact ? 17 : 18,
                      color: Colors.white,
                    ),
                    tooltip: 'رجوع',
                    onPressed: _saving
                        ? null
                        : () {
                            if (_step > 0) {
                              _goPrev();
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 16 : 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _progressHeader({required bool compact}) {
    final progress = (_step + 1) / _stepCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'الخطوة ${_step + 1} من $_stepCount',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.85),
            letterSpacing: 0.2,
          ),
        ),
        SizedBox(height: compact ? 8 : 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            color: AppColors.accentGold,
          ),
        ),
        SizedBox(height: compact ? 10 : 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_stepCount, (i) {
            final active = i == _step;
            final done = i < _step;
            return Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                width: active ? (compact ? 18 : 22) : 7,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: done || active
                      ? AppColors.accentGold.withValues(alpha: active ? 1 : 0.45)
                      : Colors.white.withValues(alpha: 0.22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _glassQuestionCard(
    _StepCopy c,
    int stepIndex, {
    required bool compact,
  }) {
    final value = _valueForStep(stepIndex);
    final switchOn = _switchEnabledForStep(stepIndex);
    final cardPadding = compact ? 18.0 : 22.0;
    final titleSize = compact ? 18.0 : 21.0;
    final bodySize = compact ? 12.8 : 14.0;
    final iconSize = compact ? 24.0 : 28.0;
    final paragraphs = c.paragraphs;

    return GlassSurface(
      borderRadius: BorderRadius.all(Radius.circular(compact ? 18 : 22)),
      blurSigma: 16,
      tintColor: AppGlass.surfaceTintStrong,
      strokeColor: AppGlass.stroke,
      padding: EdgeInsetsDirectional.all(cardPadding),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: EdgeInsets.all(compact ? 10 : 12),
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(compact ? 12 : 14),
                  border: Border.all(
                    color: AppColors.accentGold.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(c.icon, color: AppColors.accentGold, size: iconSize),
              ),
            ),
            SizedBox(height: compact ? 14 : 18),
            Text(
              c.question,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.bold,
                height: compact ? 1.28 : 1.35,
                color: const Color(0xFFF8FAFC),
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            for (var i = 0; i < paragraphs.length; i++) ...[
              if (i > 0) SizedBox(height: compact ? 7 : 10),
              Text(
                paragraphs.elementAt(i),
                style: TextStyle(
                  fontSize: bodySize,
                  height: compact ? 1.45 : 1.55,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ],
            if (c.examples.isNotEmpty) ...[
              SizedBox(height: compact ? 14 : 18),
              Text(
                'أمثلة عملية',
                style: TextStyle(
                  color: AppColors.accentGold,
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: compact ? 8 : 10),
              for (final example in c.examples) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsetsDirectional.only(top: 2),
                        child: Icon(
                          Icons.check_circle_outline,
                          size: compact ? 15 : 16,
                          color: AppColors.accentGold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          example,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: compact ? 12.3 : 13.2,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            if (c.footnote != null &&
                stepIndex == 1 &&
                !_enableCustomers) ...[
              SizedBox(height: compact ? 10 : 14),
              Container(
                width: double.infinity,
                padding: EdgeInsetsDirectional.all(compact ? 10 : 12),
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.accentBlue.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 20,
                      color: AppColors.accentBlue.withValues(alpha: 0.95),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.footnote!,
                        style: TextStyle(
                          fontSize: compact ? 11.8 : 12.5,
                          height: 1.45,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: compact ? 14 : 22),
            Divider(color: Colors.white.withValues(alpha: 0.14)),
            SizedBox(height: compact ? 10 : 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    c.switchLabel,
                    style: TextStyle(
                      fontSize: compact ? 13.5 : 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: value,
                  onChanged: switchOn && !_saving
                      ? (v) => _setValueForStep(stepIndex, v)
                      : null,
                  activeTrackColor: AppColors.accentGold.withValues(alpha: 0.55),
                  activeColor: AppColors.accentGold,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _navActions({required bool compact}) {
    final isLast = _step >= _stepCount - 1;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: (_saving || _step == 0) ? null : _goPrev,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white.withValues(alpha: 0.45),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.04),
              padding: EdgeInsets.symmetric(vertical: compact ? 12 : 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 12 : 14),
              ),
            ),
            child: const Text('السابق'),
          ),
        ),
        SizedBox(width: compact ? 10 : 12),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _saving ? null : _goNext,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentGold,
              foregroundColor: AppColors.primary,
              padding: EdgeInsets.symmetric(vertical: compact ? 12 : 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 12 : 14),
              ),
            ),
            child: _saving && isLast
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Text(isLast
                    ? (widget.openedFromSettings ? 'حفظ' : 'متابعة')
                    : 'التالي'),
          ),
        ),
      ],
    );
  }
}
