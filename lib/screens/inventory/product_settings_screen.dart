import 'package:flutter/material.dart';

import '../../services/app_settings_repository.dart';
import '../../services/inventory_product_settings.dart';
import '../../services/product_repository.dart';
import 'price_lists_screen.dart';
import 'product_sku_numbering_dialog.dart';
import 'unit_templates_settings_screen.dart';
import 'warehouses_screen.dart';

/// إعدادات المنتجات — أربعة أقسام: تهيئة، تتبع، أذون مخزنية، قيم افتراضية (تخزين في [app_settings]).
class ProductSettingsScreen extends StatefulWidget {
  const ProductSettingsScreen({super.key});

  @override
  State<ProductSettingsScreen> createState() => _ProductSettingsScreenState();
}

class _ProductSettingsScreenState extends State<ProductSettingsScreen> {
  final _repo = ProductRepository();
  final _settings = AppSettingsRepository.instance;

  bool _loading = true;
  late InventoryProductSettingsData _d;

  final _nextSkuCtrl = TextEditingController();
  final _nextTransferCtrl = TextEditingController();
  final _suggestMarginCtrl = TextEditingController();
  final _minSellPctCtrl = TextEditingController();

  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _priceLists = [];
  String _hintProductCode = 'N1-…';

  static const _taxChoices = <String>['معفى', '5', '10', '15', 'مخصص'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _hintProductCode = _repo.defaultProductCodeDisplayHint();
      var d = await InventoryProductSettingsData.load(_settings);
      _warehouses = await _repo.listWarehouses();
      _priceLists = await _repo.listPriceListsForSettings();

      if (d.defaultWarehouseId != null &&
          !_warehouses.any(
            (w) => (w['id'] as num).toInt() == d.defaultWarehouseId,
          )) {
        d = d.copyWith(clearWarehouseId: true);
        await d.save(_settings);
      }
      if (d.defaultPriceListId != null &&
          !_priceLists.any(
            (w) => (w['id'] as num).toInt() == d.defaultPriceListId,
          )) {
        d = d.copyWith(clearPriceListId: true);
        await d.save(_settings);
      }
      _d = d;

      _nextSkuCtrl.text =
          _d.nextSkuText.isNotEmpty ? _d.nextSkuText : _hintProductCode;
      _nextTransferCtrl.text = _d.nextTransferNo;
      _suggestMarginCtrl.text = _fmtSettingNum(_d.suggestedMarginPercent);
      _minSellPctCtrl.text = _fmtSettingNum(_d.minSellPercentOfSell);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persist() async {
    _d = _d.copyWith(
      nextSkuText: _nextSkuCtrl.text.trim(),
      nextTransferNo: _nextTransferCtrl.text.trim(),
    );
    await _d.save(_settings);
  }

  Future<void> _patch(InventoryProductSettingsData next) async {
    setState(() {
      _d = next.copyWith(
        nextSkuText: _nextSkuCtrl.text.trim(),
        nextTransferNo: _nextTransferCtrl.text.trim(),
      );
    });
    await _d.save(_settings);
  }

  /// أيقونة منع سريعة: إيقاف التعامل بالضريبة في شاشة إضافة المنتج (إخفاء الحقل).
  Widget _addProductTaxRow(ColorScheme cs) {
    final canUse = _d.addShowAdvancedPricing;
    final on = _d.addShowTaxField;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: IconButton(
        tooltip: 'عدم التعامل بالضريبة — إيقاف إظهار حقل الضريبة',
        icon: Icon(
          Icons.block_rounded,
          color: canUse && on
              ? cs.error
              : cs.onSurfaceVariant.withValues(alpha: 0.35),
        ),
        onPressed: canUse && on
            ? () => _patch(_d.copyWith(addShowTaxField: false))
            : null,
      ),
      title: const Text('إظهار حقل الضريبة'),
      subtitle: const Text(
        'في «إضافة منتج جديد». أيقونة المنع تعطّل الضريبة دفعة واحدة.',
        style: TextStyle(fontSize: 12, height: 1.25),
      ),
      trailing: Switch(
        value: on,
        onChanged: canUse
            ? (v) => _patch(_d.copyWith(addShowTaxField: v))
            : null,
      ),
    );
  }

