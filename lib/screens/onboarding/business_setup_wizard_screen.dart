import 'package:flutter/material.dart';

import '../../services/app_settings_repository.dart';
import '../../services/business_setup_settings.dart';
import '../../models/sale_pos_settings_data.dart';
import '../../providers/loyalty_settings_provider.dart';
import 'package:provider/provider.dart';

class BusinessSetupWizardScreen extends StatefulWidget {
  const BusinessSetupWizardScreen({super.key});

  @override
  State<BusinessSetupWizardScreen> createState() =>
      _BusinessSetupWizardScreenState();
}

class _BusinessSetupWizardScreenState extends State<BusinessSetupWizardScreen> {
  static const Color _navy2 = Color(0xFF0D1F3C);
  static const Color _gold = Color(0xFFB8960C);

  final _repo = AppSettingsRepository.instance;
  bool _loading = true;
  bool _saving = false;

  bool _enableDebts = false;
  bool _enableInstallments = false;
  bool _enableWeightSales = false;
  bool _enableCustomers = true;
  bool _enableLoyalty = false;
  bool _enableTaxOnSale = false;
  bool _enableInvoiceDiscount = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await BusinessSetupSettingsData.load(_repo);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _enableDebts = d.enableDebts;
      _enableInstallments = d.enableInstallments;
      _enableWeightSales = d.enableWeightSales;
      _enableCustomers = d.enableCustomers;
      _enableLoyalty = d.enableLoyalty;
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
      enableCustomers: _enableCustomers,
      enableLoyalty: _enableLoyalty,
      enableTaxOnSale: _enableTaxOnSale,
      enableInvoiceDiscount: _enableInvoiceDiscount,
    );
    await d.save(_repo);

    // طبّق إعدادات البيع (خصم/ضريبة) مباشرة.
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

    // طبّق تفعيل الولاء مباشرة.
    try {
      final prov = context.read<LoyaltySettingsProvider>();
      final next = prov.data.copyWith(enabled: _enableLoyalty);
      await prov.save(next);
    } catch (_) {}

    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pushReplacementNamed('/open-shift');
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _navy2,
          elevation: 0.5,
          title: const Text('إعداد سريع للتطبيق'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _hero(),
                        const SizedBox(height: 16),
                        _toggleCard(
                          title: 'هل تستخدم العملاء؟',
                          subtitle:
                              'يعرض وحدة العملاء وربطها بالفواتير والديون ونقاط الولاء.',
                          value: _enableCustomers,
                          onChanged: (v) => setState(() => _enableCustomers = v),
                        ),
                        const SizedBox(height: 12),
                        _toggleCard(
                          title: 'هل تريد تفعيل نقاط الولاء؟',
                          subtitle:
                              'يفعّل برنامج نقاط الولاء (جمع واستبدال) وربطه بالعملاء.',
                          value: _enableLoyalty,
                          onChanged: (v) => setState(() => _enableLoyalty = v),
                        ),
                        const SizedBox(height: 12),
                        _toggleCard(
                          title: 'هل تستخدم الضريبة عند البيع؟',
                          subtitle: 'يظهر حقل الضريبة في فاتورة البيع.',
                          value: _enableTaxOnSale,
                          onChanged: (v) => setState(() => _enableTaxOnSale = v),
                        ),
                        const SizedBox(height: 12),
                        _toggleCard(
                          title: 'هل تسمح بالخصم على الفاتورة؟',
                          subtitle: 'يظهر حقل الخصم الإجمالي في فاتورة البيع.',
                          value: _enableInvoiceDiscount,
                          onChanged: (v) =>
                              setState(() => _enableInvoiceDiscount = v),
                        ),
                        const SizedBox(height: 12),
                        _toggleCard(
                          title: 'هل تبيع بالدَّين (آجل)؟',
                          subtitle:
                              'يفعّل لوحة الديون، السقوف، والتنبيهات المرتبطة بعملائك.',
                          value: _enableDebts,
                          onChanged: (v) => setState(() => _enableDebts = v),
                        ),
                        const SizedBox(height: 12),
                        _toggleCard(
                          title: 'هل تبيع بالتقسيط؟',
                          subtitle:
                              'يفعّل خطط الأقساط، الجداول، والمتابعة حسب العميل.',
                          value: _enableInstallments,
                          onChanged: (v) =>
                              setState(() => _enableInstallments = v),
                        ),
                        const SizedBox(height: 12),
                        _toggleCard(
                          title: 'هل تبيع بالوزن؟',
                          subtitle:
                              'يفعّل إعدادات الوزن (مثل الباركود بالوزن) وخيارات إدخال الكمية بالوزن.',
                          value: _enableWeightSales,
                          onChanged: (v) =>
                              setState(() => _enableWeightSales = v),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _navy2,
                              foregroundColor: Colors.white,
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('متابعة'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'يمكنك تغيير هذه الخيارات لاحقاً من الإعدادات.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
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

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.tune_rounded, size: 44, color: _gold),
          const SizedBox(height: 10),
          const Text(
            'خلّ التطبيق يناسب شغلك',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _navy2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'أجب عن 3 أسئلة سريعة لنفعّل الميزات المناسبة لتجارتك.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 14, end: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.only(top: 12, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _navy2,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Switch(
            value: value,
            activeColor: _gold,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

