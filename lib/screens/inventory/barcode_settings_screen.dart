import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_settings_repository.dart';

/// تهيئة الباركود — إعدادات حقيقية في [app_settings].
class BarcodeSettingsScreen extends StatefulWidget {
  const BarcodeSettingsScreen({super.key});

  @override
  State<BarcodeSettingsScreen> createState() => _BarcodeSettingsScreenState();
}

class _BarcodeSettingsScreenState extends State<BarcodeSettingsScreen> {
  final _repo = AppSettingsRepository.instance;
  final _patternCtrl = TextEditingController();
  final _weightDivCtrl = TextEditingController();
  final _currencyDivCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _standard = 'code128';
  bool _weightEmbed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await BarcodeSettingsData.load(_repo);
      if (!mounted) return;
      setState(() {
        _standard = d.standard;
        _weightEmbed = d.weightEmbedEnabled;
        _patternCtrl.text = d.embedPattern;
        _weightDivCtrl.text = _fmtNum(d.weightDivisor);
        _currencyDivCtrl.text = _fmtNum(d.currencyDivisor);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtNum(double x) {
    if (x == x.roundToDouble()) return x.toInt().toString();
    return x.toString();
  }

  @override
  void dispose() {
    _patternCtrl.dispose();
    _weightDivCtrl.dispose();
    _currencyDivCtrl.dispose();
    super.dispose();
  }

  bool _validatePattern(String s) {
    final t = s.trim().toUpperCase();
    if (t.isEmpty) return false;
    return RegExp(r'^[XWPN]+$').hasMatch(t);
  }

  Future<void> _save() async {
    final pattern = _patternCtrl.text.trim().toUpperCase();
    if (!_validatePattern(pattern)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'صيغة الباركود المتضمن يجب أن تحتوي فقط على الحروف X و W و P و N.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final wd = double.tryParse(_weightDivCtrl.text.replaceAll(',', '.'));
    final cd = double.tryParse(_currencyDivCtrl.text.replaceAll(',', '.'));
    if (wd == null || wd <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل قيمة صحيحة أكبر من صفر لتقسيم وحدة الوزن.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (cd == null || cd <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل قيمة صحيحة أكبر من صفر لقسمة العملة.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final data = BarcodeSettingsData(
        standard: _standard,
        weightEmbedEnabled: _weightEmbed,
        embedPattern: pattern,
        weightDivisor: wd,
        currencyDivisor: cd,
      );
      await data.save(_repo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تم حفظ إعدادات الباركود.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر الحفظ: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          title: Text(
            'تهيئة الباركود',
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                children: [
                  Text(
                    'حدد تفضيلات وصيغ الباركود لمسح دقيق وضبط التسعير حسب الوزن.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.55,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'نوع الباركود',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (_, c) {
                      final row = c.maxWidth >= 560;
                      final c128 = _FormatCard(
                        selected: _standard == 'code128',
                        title: 'Code 128',
                        description:
                            'باركود مرن يدعم ترميز الأرقام والحروف والرموز، ويُستخدم على نطاق واسع في التوصيل والمستودعات وتتبع المنتجات لقدرته على استيعاب الأكواد الطويلة.',
                        onTap: () => setState(() => _standard = 'code128'),
                      );
                      final ean = _FormatCard(
                        selected: _standard == 'ean13',
                        title: 'EAN 13',
                        description:
                            'معيار مكوّن من 13 رقمًا يُستخدم بشكل شائع في قطاع التجزئة، ويشمل رمز الدولة ورمز المصنّع ورمز المنتج بالإضافة إلى رقم تحقق.',
                        onTap: () => setState(() => _standard = 'ean13'),
                      );
                      if (row) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: c128),
                            const SizedBox(width: 12),
                            Expanded(child: ean),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          c128,
                          const SizedBox(height: 12),
                          ean,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'اختر معيار الباركود الذي سيعتمد عليه النظام في إنشاء وقراءة باركود المنتجات.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 28),
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'باركود متضمن الوزن',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Switch(
                              value: _weightEmbed,
                              onChanged: (v) =>
                                  setState(() => _weightEmbed = v),
                              activeThumbColor: Colors.green.shade600,
                              activeTrackColor: Colors.green.shade200,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _weightEmbed ? 'مفعّل' : 'معطّل',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _weightEmbed
                                    ? Colors.green.shade700
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'استخدم الباركود متضمن الوزن ليتمكّن النظام من قراءة وزن المنتج (والسعر إذا وُجد) مباشرة من الباركود دون الحاجة إلى إدخاله يدويًا.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'صيغة الباركود المتضمن',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _patternCtrl,
                    textAlign: TextAlign.right,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[XWPNxwpn]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'XXXXXXXXWWWWWWPPPPN',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'أدخل صيغة الباركود المدمج وفق النموذج، حيث تُمثل X أرقام المنتج، وW خانات الوزن، وP خانات السعر (إذا لزم الأمر)، وN أي خانات إضافية.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'على سبيل المثال، إذا كان الوزن يُعرض بأربع خانات فسيظهر 250 جرامًا كـ 0250، وإذا كان بخمس خانات فسيظهر كـ 00250. يعتمد اختيار عدد الخانات على طبيعة الأوزان أو الأسعار التي تتعامل بها.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'تقسيم وحدة الوزن',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _weightDivCtrl,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      hintText: 'مثال: 1000',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أدخل القيمة التي يستخدمها النظام لتحويل وحدة الوزن في الباركود إلى وحدة البيع لديك. مثال: إذا بعت بالكيلوغرام والميزان يسجّل بالغرام أدخل 1000.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 24),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'قسمة العملة',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _currencyDivCtrl,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: const InputDecoration(
                      hintText: 'مثال: 100',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'أدخل القيمة التي يستخدمها النظام لتحويل السعر من الوحدة المضمنة في الباركود إلى وحدتك الأساسية للبيع. مثال: إذا بعت بالدينار والباركود بالفلس أدخل 1000، أو إذا كان السعر بالسنت والبيع بالدولار أدخل 100.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.right,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'جاري الحفظ…' : 'حفظ الإعدادات'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: cs.outlineVariant),
      ),
      child: child,
    );
  }
}

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.selected,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final primary = cs.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.zero,
            border: Border.all(
              color: selected ? primary : cs.outlineVariant,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: selected ? primary : cs.onSurface,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? primary : cs.outline,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
