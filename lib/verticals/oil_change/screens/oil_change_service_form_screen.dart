import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/oil_change_service_item.dart';
import '../services/oil_change_services_repository.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/screen_layout.dart';
import '../../../widgets/adaptive/adaptive_form_container.dart';

/// إضافة أو تعديل خدمة إضافية في كتالوج غيار الزيت.
class OilChangeServiceFormScreen extends StatefulWidget {
  const OilChangeServiceFormScreen({super.key, this.existing});

  final OilChangeServiceItem? existing;

  @override
  State<OilChangeServiceFormScreen> createState() =>
      _OilChangeServiceFormScreenState();
}

class _OilChangeServiceFormScreenState extends State<OilChangeServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _priceCtrl = TextEditingController(
      text: e == null || e.priceFils <= 0
          ? ''
          : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(e.priceFils)),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  int _parsePriceFils() {
    final raw = _priceCtrl.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return 0;
    return IqdMoney.toFils(double.tryParse(raw) ?? 0);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final name = _nameCtrl.text.trim();
      final fils = _parsePriceFils();
      if (_isEdit) {
        await OilChangeServicesRepository.instance.updateById(
          id: widget.existing!.id,
          name: name,
          priceFils: fils,
        );
      } else {
        await OilChangeServicesRepository.instance.insert(
          name: name,
          priceFils: fils,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الحفظ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = context.screenLayout.pageHorizontalGap;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل خدمة' : 'إضافة خدمة'),
      ),
      body: AdaptiveFormContainer(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsetsDirectional.fromSTEB(pad, 16, pad, 24),
            children: [
              Text(
                'خدمة إضافية تظهر في بطاقة الغيار (مثل غسيل محرك، فلاش…). '
                'سعر تبديل الزيت الأساسي يُحدَّد من شاشة «الخدمات وأسعارها».',
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الخدمة',
                  border: OutlineInputBorder(),
                  hintText: 'مثال: غسيل محرك',
                ),
                textAlign: TextAlign.start,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'اسم الخدمة مطلوب';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _priceCtrl,
                decoration: const InputDecoration(
                  labelText: 'السعر (د.ع)',
                  border: OutlineInputBorder(),
                  hintText: '0',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                validator: (v) {
                  final raw = (v ?? '').trim().replaceAll(',', '');
                  if (raw.isEmpty) return 'أدخل السعر';
                  final n = double.tryParse(raw);
                  if (n == null || n < 0) return 'سعر غير صالح';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ الخدمة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
