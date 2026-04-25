import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/installment_settings_data.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';

final _pctFmt = NumberFormat('#,##0.#', 'en');

/// إعدادات تقسيط عامة — هوية بصرية موحّدة مع باقي التطبيق (ثيم، بطاقات، حدود حادة).
class InstallmentSettingsScreen extends StatefulWidget {
  const InstallmentSettingsScreen({super.key});

  @override
  State<InstallmentSettingsScreen> createState() =>
      _InstallmentSettingsScreenState();
}

class _InstallmentSettingsScreenState extends State<InstallmentSettingsScreen> {
  final _db = DatabaseHelper();
  bool _loading = true;
  InstallmentSettingsData _data = InstallmentSettingsData.defaults();

  final _minPct = TextEditingController();
  final _defCount = TextEditingController();
  final _interval = TextEditingController();
  final _saleDefInterest = TextEditingController();

  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _primary => Theme.of(context).colorScheme.primary;
  Color get _onPrimary => Theme.of(context).colorScheme.onPrimary;
  Color get _filterBg =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _outline => Theme.of(context).colorScheme.outline;

  InputDecoration _fieldDecoration({
    required String label,
    String? helper,
    int? helperMaxLines,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: helperMaxLines ?? 2,
      filled: true,
      fillColor: _filterBg,
      isDense: true,
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(
        borderRadius: AppShape.none,
        borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppShape.none,
        borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppShape.none,
        borderSide: BorderSide(color: _primary, width: 1.5),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _minPct.dispose();
    _defCount.dispose();
    _interval.dispose();
    _saleDefInterest.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await _db.getInstallmentSettings();
    if (!mounted) return;
    setState(() {
      _data = s;
      _minPct.text = _pctFmt.format(s.minDownPaymentPercent);
      _defCount.text = '${s.defaultInstallmentCount}';
      _interval.text = '${s.paymentIntervalMonths}';
      _saleDefInterest.text = s.saleDefaultInterestPercent % 1 == 0
          ? '${s.saleDefaultInterestPercent.toInt()}'
          : s.saleDefaultInterestPercent.toStringAsFixed(2);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final minP = double.tryParse(_minPct.text.replaceAll(',', '').trim()) ?? 0;
    final cnt = int.tryParse(_defCount.text.trim()) ?? 1;
    final iv = int.tryParse(_interval.text.trim()) ?? 1;
    final saleInt =
        double.tryParse(_saleDefInterest.text.replaceAll(',', '').trim()) ??
            0;
    if (minP < 0 || minP > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نسبة المقدّم يجب أن تكون بين 0 و 100')),
      );
      return;
    }
    if (cnt < 1 || cnt > 120) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('عدد الأقساط الافتراضي بين 1 و 120')),
      );
      return;
    }
    if (iv < 1 || iv > 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الفترة بين الأقساط: بين 1 و 24 شهراً')),
      );
      return;
    }
    if (saleInt < 0 || saleInt > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('نسبة الفائدة الافتراضية في البيع بين 0 و 100'),
        ),
      );
      return;
    }
    final next = _data.copyWith(
      minDownPaymentPercent: minP,
      defaultInstallmentCount: cnt,
      paymentIntervalMonths: iv,
      saleDefaultInterestPercent: saleInt,
    );
    await _db.saveInstallmentSettings(next);
    CloudSyncService.instance.scheduleSyncSoon();
    if (!mounted) return;
    setState(() => _data = next);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ إعدادات التقسيط')),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _primary,
      foregroundColor: _onPrimary,
      elevation: 0,
      centerTitle: false,
      title: const Text(
        'إعدادات تقسيط',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'إعادة التحميل من القاعدة',
          onPressed: _loading ? null : _load,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _introBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.1),
        borderRadius: AppShape.none,
        border: Border.all(color: _primary.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: _primary, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'تُطبَّق على بيع «تقسيط»، وبطاقة «مخطط التقسيط» في شاشة البيع (عند التفعيل)، وعلى ضبط خطة الأقساط بعد الحفظ.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    String? subtitle,
    IconData? icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: AppShape.none,
        border: Border.all(color: _outline.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: _primary, size: 24),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _outline.withValues(alpha: 0.28)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: _textSecondary,
          ),
        ),
      ),
      value: value,
      activeThumbColor: _onPrimary,
      activeTrackColor: _primary.withValues(alpha: 0.55),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _pageBg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAppBar(),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _pageBg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _introBanner(),
                        const SizedBox(height: 20),
                        _section(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'المقدّم وشروط البيع',
                          subtitle:
                              'التحكم في إلزامية المقدّم وأقل نسبة مسموحة من إجمالي الفاتورة.',
                          children: [
                            _switchTile(
                              title: 'إلزام مقدّم دفع لفاتورة التقسيط',
                              subtitle:
                                  'يمنع حفظ فاتورة تقسيط إذا كان المقدّم أقل من النسبة المحددة أدناه (من إجمالي الفاتورة بعد الخصم والضريبة).',
                              value: _data.requireDownPaymentForInstallmentSale,
                              onChanged: (v) => setState(
                                () => _data = _data.copyWith(
                                  requireDownPaymentForInstallmentSale: v,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _minPct,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: _fieldDecoration(
                                label: 'أقل نسبة مقدّم من إجمالي الفاتورة (%)',
                                helper:
                                    'مثال: 10 تعني ألا يقل المقدّم عن 10٪ من الإجمالي.',
                                prefixIcon: Icon(
                                  Icons.percent,
                                  size: 20,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _section(
                          icon: Icons.point_of_sale_outlined,
                          title: 'شاشة البيع وبطاقة التقسيط',
                          subtitle:
                              'عرض بطاقة الحاسبة، والقيم الافتراضية للأقساط والفائدة.',
                          children: [
                            _switchTile(
                              title: 'إظهار بطاقة «مخطط التقسيط» في شاشة البيع',
                              subtitle:
                                  'تُظهر المقدّم، نسبة الفائدة، عدد الأشهر، والقسط المقترح. عند الإيقاف يظهر المقدّم مع «تفصيل المبالغ» فقط، وتُحسب الفائدة من الإعدادات أدناه عند الحفظ.',
                              value: _data.showInstallmentCalculatorOnSale,
                              onChanged: (v) => setState(
                                () => _data = _data.copyWith(
                                  showInstallmentCalculatorOnSale: v,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _defCount,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(
                                label:
                                    'عدد أقساط المتبقي (افتراضي عند إنشاء الخطة)',
                                helper:
                                    'يُستخدم كعدد أشهر افتراضي في بطاقة «مخطط التقسيط» عند البيع؛ وعند إخفاء البطاقة يُحسب ما يُحفظ مع الفاتورة.',
                                helperMaxLines: 3,
                                prefixIcon: Icon(
                                  Icons.calendar_view_month_outlined,
                                  size: 20,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _saleDefInterest,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: _fieldDecoration(
                                label: 'نسبة الفائدة الافتراضية في بيع التقسيط (%)',
                                helper:
                                    'تُملأ خانة الفائدة عند اختيار «تقسيط»؛ وعند إخفاء البطاقة تُستخدم عند حفظ الفاتورة.',
                                prefixIcon: Icon(
                                  Icons.trending_up,
                                  size: 20,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _section(
                          icon: Icons.date_range_outlined,
                          title: 'الجدولة وتواريخ الاستحقاق',
                          subtitle:
                              'فترة الأقساط، طريقة احتساب الشهر، ومرجع أول تاريخ استحقاق.',
                          children: [
                            TextField(
                              controller: _interval,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(
                                label: 'فترة بين كل استحقاق وآخر (بالأشهر)',
                                helper: '1 = قسط شهري، 2 = كل شهرين، وهكذا.',
                                prefixIcon: Icon(
                                  Icons.more_time_outlined,
                                  size: 20,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _switchTile(
                              title: 'استخدام أشهر تقويمية لتواريخ الاستحقاق',
                              subtitle:
                                  'مفعّل: إضافة شهر تقويمي من تاريخ المرجع. معطّل: تقريب 30 يوماً لكل فترة.',
                              value: _data.useCalendarMonths,
                              onChanged: (v) => setState(
                                () => _data =
                                    _data.copyWith(useCalendarMonths: v),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'تاريخ مرجع أول قسط (عند فتح شاشة الخطة)',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              key: ValueKey<String>(_data.defaultFirstDueAnchor),
                              initialValue: _data.defaultFirstDueAnchor,
                              decoration: _fieldDecoration(
                                label: 'الخيار',
                                helper: null,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: InstallmentSettingsData.anchorInvoiceDate,
                                  child: Text('من تاريخ الفاتورة'),
                                ),
                                DropdownMenuItem(
                                  value: InstallmentSettingsData.anchorCustom,
                                  child: Text('يحدده البائع من التقويم (اتفاق)'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setState(
                                  () => _data =
                                      _data.copyWith(defaultFirstDueAnchor: v),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_outlined, size: 22),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'حفظ الإعدادات',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: _onPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppShape.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
