import 'dart:async';

import 'package:flutter/material.dart';

import '../models/oil_card_required_fields.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../services/oil_change_settings.dart';
import '../utils/iraq_plate.dart';
import 'oil_technicians_screen.dart';
import '../../../guides/guide_anchor.dart';

/// إعدادات بطاقة الغيار المستقلة.
///
/// القسم الأول: الحقول الإلزامية. اسم العميل وهاتفه إلزاميان دائماً.
/// كل الحقول تبقى ظاهرة في البطاقة؛ الإعداد يحدد هل يُمنع البيع بدونها.
class OilChangeCardSettingsScreen extends StatefulWidget {
  const OilChangeCardSettingsScreen({super.key});

  @override
  State<OilChangeCardSettingsScreen> createState() =>
      _OilChangeCardSettingsScreenState();
}

class _OilChangeCardSettingsScreenState
    extends State<OilChangeCardSettingsScreen> {
  OilCardRequiredFields? _required;
  OilCustomerLaborSettings _labor = const OilCustomerLaborSettings();
  int _basePriceFils = 0;
  OilChangeCardSettings? _card;
  final Set<OilCardField> _saving = {};
  final Set<String> _savingFlags = {};
  String? _province;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final card = await OilChangeSettings.loadCardSettings();
    final province = await OilChangeSettings.getDefaultPlateProvince();
    if (!mounted) return;
    setState(() {
      _province = province;
      _required = card.requiredFields;
      _labor = card.customerLabor;
      _basePriceFils = card.baseOilChangePriceFils;
      _card = card;
    });
  }

  Future<void> _setFlag(String key, bool value) async {
    setState(() => _savingFlags.add(key));
    try {
      await OilChangeSettings.setCardFlag(key, value);
      await _load();
    } finally {
      if (mounted) setState(() => _savingFlags.remove(key));
    }
  }

  Widget _sourceTile({
    required String key,
    required String title,
    required bool value,
    String onText = 'مرتبط بالمخزون: يُختار الصنف ويُخصم عند البيع',
    String offText = 'أسماء وأسعار فقط، بلا خصم مخزون',
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(value ? onText : offText),
      value: value,
      onChanged: _savingFlags.contains(key)
          ? null
          : (v) => unawaited(_setFlag(key, v)),
    );
  }

  List<Widget> _sourceSection(BuildContext context, ColorScheme cs) {
    final card = _card;
    if (card == null) return const [];
    return [
      Text(
        'مصدر كل قسم',
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        'لكل قسم مصدر واحد داخل البطاقة. «من العميل» متاح دائماً بجانبه. '
        'الفلاتر تُربط بالمخزون من حقل «الصنف» في المنتج: «فلتر المحرك» '
        'يظهر في خانة المحرك، و«فلتر» يظهر في كل الخانات.',
        style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
      ),
      const SizedBox(height: 8),
      Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            _sourceTile(
              key: OilChangeSettingsKeys.stockFromWarehouse,
              title: 'الزيت',
              value: card.stockFromWarehouse,
            ),
            _sourceTile(
              key: OilChangeSettingsKeys.hydraulicGearStockFromWarehouse,
              title: 'هيدروليك الكير',
              value: card.hydraulicGearStockFromWarehouse,
            ),
            _sourceTile(
              key: OilChangeSettingsKeys.hydraulicPowerStockFromWarehouse,
              title: 'هيدروليك الباور',
              value: card.hydraulicPowerStockFromWarehouse,
            ),
            _sourceTile(
              key: OilChangeSettingsKeys.filtersStockFromWarehouse,
              title: 'الفلاتر',
              value: card.filtersStockFromWarehouse,
            ),
            _sourceTile(
              key: OilChangeSettingsKeys.filterQuantityEditable,
              title: 'كمية الفلتر',
              value: card.filterQuantityEditable,
              onText: 'قابلة للتعديل في البطاقة',
              offText: 'قطعة واحدة دائماً',
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  Future<void> _pickProvince() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const Key('defaultProvinceNone'),
                label: const Text('بلا محافظة'),
                selected: _province == null,
                onSelected: (_) => Navigator.pop(ctx, ''),
              ),
              for (final p in kIraqProvinces)
                ChoiceChip(
                  key: Key('defaultProvince_$p'),
                  label: Text(p),
                  selected: _province == p,
                  onSelected: (_) => Navigator.pop(ctx, p),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await OilChangeSettings.setDefaultPlateProvince(picked);
    await _load();
  }

  Future<void> _toggle(OilCardField field, bool value) async {
    setState(() => _saving.add(field));
    try {
      await OilChangeSettings.setFieldRequired(field, value);
      await _load();
    } finally {
      if (mounted) setState(() => _saving.remove(field));
    }
  }

  String _fmt(int fils) =>
      fils <= 0 ? '0' : IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));

  Future<void> _editLabor(String key, String title, int? current) async {
    final ctrl = TextEditingController(
      text: current == null || current <= 0
          ? ''
          : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(current)),
    );
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'المبلغ (د.ع)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
      if (result == null) return;
      final d = double.tryParse(result.trim().replaceAll(',', ''));
      await OilChangeSettings.setCustomerLaborFils(
        key,
        d == null || d <= 0 ? null : IqdMoney.toFils(d),
      );
      await _load();
    } finally {
      ctrl.dispose();
    }
  }

  Widget _laborTile({
    required String key,
    required String title,
    required int? fils,
    required String emptyText,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(fils == null || fils <= 0 ? emptyText : _fmt(fils)),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => unawaited(_editLabor(key, title, fils)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final required = _required;
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات بطاقة الغيار')),
      body: required == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                ..._sourceSection(context, cs),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    key: const Key('defaultPlateProvinceTile'),
                    leading: const Icon(Icons.location_city_outlined),
                    title: const Text('محافظة المحل'),
                    subtitle: Text(
                      _province == null
                          ? 'غير محددة: اللوحة رقم وحرف فقط'
                          : 'تُكتب في لوحة كل بطاقة جديدة: $_province',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => unawaited(_pickProvince()),
                  ),
                ),
                const SizedBox(height: 8),
                GuideAnchor(
                  id: OilGuideAnchors.cardSettingsTechnicians,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      key: const Key('techniciansTile'),
                      leading: const Icon(Icons.handyman_outlined),
                      title: const Text('الفنيون'),
                      subtitle: const Text('حسابات الموظفين والمضافون يدوياً، والإيقاف والإعادة'),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => unawaited(OilTechniciansScreen.open(context)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'الحقول الإلزامية',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'اسم العميل وهاتفه إلزاميان دائماً. الحقل غير الإلزامي يبقى '
                  'ظاهراً في البطاقة ويُحفظ إن كُتب، لكن البيع لا يُمنع بدونه.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final f in OilCardField.values)
                        SwitchListTile(
                          title: Text(f.labelAr),
                          subtitle: Text(
                            required.isRequired(f) ? 'إلزامي' : 'اختياري',
                          ),
                          value: required.isRequired(f),
                          onChanged: _saving.contains(f)
                              ? null
                              : (v) => unawaited(_toggle(f, v)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'أجرة اليد حين يُحضر العميل الصنف',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'عند «من العميل» لا يُحسب ثمن الصنف ولا يُخصم مخزون، ويظهر سطر '
                  'الأجرة في البطاقة والفاتورة. الموظف يعدّله لكل بطاقة.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _laborTile(
                        key: OilChangeSettingsKeys.customerLaborOil,
                        title: 'أجرة التبديل بزيت العميل',
                        fils: _labor.oilFils,
                        emptyText:
                            'غير محددة: تُستعمل الأجرة الأساسية (${_fmt(_basePriceFils)})',
                      ),
                      _laborTile(
                        key: OilChangeSettingsKeys.customerLaborHydraulicGear,
                        title: 'هيدروليك الكير من العميل',
                        fils: _labor.hydraulicGearFils,
                        emptyText: 'بلا أجرة',
                      ),
                      _laborTile(
                        key: OilChangeSettingsKeys.customerLaborHydraulicPower,
                        title: 'هيدروليك الباور من العميل',
                        fils: _labor.hydraulicPowerFils,
                        emptyText: 'بلا أجرة',
                      ),
                      _laborTile(
                        key: OilChangeSettingsKeys.customerLaborFilter,
                        title: 'تركيب فلتر من العميل',
                        fils: _labor.filterFils,
                        emptyText: 'بلا أجرة',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'بطاقة بلا زيت لا يُجدوَل لها تذكير الغيار القادم. '
                  'والبطاقة تحتاج بنداً مسعَّراً واحداً على الأقل.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                ),
              ],
            ),
    );
  }
}