  /// أيقونة منع سريعة: إيقاف التعامل بالخصم في شاشة إضافة المنتج (إخفاء الحقول).
  Widget _addProductDiscountRow(ColorScheme cs) {
    final canUse = _d.addShowAdvancedPricing;
    final on = _d.addShowDiscountFields;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: IconButton(
        tooltip: 'عدم التعامل بالخصم — إيقاف إظهار حقول الخصم',
        icon: Icon(
          Icons.money_off_rounded,
          color: canUse && on
              ? cs.error
              : cs.onSurfaceVariant.withValues(alpha: 0.35),
        ),
        onPressed: canUse && on
            ? () => _patch(_d.copyWith(addShowDiscountFields: false))
            : null,
      ),
      title: const Text('إظهار حقول الخصم'),
      subtitle: const Text(
        'في «إضافة منتج جديد». أيقونة المنع تعطّل الخصم دفعة واحدة.',
        style: TextStyle(fontSize: 12, height: 1.25),
      ),
      trailing: Switch(
        value: on,
        onChanged: canUse
            ? (v) => _patch(_d.copyWith(addShowDiscountFields: v))
            : null,
      ),
    );
  }

  static String _fmtSettingNum(double v) {
    if ((v - v.round()).abs() < 1e-9) return v.round().toString();
    return v.toString();
  }

  Future<void> _persistMarginSuggestFields() async {
    final m = double.tryParse(
          _suggestMarginCtrl.text.trim().replaceAll(',', '.')) ??
        _d.suggestedMarginPercent;
    final p = double.tryParse(
          _minSellPctCtrl.text.trim().replaceAll(',', '.')) ??
        _d.minSellPercentOfSell;
    final mc = m.clamp(0.0, 500.0);
    final pc = p.clamp(1.0, 100.0);
    await _patch(
      _d.copyWith(
        suggestedMarginPercent: mc,
        minSellPercentOfSell: pc,
      ),
    );
    if (!mounted) return;
    _suggestMarginCtrl.text = _fmtSettingNum(mc);
    _minSellPctCtrl.text = _fmtSettingNum(pc);
  }

  @override
  void dispose() {
    _nextSkuCtrl.dispose();
    _nextTransferCtrl.dispose();
    _suggestMarginCtrl.dispose();
    _minSellPctCtrl.dispose();
    super.dispose();
  }

  Future<void> _openNumberingDialog({required bool forTransfer}) async {
    if (!forTransfer) {
      final result = await showProductSkuNumberingDialog(
        context,
        data: _d,
        hintNextSku: _hintProductCode,
        initialNextNumber: _nextSkuCtrl.text,
      );
      if (result != null && mounted) {
        setState(() => _d = result);
        _nextSkuCtrl.text = result.nextSkuText;
        await _d.save(_settings);
      }
      return;
    }

    final prefixCtrl = TextEditingController(text: _d.transferPrefix);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إعدادات ترقيم أذون التحويل'),
          content: TextField(
            controller: prefixCtrl,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'بادئة اختيارية',
              border: OutlineInputBorder(),
              hintText: 'مثال: TR-',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                await _patch(
                  _d.copyWith(transferPrefix: prefixCtrl.text.trim()),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFF0F4F8);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E3A5F),
          foregroundColor: Colors.white,
          title: const Text(
            'إعدادات المنتجات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : DefaultTabController(
                length: 4,
                child: Column(
                  children: [
                    Material(
                      color: cs.surface,
                      child: TabBar(
                        isScrollable: true,
                        labelColor: cs.primary,
                        unselectedLabelColor: cs.onSurfaceVariant,
                        indicatorColor: cs.primary,
                        tabs: const [
                          Tab(text: 'تهيئة المنتجات'),
                          Tab(text: 'تتبع المنتجات'),
                          Tab(text: 'الأذون المخزنية'),
                          Tab(text: 'القيم الافتراضية'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _tabInit(cs),
                          _tabTrack(cs),
                          _tabVouchers(cs),
                          _tabDefaults(cs),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _tabInit(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(
            'تهيئة المنتجات',
            'إدارة الترقيم التلقائي، وخيارات التسعير المتقدمة، ونظام الوحدات، والأصناف المجمعة.',
            cs,
          ),
          const SizedBox(height: 16),
          _sectionCard(
            cs,
            title: 'الرقم التسلسلي للمنتج التالي',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nextSkuCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: _outlineDec('الرقم التالي'),
                    onEditingComplete: _persist,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openNumberingDialog(forTransfer: false),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('إعدادات الترقيم'),
                ),
              ],
            ),
            footer:
                'الرقم الذي سيُعرض كتلميح للمعرّف التالي. البادئة تُحفظ في إعدادات الترقيم.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'خيارات التسعير المتقدمة',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_d.advancedPricing ? 'مفعّل' : 'معطّل'),
                  subtitle: const Text(
                    'عند التفعيل: في «إضافة منتج جديد» يُقترح سعر البيع وأقل سعر من سعر الشراء حسب الهامش أدناه (قابل للتعديل يدوياً قبل الحفظ).',
                    style: TextStyle(fontSize: 12, height: 1.35),
                  ),
                  value: _d.advancedPricing,
                  onChanged: (v) => _patch(_d.copyWith(advancedPricing: v)),
                ),
                if (_d.advancedPricing) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _suggestMarginCtrl,
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _outlineDec('هامش الربح على التكلفة (%)')
                              .copyWith(hintText: 'مثال: 25'),
                          onSubmitted: (_) => _persistMarginSuggestFields(),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _minSellPctCtrl,
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _outlineDec(
                            'أقل سعر بيع كنسبة من سعر البيع (%)',
                          ).copyWith(hintText: '100 = مساوٍ لسعر البيع'),
                          onSubmitted: (_) => _persistMarginSuggestFields(),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonal(
                            onPressed: _persistMarginSuggestFields,
                            child: const Text('حفظ أرقام الاقتراح'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            footer:
                'مثال: تكلفة 10,000 وهامش 25٪ → سعر بيع مقترح 12,500. نسبة أقل سعر 100٪ تجعل أقل سعر = سعر البيع.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'استخدام وحدات متعددة لكل صنف',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const UnitTemplatesSettingsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('إدارة الوحدات'),
                    ),
                    const Spacer(),
                    Switch(
                      value: _d.multiUnitPerItem,
                      onChanged: (v) =>
                          _patch(_d.copyWith(multiUnitPerItem: v)),
                    ),
                    Text(_d.multiUnitPerItem ? 'مفعّل' : 'معطّل'),
                  ],
                ),
              ],
            ),
            footer:
                'السماح بشراء بوحدة وبيع بوحدة أخرى مع معاملات تحويل من قوالب الوحدات.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'الوحدة الافتراضية لعرض المخزون',
            child: Column(
              children: [
                _unitRadio('base', 'الوحدة الأساسية لقالب الوحدة',
                    'عرض المخزون بوحدة القالب الأساسية.'),
                _unitRadio('sale', 'وحدة البيع',
                    'عرض الرصيد بوحدة البيع الافتراضية.'),
                _unitRadio('purchase', 'وحدة الشراء',
                    'عرض الرصيد بوحدة الشراء الافتراضية.'),
              ],
            ),
            footer:
                'تحدد كيف يُعرض المخزون في التقارير والجرد عند تفعيل تعدد الوحدات.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'التجميعات والوحدات المركبة',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_d.bundlesEnabled ? 'مسموح' : 'غير مسموح'),
              value: _d.bundlesEnabled,
              onChanged: (v) => _patch(_d.copyWith(bundlesEnabled: v)),
            ),
            footer:
                'تعريف صنف مركّب من عدة أصناف وخصم المخزون عند التجميع أو البيع (يتطلب تطوير شاشات لاحقاً).',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'سياسات شاشة إضافة المنتج',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار قسم التسعير المتقدم'),
                  subtitle: const Text(
                    'يتحكم بإظهار الضريبة والخصم وأقل سعر البيع وهامش الربح.',
                  ),
                  value: _d.addShowAdvancedPricing,
                  onChanged: (v) =>
                      _patch(_d.copyWith(addShowAdvancedPricing: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار حقل الباركود'),
                  value: _d.addShowBarcodeField,
                  onChanged: (v) {
                    if (!v && _d.addRequireBarcode) {
                      _patch(
                        _d.copyWith(
                          addShowBarcodeField: false,
                          addRequireBarcode: false,
                        ),
                      );
                      return;
                    }
                    _patch(_d.copyWith(addShowBarcodeField: v));
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('الباركود إلزامي عند الحفظ'),
                  value: _d.addRequireBarcode,
                  onChanged: _d.addShowBarcodeField
                      ? (v) => _patch(_d.copyWith(addRequireBarcode: v))
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار حقل صورة المنتج'),
                  value: _d.addShowImageField,
                  onChanged: (v) {
                    if (!v && _d.addRequireImage) {
                      _patch(
                        _d.copyWith(
                          addShowImageField: false,
                          addRequireImage: false,
                        ),
                      );
                      return;
                    }
                    _patch(_d.copyWith(addShowImageField: v));
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('صورة المنتج إلزامية'),
                  value: _d.addRequireImage,
                  onChanged: _d.addShowImageField
                      ? (v) => _patch(_d.copyWith(addRequireImage: v))
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار الحقول الإضافية'),
                  subtitle: const Text(
                    'مثل: ملاحظات داخلية، وسوم، الوزن، وتواريخ الإنتاج/الانتهاء.',
                  ),
                  value: _d.addShowExtraFields,
                  onChanged: (v) => _patch(_d.copyWith(addShowExtraFields: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('المورد إلزامي عند الحفظ'),
                  value: _d.addRequireSupplier,
                  onChanged: (v) => _patch(_d.copyWith(addRequireSupplier: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('المخزن إلزامي عند الحفظ'),
                  value: _d.addRequireWarehouse,
                  onChanged: (v) => _patch(_d.copyWith(addRequireWarehouse: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل تتبع المخزون افتراضياً'),
                  subtitle: const Text(
                    'ينعكس على حالة المفتاح عند فتح شاشة إضافة المنتج.',
                  ),
                  value: _d.addDefaultTrackInventory,
                  onChanged: (v) =>
                      _patch(_d.copyWith(addDefaultTrackInventory: v)),
                ),
                _addProductTaxRow(cs),
                _addProductDiscountRow(cs),
              ],
            ),
            footer:
                'هذه السياسات تُطبّق مباشرة على شاشة «إضافة منتج جديد» دون التأثير على شاشة البيع.',
          ),
        ],
      ),
    );
  }

  Widget _unitRadio(String value, String title, String sub) {
    final sel = _d.defaultUnitView == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _patch(_d.copyWith(defaultUnitView: value)),
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: sel ? const Color(0xFF2563EB) : Colors.grey.shade300,
              width: sel ? 2 : 1,
            ),
          ),
          child: RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: value,
            groupValue: _d.defaultUnitView,
            onChanged: (v) {
              if (v != null) _patch(_d.copyWith(defaultUnitView: v));
            },
            title: Text(title, textAlign: TextAlign.right),
            subtitle: Text(sub,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
          ),
        ),
      ),
    );
  }

  Widget _tabTrack(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(
            'تتبع المنتجات',
            'إعداد طرق التتبع وسلوك النظام عند نفاد الكمية.',
            cs,
          ),
          const SizedBox(height: 16),
          _sectionCard(
            cs,
            title:
                'تتبع بواسطة الرقم المسلسل، رقم التوصيلة، أو تاريخ الانتهاء',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_d.trackSerialBatchExpiry ? 'مفعّل' : 'معطّل'),
              value: _d.trackSerialBatchExpiry,
              onChanged: (v) =>
                  _patch(_d.copyWith(trackSerialBatchExpiry: v)),
            ),
            footer:
                'عند التفعيل يمكن تفعيل التتبع لكل منتج على حدة عند الإضافة.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'المخزون السالب',
            child: Column(
              children: [
                _negRadio(
                  'stop_all',
                  'إيقاف العمليات عند نفاد الكمية لجميع المنتجات',
                  'منع البيع أو الصرف عند وصول المخزون إلى الصفر.',
                ),
                _negRadio(
                  'tracked_only',
                  'السماح فقط للمنتجات القابلة للتتبع بالكميات',
                  'يُسمح بالبيع السالب أو الصرف حسب سياسة الصنف.',
                ),
              ],
            ),
            footer: 'يحدد سلوك النظام عند نفاد المخزون.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'عرض الكمية الإجمالية والمتوفرة',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_d.showTotalAndAvailable ? 'مفعّل' : 'معطّل'),
              value: _d.showTotalAndAvailable,
              onChanged: (v) =>
                  _patch(_d.copyWith(showTotalAndAvailable: v)),
            ),
            footer:
                'عرض إجمالي الكمية مقابل المتاح بعد الحجوزات (عند تفعيل الحجز لاحقاً).',
          ),
        ],
      ),
    );
  }

  Widget _negRadio(String value, String title, String sub) {
    final sel = _d.negativeStockMode == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _patch(_d.copyWith(negativeStockMode: value)),
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: sel ? const Color(0xFF2563EB) : Colors.grey.shade300,
              width: sel ? 2 : 1,
            ),
          ),
          child: RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: value,
            groupValue: _d.negativeStockMode,
            onChanged: (v) {
              if (v != null) _patch(_d.copyWith(negativeStockMode: v));
            },
            title: Text(title, textAlign: TextAlign.right),
            subtitle: Text(sub,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
          ),
        ),
      ),
    );
  }

  Widget _tabVouchers(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(
            'الأذون المخزنية',
            'إنشاء طلبات مخزنية وترقيم أذون التحويل وربطها بالمبيعات والمشتريات.',
            cs,
          ),
          const SizedBox(height: 16),
          _sectionCard(
            cs,
            title: 'الطلبات المخزنية',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_d.inventoryRequestsEnabled ? 'مفعّل' : 'معطّل'),
              value: _d.inventoryRequestsEnabled,
              onChanged: (v) =>
                  _patch(_d.copyWith(inventoryRequestsEnabled: v)),
            ),
            footer:
                'تمكين الأقسام من رفع طلبات مخزنية لمراجعتها. الصلاحيات تُضبط من أدوار المستخدمين عند توفرها.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'الرقم التسلسلي لإذن التحويل المخزني التالي',
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nextTransferCtrl,
                    textAlign: TextAlign.right,
                    decoration: _outlineDec('الرقم'),
                    onEditingComplete: _persist,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openNumberingDialog(forTransfer: true),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('إعدادات الترقيم'),
                ),
              ],
            ),
            footer: 'الرقم التالي المقترح لأذون التحويل.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'الأذون المخزنية لفواتير المبيعات',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_d.salesVoucherPerm ? 'مفعّل' : 'معطّل'),
              value: _d.salesVoucherPerm,
              onChanged: (v) => _patch(_d.copyWith(salesVoucherPerm: v)),
            ),
            footer:
                'عند التفعيل يُنشأ إذن صرف يحتاج اعتماداً قبل خصم المخزون.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'الأذون المخزنية لفواتير الشراء',
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_d.purchaseVoucherPerm ? 'مفعّل' : 'معطّل'),
              value: _d.purchaseVoucherPerm,
              onChanged: (v) =>
                  _patch(_d.copyWith(purchaseVoucherPerm: v)),
            ),
            footer:
                'عند التفعيل يُنشأ إذن إدخال يحتاج اعتماداً قبل إضافة المخزون.',
          ),
        ],
      ),
    );
  }

  Widget _tabDefaults(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(
            'القيم الافتراضية للنظام',
            'قيم تُقترح تلقائياً للمستودعات والمنتجات والضرائب.',
            cs,
          ),
          const SizedBox(height: 16),
          _sectionCard(
            cs,
            title: 'الحساب الفرعي الافتراضي',
            child: DropdownButtonFormField<String>(
              value: _d.subAccountLabel.isEmpty ? null : _d.subAccountLabel,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              hint: const Text('من فضلك اختر'),
              items: const [
                DropdownMenuItem(value: '', child: Text('— بدون —')),
                DropdownMenuItem(
                    value: 'مخزون_عام', child: Text('مخزون عام')),
                DropdownMenuItem(
                    value: 'مواد_خام', child: Text('مواد خام')),
                DropdownMenuItem(
                    value: 'تجاري', child: Text('تجاري')),
              ],
              onChanged: (v) =>
                  _patch(_d.copyWith(subAccountLabel: v ?? '')),
            ),
            footer: 'يُستخدم كمرجع محاسبي عند ربط المخزون بالحسابات.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'المستودع الافتراضي',
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const WarehousesScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('إدارة المستودعات'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: _d.defaultWarehouseId,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    hint: const Text('اختر مستودعاً'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('— بدون —'),
                      ),
                      ..._warehouses.map(
                        (w) => DropdownMenuItem<int?>(
                          value: (w['id'] as num).toInt(),
                          child: Text(w['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) {
                        _patch(_d.copyWith(clearWarehouseId: true));
                      } else {
                        _patch(_d.copyWith(defaultWarehouseId: v));
                      }
                    },
                  ),
                ),
              ],
            ),
            footer: 'يُقترح عند إضافة منتجات وحركات مخزون جديدة.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'قائمة الأسعار الافتراضية',
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const PriceListsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('إدارة القوائم'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    value: _d.defaultPriceListId,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    hint: const Text('من فضلك اختر'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('— بدون —'),
                      ),
                      ..._priceLists.map(
                        (w) => DropdownMenuItem<int?>(
                          value: (w['id'] as num).toInt(),
                          child: Text(w['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) {
                        _patch(_d.copyWith(clearPriceListId: true));
                      } else {
                        _patch(_d.copyWith(defaultPriceListId: v));
                      }
                    },
                  ),
                ),
              ],
            ),
            footer: 'تُستخدم كقائمة أسعار افتراضية للفرع الحالي عند توفر الربط.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'الضريبة الافتراضية 1',
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'نِسَب الضريبة تُضبط لكل منتج أو من إعدادات الفاتورة.',
                        ),
                      ),
                    );
                  },
                  child: const Text('إدارة الضرائب'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _d.defaultTax1,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _taxChoices
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _patch(_d.copyWith(defaultTax1: v));
                    },
                  ),
                ),
              ],
            ),
            footer: 'تُقترح للمنتجات الجديدة ومتوافقة مع حقل الضريبة في المنتج.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'الضريبة الافتراضية 2',
            child: Row(
              children: [
                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'للاستخدام المزدوج عند دعم ضريبتين لاحقاً.',
                        ),
                      ),
                    );
                  },
                  child: const Text('إدارة الضرائب'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _d.defaultTax2,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: _taxChoices
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _patch(_d.copyWith(defaultTax2: v));
                    },
                  ),
                ),
              ],
            ),
            footer: '',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'طريقة احتساب تكلفة المرتجعات',
            child: Column(
              children: [
                _simpleRadio(
                  'sell_price',
                  'حسب سعر البيع',
                  'استخدام سعر البيع من فاتورة المبيعات.',
                ),
                _simpleRadio(
                  'last_avg',
                  'حسب آخر متوسط للتكلفة',
                  'استخدام متوسط التكلفة عند إنشاء المرتجع.',
                ),
              ],
            ),
            footer: 'يُطبَّق عند معالجة مرتجعات المبيعات.',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            cs,
            title: 'طبيعة مبيعات النشاط',
            child: Column(
              children: [
                _natureRadio(
                    'products', 'المنتجات فقط', 'مناسب للمخزون الفعلي.'),
                _natureRadio(
                    'services', 'الخدمات فقط', 'أنشطة تعتمد على الوقت أو المشاريع.'),
                _natureRadio('both', 'منتجات وخدمات',
                    'دمج بين الصنفين في النظام.'),
              ],
            ),
            footer: 'يحدد التركيز الافتراضي في شاشات المخزون والفوترة.',
          ),
        ],
      ),
    );
  }

  Widget _simpleRadio(String value, String title, String sub) {
    final sel = _d.returnCostMethod == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _patch(_d.copyWith(returnCostMethod: value)),
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: sel ? const Color(0xFF2563EB) : Colors.grey.shade300,
              width: sel ? 2 : 1,
            ),
          ),
          child: RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: value,
            groupValue: _d.returnCostMethod,
            onChanged: (v) {
              if (v != null) _patch(_d.copyWith(returnCostMethod: v));
            },
            title: Text(title, textAlign: TextAlign.right),
            subtitle: Text(sub,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
          ),
        ),
      ),
    );
  }

  Widget _natureRadio(String value, String title, String sub) {
    final sel = _d.businessNature == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _patch(_d.copyWith(businessNature: value)),
        borderRadius: BorderRadius.zero,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: sel ? const Color(0xFF2563EB) : Colors.grey.shade300,
              width: sel ? 2 : 1,
            ),
          ),
          child: RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: value,
            groupValue: _d.businessNature,
            onChanged: (v) {
              if (v != null) _patch(_d.copyWith(businessNature: v));
            },
            title: Text(title, textAlign: TextAlign.right),
            subtitle: Text(sub,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600, height: 1.3)),
          ),
        ),
      ),
    );
  }

  Widget _header(String title, String sub, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
          textAlign: TextAlign.right,
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.right,
        ),
      ],
    );
  }

  Widget _sectionCard(
    ColorScheme cs, {
    required String title,
    required Widget child,
    String footer = '',
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 10),
          child,
          if (footer.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              footer,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.right,
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _outlineDec(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    );
  }
}
