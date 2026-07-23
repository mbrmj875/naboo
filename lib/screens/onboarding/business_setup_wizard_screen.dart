import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/auth_provider.dart';
import '../../providers/business_features_provider.dart';
import '../../services/app_settings_repository.dart';
import '../../services/auth/owner_business_vertical_cloud_service.dart';
import '../../services/business_setup_settings.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../services/password_hashing.dart';
import '../../theme/design_tokens.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_surface.dart';
import '../../utils/auth_validators.dart';
import '../../utils/pin_input_constraints.dart';

class BusinessSetupWizardScreen extends StatefulWidget {
  const BusinessSetupWizardScreen({super.key, this.openedFromSettings = false});

  final bool openedFromSettings;

  @override
  State<BusinessSetupWizardScreen> createState() => _BusinessSetupWizardScreenState();
}

class _VerticalOption {
  const _VerticalOption({
    required this.vertical,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  final String vertical;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
}

class _BusinessSetupWizardScreenState extends State<BusinessSetupWizardScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _exiting = false;
  bool _verticalSelectionLocked = false;
  int _step = 0;

  String _businessVertical = BusinessVertical.generalRetail;
  
  // Feature toggles for settings view
  bool _enableDebts = false;
  bool _enableInstallments = false;
  bool _enableWeightSales = false;
  bool _enableClothingVariants = false;
  bool _enableServices = true;
  bool _enablePos = true;
  bool _enableCustomers = true;
  bool _enableLoyalty = false;
  bool _enableTaxOnSale = false;
  bool _enableInvoiceDiscount = true;

  // First Cashier fields
  final _cashierNameCtrl = TextEditingController();
  final _cashierPinCtrl = TextEditingController();

  static const List<_VerticalOption> _verticalOptions = [
    _VerticalOption(
      vertical: BusinessVertical.oilChange,
      title: BusinessVertical.oilChangeDisplayNameAr,
      subtitle: 'بطاقات خدمة، ديون عملاء، بدون نقطة بيع تقليدية',
      icon: Icons.opacity_rounded,
      accentColor: AppColors.accentBlue,
    ),
    _VerticalOption(
      vertical: BusinessVertical.supermarket,
      title: 'سوبر ماركت ومواد غذائية',
      subtitle: 'بيع بالوزن، ولاء، وديون آجلة',
      icon: Icons.shopping_cart_outlined,
      accentColor: Color(0xFF34C759),
    ),
    _VerticalOption(
      vertical: BusinessVertical.clothingStore,
      title: 'محل ملابس وأحذية',
      subtitle: 'ألوان ومقاسات، ولاء، وديون',
      icon: Icons.checkroom_rounded,
      accentColor: Color(0xFFAF52DE),
    ),
    _VerticalOption(
      vertical: BusinessVertical.pharmacy,
      title: 'صيدلية',
      subtitle: 'نقطة بيع، ولاء، وديون',
      icon: Icons.local_pharmacy_rounded,
      accentColor: Color(0xFF5856D6),
    ),
    _VerticalOption(
      vertical: BusinessVertical.restaurantCafe,
      title: 'مطعم / كافيه',
      subtitle: 'نقطة بيع، ولاء، وخدمات',
      icon: Icons.restaurant_rounded,
      accentColor: Color(0xFFFF3B30),
    ),
    _VerticalOption(
      vertical: BusinessVertical.generalRetail,
      title: 'محل تجاري عام',
      subtitle: 'تخصيص كامل لكل ميزات المتجر',
      icon: Icons.storefront_rounded,
      accentColor: Color(0xFFFF9500),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cashierNameCtrl.dispose();
    _cashierPinCtrl.dispose();
    super.dispose();
  }

  void _exitToEmployeeGate() {
    if (!mounted || _exiting) return;
    _exiting = true;
    setState(() => _loading = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/employee-gate');
    });
  }

  Future<void> _load() async {
    if (!widget.openedFromSettings &&
        Supabase.instance.client.auth.currentUser != null) {
      try {
        await context.read<AuthProvider>().hydrateCloudAccountData(
          timeout: const Duration(seconds: 15),
          forceImportOnPull: true,
        );
      } catch (_) {}
    }

    final featuresProv = context.read<BusinessFeaturesProvider>();
    await featuresProv.refresh();
    if (!featuresProv.isLoaded) {
      await featuresProv.refresh();
    }
    if (!mounted) return;

    if (!widget.openedFromSettings && featuresProv.data.onboardingCompleted) {
      _exitToEmployeeGate();
      return;
    }

    if (!widget.openedFromSettings) {
      final cloudVertical =
          await OwnerBusinessVerticalCloudService.fetchForCurrentUser();
      if (cloudVertical != null && BusinessVertical.isKnown(cloudVertical)) {
        await OwnerBusinessVerticalCloudService.applyToLocalIfNeeded();
        await featuresProv.refresh();
        if (!mounted) return;
        if (featuresProv.data.onboardingCompleted) {
          _exitToEmployeeGate();
          return;
        }
        _applyVerticalDefaults();
        setState(() {
          _loading = false;
          _businessVertical = cloudVertical;
          _verticalSelectionLocked = true;
          _step = 1;
        });
        return;
      }
      if (await BusinessSetupSettingsData.isVerticalLocked(
        AppSettingsRepository.instance,
      )) {
        final d = featuresProv.data;
        setState(() {
          _loading = false;
          _businessVertical = d.businessVertical;
          _verticalSelectionLocked = true;
          _step = 1;
        });
        return;
      }
    }

    final d = featuresProv.data;
    setState(() {
      _loading = false;
      _businessVertical = d.businessVertical;
      _enableDebts = d.enableDebts;
      _enableInstallments = d.enableInstallments;
      _enableWeightSales = d.enableWeightSales;
      _enableClothingVariants = d.enableClothingVariants;
      _enableServices = d.enableServices;
      _enablePos = d.enablePos;
      _enableCustomers = d.enableCustomers;
      _enableLoyalty = d.enableLoyalty;
      _enableTaxOnSale = d.enableTaxOnSale;
      _enableInvoiceDiscount = d.enableInvoiceDiscount;
    });
  }

  void _applyVerticalDefaults() {
    // Reset defaults based on selected vertical
    switch (_businessVertical) {
      case BusinessVertical.oilChange:
        _enableDebts = true;
        _enableInstallments = false;
        _enableWeightSales = false;
        _enableClothingVariants = false;
        _enableServices = true;
        _enablePos = false;
        _enableCustomers = true;
        _enableLoyalty = true;
        break;
      case BusinessVertical.supermarket:
        _enableDebts = true;
        _enableInstallments = false;
        _enableWeightSales = true;
        _enableClothingVariants = false;
        _enableServices = false;
        _enablePos = true;
        _enableCustomers = true;
        _enableLoyalty = true;
        break;
      case BusinessVertical.clothingStore:
        _enableDebts = true;
        _enableInstallments = false;
        _enableWeightSales = false;
        _enableClothingVariants = true;
        _enableServices = false;
        _enablePos = true;
        _enableCustomers = true;
        _enableLoyalty = true;
        break;
      case BusinessVertical.pharmacy:
        _enableDebts = true;
        _enableInstallments = false;
        _enableWeightSales = false;
        _enableClothingVariants = false;
        _enableServices = false;
        _enablePos = true;
        _enableCustomers = true;
        _enableLoyalty = true;
        break;
      case BusinessVertical.restaurantCafe:
        _enableDebts = true;
        _enableInstallments = false;
        _enableWeightSales = false;
        _enableClothingVariants = false;
        _enableServices = true;
        _enablePos = true;
        _enableCustomers = true;
        _enableLoyalty = true;
        break;
      case BusinessVertical.generalRetail:
      default:
        _enableDebts = true;
        _enableInstallments = true;
        _enableWeightSales = true;
        _enableClothingVariants = true;
        _enableServices = true;
        _enablePos = true;
        _enableCustomers = true;
        _enableLoyalty = true;
        break;
    }
  }

  Future<void> _save() async {
    if (!widget.openedFromSettings && _step == 1) {
      final name = _cashierNameCtrl.text.trim();
      final pin = _cashierPinCtrl.text.trim();
      if (name.isEmpty || pin.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال اسم الموظف ورمز الدخول (PIN)')),
        );
        return;
      }
      if (!AuthValidators.isValidPin(pin)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(PinInputConstraints.invalidMessage)),
        );
        return;
      }
    }

    setState(() => _saving = true);

    if (!widget.openedFromSettings) {
      _applyVerticalDefaults();
    }

    final d = BusinessSetupSettingsData(
      onboardingCompleted: true,
      businessVertical: _businessVertical,
      enableDebts: _enableDebts,
      enableInstallments: _enableInstallments,
      enableWeightSales: _enableWeightSales,
      enableClothingVariants: _enableClothingVariants,
      enableOilChange: _enableServices && _businessVertical == BusinessVertical.oilChange,
      enableCarWash: false,
      enableRepairServices: _enableServices && _businessVertical != BusinessVertical.oilChange,
      enablePos: _enablePos,
      enableServices: _enableServices,
      enableCustomers: _enableCustomers,
      enableLoyalty: _enableLoyalty,
      enableTaxOnSale: _enableTaxOnSale,
      enableInvoiceDiscount: _enableInvoiceDiscount,
    );
    final featuresProv = context.read<BusinessFeaturesProvider>();
    await featuresProv.save(d);

    if (!widget.openedFromSettings) {
      await OwnerBusinessVerticalCloudService.commitVerticalOnce(
        _businessVertical,
      );
    }

    if (!widget.openedFromSettings) {
      // Insert first cashier
      final salt = PasswordHashing.generateSalt();
      final hash = await PasswordHashing.hashPin(_cashierPinCtrl.text.trim(), salt);
      final email = 'staff_${DateTime.now().millisecondsSinceEpoch}@local.store';
      
      await DatabaseHelper().insertLocalUser(
        username: _cashierNameCtrl.text.trim(),
        email: email,
        phone: '',
        passwordHash: hash,
        passwordSalt: salt,
        role: 'staff',
        displayName: _cashierNameCtrl.text.trim(),
      );
      try {
        await CloudSyncService.instance.syncNow(
          forcePull: false,
          forcePush: true,
          forceImportOnPull: false,
        );
      } catch (_) {
        CloudSyncService.instance.scheduleSyncSoon();
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (widget.openedFromSettings) {
      Navigator.of(context).pop(true);
    } else {
      _exitToEmployeeGate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: GlassBackground(
        backgroundImage: const AssetImage('assets/images/splash_bg.png'),
        overlayOpacity: 0.45,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          resizeToAvoidBottomInset: true,
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.accentGold))
              : SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: widget.openedFromSettings ? 600 : 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 16),
                          Expanded(
                            child: widget.openedFromSettings
                                ? _buildSettingsList()
                                : _buildWizardSteps(),
                          ),
                          const SizedBox(height: 16),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final title = widget.openedFromSettings ? 'ميزات المتجر' : 'إعداد سريع للتطبيق';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (widget.openedFromSettings || (_step > 0 && !_verticalSelectionLocked))
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () {
                if (!widget.openedFromSettings && _step > 0 && !_verticalSelectionLocked) {
                  setState(() => _step--);
                } else {
                  Navigator.of(context).pop();
                }
              },
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildWizardSteps() {
    return IndexedStack(
      index: _step.clamp(0, 1),
      sizing: StackFit.expand,
      children: [
        _buildActivityStep(),
        _buildCashierStep(),
      ],
    );
  }

  Widget _buildActivityStep() {
    return GlassSurface(
      borderRadius: BorderRadius.circular(20),
      blurSigma: 15,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'ما هو نشاطك التجاري؟',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'سنقوم بضبط إعدادات المتجر تلقائياً بناءً على تخصصك',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'يُختار التخصص مرة واحدة لهذا الحساب ويُزامَن مع باقي أجهزتك',
            style: TextStyle(
              color: AppColors.accentGold.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: _verticalOptions.length,
              itemBuilder: (context, index) {
                final option = _verticalOptions[index];
                final isSelected = _businessVertical == option.vertical;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => setState(() => _businessVertical = option.vertical),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? option.accentColor.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.05),
                        border: Border.all(
                          color: isSelected
                              ? option.accentColor
                              : Colors.white.withValues(alpha: 0.1),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(option.icon, color: option.accentColor, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  option.subtitle,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_circle, color: option.accentColor),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashierStep() {
    return GlassSurface(
      borderRadius: BorderRadius.circular(20),
      blurSigma: 15,
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomInset + 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add_alt_1, size: 48, color: AppColors.accentGold),
                  const SizedBox(height: 16),
                  const Text(
                    'إنشاء الكاشير الأول',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'قم بإنشاء حساب للموظف لتتمكن من استخدام التطبيق وبدء الورديات',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _cashierNameCtrl,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'اسم الموظف',
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _cashierPinCtrl,
                    style: const TextStyle(color: Colors.white),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: PinInputConstraints.formatters,
                    decoration: InputDecoration(
                      labelText: 'رمز الدخول (PIN)',
                      hintText: PinInputConstraints.hint,
                      helperText: PinInputConstraints.staffSubtitle,
                      helperMaxLines: 2,
                      labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSettingsList() {
    return GlassSurface(
      borderRadius: BorderRadius.circular(20),
      blurSigma: 15,
      padding: const EdgeInsets.all(20),
      child: ListView(
        children: [
          _buildSwitchRow('إدارة العملاء', _enableCustomers, (v) => setState(() => _enableCustomers = v)),
          _buildSwitchRow('نظام نقاط الولاء', _enableLoyalty, (v) => setState(() => _enableLoyalty = v)),
          _buildSwitchRow('نظام الديون والآجل', _enableDebts, (v) => setState(() => _enableDebts = v)),
          _buildSwitchRow('نظام الأقساط', _enableInstallments, (v) => setState(() => _enableInstallments = v)),
          _buildSwitchRow('البيع بالوزن', _enableWeightSales, (v) => setState(() => _enableWeightSales = v)),
          _buildSwitchRow('إدارة المقاسات والألوان', _enableClothingVariants, (v) => setState(() => _enableClothingVariants = v)),
          _buildSwitchRow('الخدمات (صيانة/توصيل/أخرى)', _enableServices, (v) => setState(() => _enableServices = v)),
          _buildSwitchRow('نقطة البيع الكلاسيكية (POS)', _enablePos, (v) => setState(() => _enablePos = v)),
          _buildSwitchRow('حساب الضريبة على الفاتورة', _enableTaxOnSale, (v) => setState(() => _enableTaxOnSale = v)),
          _buildSwitchRow('تفعيل خصم الفاتورة', _enableInvoiceDiscount, (v) => setState(() => _enableInvoiceDiscount = v)),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.accentGold,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: FilledButton(
        onPressed: _saving ? null : () {
          if (!widget.openedFromSettings && _step == 0) {
            setState(() => _step++);
          } else {
            _save();
          }
        },
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentGold,
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _saving
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
            : Text(
                widget.openedFromSettings ? 'حفظ التعديلات' : (_step == 0 ? 'التالي' : 'إنهاء وبدء العمل'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }
}
