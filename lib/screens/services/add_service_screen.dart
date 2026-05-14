import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/product_provider.dart';
import '../../utils/numeric_format.dart';
import '../../widgets/adaptive/adaptive_form_container.dart';
import '../../widgets/inputs/app_input.dart';
import '../../widgets/inputs/app_price_input.dart';

/// تعريف خدمة فنية للبيع المباشر (`isService`) دون مسار «إضافة منتج» الكامل.
class AddServiceScreen extends StatefulWidget {
  const AddServiceScreen({super.key});

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _desc = TextEditingController();
  final _sell = TextEditingController();
  final _minSell = TextEditingController();
  final _costRef = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _desc.dispose();
    _sell.dispose();
    _minSell.dispose();
    _costRef.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final sellIqd = NumericFormat.parseNumber(_sell.text);
    final minRaw = _minSell.text.trim();
    final minIqd =
        minRaw.isEmpty ? sellIqd : NumericFormat.parseNumber(_minSell.text);
    final costRaw = _costRef.text.trim();
    final costIqd =
        costRaw.isEmpty ? 0 : NumericFormat.parseNumber(_costRef.text);

    if (minIqd > sellIqd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الحد الأدنى للبيع لا يجوز أن يتجاوز سعر البيع'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    final products = context.read<ProductProvider>();
    final err = await products.addProduct(
      name: _name.text.trim(),
      categoryName:
          _category.text.trim().isEmpty ? null : _category.text.trim(),
      buyPrice: costIqd.toDouble(),
      sellPrice: sellIqd.toDouble(),
      minSellPrice: minRaw.isEmpty ? null : minIqd.toDouble(),
      qty: 0,
      lowStockThreshold: 0,
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      trackInventory: false,
      isService: true,
      serviceKind: 'direct',
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الخدمة')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_submitting,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إضافة خدمة فنية'),
        ),
        body: AdaptiveFormContainer(
          child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
            children: [
              Text(
                'أضف خدمة للبيع المباشر من شاشة البيع (كمية ثابتة 1، بدون مخزون).',
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 16),
              AppInput(
                label: 'اسم الخدمة',
                hint: 'مثال: تركيب شاشة',
                controller: _name,
                isRequired: true,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'أدخل اسم الخدمة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AppPriceInput(
                label: 'سعر البيع',
                controller: _sell,
                isRequired: true,
                textInputAction: TextInputAction.next,
                validator: (s) {
                  final n = NumericFormat.parseNumber(s ?? '');
                  if (n < 0) return 'السعر غير صالح';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              AppPriceInput(
                label: 'التكلفة المرجعية للخدمة',
                controller: _costRef,
                isOptional: true,
                textInputAction: TextInputAction.next,
                subtitle:
                    'أجر الفني أو مواد مستهلكة افتراضية — لحساب الهامش في التقارير (مثل سعر الشراء للمنتج).',
              ),
              const SizedBox(height: 12),
              AppPriceInput(
                label: 'الحد الأدنى للبيع',
                controller: _minSell,
                isOptional: true,
                textInputAction: TextInputAction.next,
                subtitle: 'إن تُرك فارغاً يُستخدم سعر البيع.',
              ),
              const SizedBox(height: 12),
              AppInput(
                label: 'قسم أو تصنيف الخدمة',
                hint: 'مثال: صيانة عتاد، برمجيات، صيانة سريعة',
                controller: _category,
                isOptional: true,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              AppInput(
                label: 'الوصف أو التفاصيل',
                hint: 'مدة العمل، الشروط، الملاحظات…',
                controller: _desc,
                isOptional: true,
                maxLines: 4,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _save,
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('حفظ الخدمة'),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
