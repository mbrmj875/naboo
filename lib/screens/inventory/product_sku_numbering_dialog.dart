import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/inventory_product_settings.dart';

/// حوار مركزي لإعدادات الترقيم التلقائي للمنتجات (عرض ثابت ~520px، قابل للتمرير).
Future<InventoryProductSettingsData?> showProductSkuNumberingDialog(
  BuildContext context, {
  required InventoryProductSettingsData data,
  required String hintNextSku,
  required String initialNextNumber,
}) {
  return showDialog<InventoryProductSettingsData>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _ProductSkuNumberingDialog(
      data: data,
      hintNextSku: hintNextSku,
      initialNextNumber: initialNextNumber,
    ),
  );
}

class _ProductSkuNumberingDialog extends StatefulWidget {
  const _ProductSkuNumberingDialog({
    required this.data,
    required this.hintNextSku,
    required this.initialNextNumber,
  });

  final InventoryProductSettingsData data;
  final String hintNextSku;
  final String initialNextNumber;

  @override
  State<_ProductSkuNumberingDialog> createState() =>
      _ProductSkuNumberingDialogState();
}

class _ProductSkuNumberingDialogState extends State<_ProductSkuNumberingDialog> {
  late final TextEditingController _nextCtrl;
  late final TextEditingController _digitWidthCtrl;
  late final TextEditingController _prefixCtrl;

  late String _format;
  late bool _unique;
  late bool _prefixEnabled;

  @override
  void initState() {
    super.initState();
    final t = widget.initialNextNumber.trim();
    _nextCtrl = TextEditingController(
      text: t.isNotEmpty ? t : widget.hintNextSku,
    );
    _digitWidthCtrl = TextEditingController(
      text: widget.data.skuDigitWidth.isNotEmpty
          ? widget.data.skuDigitWidth
          : '1',
    );
    _prefixCtrl = TextEditingController(text: widget.data.skuPrefix);
    _format = widget.data.skuNumberFormat;
    if (!const {'numeric', 'alpha', 'alnum'}.contains(_format)) {
      _format = 'numeric';
    }
    _unique = widget.data.skuUniqueSequential;
    _prefixEnabled = widget.data.skuPrefixEnabled;
  }

  @override
  void dispose() {
    _nextCtrl.dispose();
    _digitWidthCtrl.dispose();
    _prefixCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final w = int.tryParse(_digitWidthCtrl.text.trim()) ?? 1;
    final width = w.clamp(1, 20);
    final updated = widget.data.copyWith(
      nextSkuText: _nextCtrl.text.trim(),
      skuDigitWidth: '$width',
      skuNumberFormat: _format,
      skuUniqueSequential: _unique,
      skuPrefixEnabled: _prefixEnabled,
      skuPrefix: _prefixCtrl.text.trim(),
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxW = math.min(520.0, MediaQuery.sizeOf(context).width - 48);
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'الترقيم التلقائي لـ المنتجات',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.right,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'تحكم في إعدادات وتنسيق الترقيم التلقائي.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldLabel('الرقم التالي', cs),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nextCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        decoration: _dec(cs),
                      ),
                      _footer(
                        'الرقم الذي سيقوم النظام بتعيينه للعنصر التالي.',
                        cs,
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel('تنسيق الترقيم', cs),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _format,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'numeric',
                            child: Text('الأرقام الرقمية (0، 1، 2، …)'),
                          ),
                          DropdownMenuItem(
                            value: 'alpha',
                            child: Text('حروف أبجدية'),
                          ),
                          DropdownMenuItem(
                            value: 'alnum',
                            child: Text('أرقام وحروف'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _format = v);
                        },
                      ),
                      _footer(
                        'اختر الصيغة المراد استخدامها في إنشاء الترقيم (أرقام، حروف، أو مزيج).',
                        cs,
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel('عدد الأرقام', cs),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _digitWidthCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.right,
                        decoration: _dec(cs),
                      ),
                      _footer(
                        'حدد عدد الخانات للرقم التسلسلي. إذا كان الرقم أقل من هذا العدد، تُضاف أصفار من اليسار. مثال: إن كان العدد 5 والرقم 3، يظهر 00003.',
                        cs,
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel('غير مكرر', cs),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_unique ? 'مفعّل' : 'معطّل'),
                          value: _unique,
                          onChanged: (v) => setState(() => _unique = v),
                        ),
                      ),
                      _footer(
                        'تأكد من أن يكون كل رقم في التسلسل فريداً وغير مكرر.',
                        cs,
                      ),
                      const SizedBox(height: 20),
                      _fieldLabel('البادئة', cs),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: cs.outlineVariant),
                          borderRadius: BorderRadius.zero,
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_prefixEnabled ? 'مفعّل' : 'معطّل'),
                          value: _prefixEnabled,
                          onChanged: (v) =>
                              setState(() => _prefixEnabled = v),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _prefixCtrl,
                        enabled: _prefixEnabled,
                        textAlign: TextAlign.right,
                        decoration: _dec(cs).copyWith(
                          hintText: 'مثال: PR أو INV',
                        ),
                      ),
                      _footer(
                        'الرموز أو الأحرف التي تظهر قبل رقم المستند. يمكن أن تكون ثابتة مثل INV أو تتضمن سنة/شهراً حسب سياسة المتجر.',
                        cs,
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _save,
                      child: const Text('حفظ'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String t, ColorScheme cs) {
    return Text(
      t,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: cs.onSurface,
      ),
      textAlign: TextAlign.right,
    );
  }

  Widget _footer(String t, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 12,
          height: 1.45,
          color: cs.onSurfaceVariant,
        ),
        textAlign: TextAlign.right,
      ),
    );
  }

  InputDecoration _dec(ColorScheme cs) {
    return InputDecoration(
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
      isDense: true,
      filled: true,
      fillColor: cs.surface,
    );
  }
}
