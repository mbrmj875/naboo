import 'package:flutter/material.dart';

import '../models/car_wash_service_item.dart';
import '../services/car_wash_services_repository.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../widgets/raw_keyboard_inset.dart';

/// نتيجة نافذة نوع الغسيل — اسم منظّف وسعر بالفلس.
class CarWashServiceDraft {
  const CarWashServiceDraft({required this.name, required this.priceFils});

  final String name;
  final int priceFils;
}

/// نافذة سريعة لإضافة أو تعديل نوع غسيل بلا مغادرة البطاقة.
///
/// [takenNames]: أسماء الأنواع الموجودة. الاسم المكرر يُرفض برسالة واضحة،
/// بدل أن يُحدَّث سعر النوع القديم بصمت.
Future<CarWashServiceDraft?> showCarWashServiceDialog(
  BuildContext context, {
  CarWashServiceItem? existing,
  Iterable<String> takenNames = const [],
}) {
  final taken = {
    for (final n in takenNames)
      CarWashServicesRepository.normalizeName(n).toLowerCase(),
  };
  final own = existing == null
      ? null
      : CarWashServicesRepository.normalizeName(existing.name).toLowerCase();
  if (own != null) taken.remove(own);
  return showDialog<CarWashServiceDraft>(
    context: context,
    builder: (_) => _CarWashServiceDialog(existing: existing, taken: taken),
  );
}

class _CarWashServiceDialog extends StatefulWidget {
  const _CarWashServiceDialog({this.existing, this.taken = const {}});

  final CarWashServiceItem? existing;
  final Set<String> taken;

  @override
  State<_CarWashServiceDialog> createState() => _CarWashServiceDialogState();
}

class _CarWashServiceDialogState extends State<_CarWashServiceDialog>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  double _keyboardInset = 0;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidImeInset.ensureStarted();
    AndroidImeInset.bottomLogical.addListener(_onInsetChanged);
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _price = TextEditingController(
      text: e == null || e.priceFils <= 0
          ? ''
          : IraqiCurrencyFormat.formatInt(IqdMoney.fromFils(e.priceFils)),
    );
  }

  @override
  void dispose() {
    AndroidImeInset.bottomLogical.removeListener(_onInsetChanged);
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() => _onInsetChanged();

  /// على أندرويد يصل ارتفاع الكيبورد من القناة الأصلية فقط؛ بدون هذا تبقى
  /// النافذة مرفوعة بعد إغلاق الكيبورد، فيقع الضغط على غير الزر المقصود.
  void _onInsetChanged() {
    if (!mounted) return;
    final next = rawKeyboardBottomInset(context);
    if ((next - _keyboardInset).abs() < 0.5) return;
    setState(() => _keyboardInset = next);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final dinars = IraqiCurrencyFormat.parseIqdInt(_price.text);
    final fils = IqdMoney.toFils(dinars.toDouble());
    Navigator.pop(
      context,
      CarWashServiceDraft(
        name: CarWashServicesRepository.normalizeName(_name.text),
        priceFils: fils,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = rawKeyboardBottomInset(context);
    _keyboardInset = inset;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: inset),
      child: AlertDialog(
        title: Text(_isEdit ? 'تعديل نوع الغسيل' : 'نوع غسيل جديد'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: !_isEdit,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'اسم النوع',
                    hintText: 'مثال: غسيل كامل',
                    border: OutlineInputBorder(),
                    errorMaxLines: 2,
                  ),
                  textAlign: TextAlign.start,
                  validator: (v) {
                    final clean =
                        CarWashServicesRepository.normalizeName(v ?? '');
                    if (clean.isEmpty) return 'اسم النوع مطلوب';
                    if (widget.taken.contains(clean.toLowerCase())) {
                      return 'هذا النوع موجود. غيّر سعره من قائمة الأنواع';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _price,
                  decoration: const InputDecoration(
                    labelText: 'السعر (د.ع)',
                    hintText: '0',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: false,
                    signed: false,
                  ),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  inputFormatters: [
                    IraqiCurrencyFormat.moneyInputFormatter(),
                  ],
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) {
                    final raw = (v ?? '').trim();
                    if (raw.isEmpty) return 'أدخل السعر';
                    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.isEmpty) return 'سعر غير صالح';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: _submit,
            child: Text(_isEdit ? 'تحديث' : 'إضافة'),
          ),
        ],
      ),
    );
  }
}
