import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/print_settings_provider.dart';
import '../../services/print_settings_repository.dart';
import '../../utils/screen_layout.dart';
import '../../verticals/oil_change/widgets/oil_change_form_theme.dart';

/// بيانات المتجر — تُحفظ في [print_settings] وتظهر على إيصال البيع.
class StoreInfoScreen extends StatefulWidget {
  const StoreInfoScreen({super.key});

  @override
  State<StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends State<StoreInfoScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final List<TextEditingController> _phones = [TextEditingController()];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    for (final c in _phones) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await PrintSettingsRepository.instance.load();
      if (!mounted) return;
      _name.text = p.storeTitleLine.trim();
      _address.text = p.storeAddress.trim();
      for (final c in _phones) {
        c.dispose();
      }
      _phones
        ..clear()
        ..addAll(
          p.storePhones.isEmpty
              ? [TextEditingController()]
              : p.storePhones.map((p) => TextEditingController(text: p)),
        );
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّر تحميل بيانات المتجر';
      });
    }
  }

  void _addPhoneField() {
    setState(() => _phones.add(TextEditingController()));
  }

  void _removePhoneField(int index) {
    if (_phones.length <= 1) {
      _phones.first.clear();
      return;
    }
    setState(() {
      _phones.removeAt(index).dispose();
    });
  }

  List<String> _collectPhones() =>
      _phones.map((c) => c.text.trim()).where((p) => p.isNotEmpty).toList();

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم المتجر')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final current = await PrintSettingsRepository.instance.load();
      final phones = _collectPhones();
      final next = current.copyWith(
        storeTitleLine: name,
        storeAddress: _address.text.trim(),
        storePhones: phones,
      );
      if (mounted) {
        await context.read<PrintSettingsProvider>().save(next);
      } else {
        await PrintSettingsRepository.instance.save(next);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ بيانات المتجر — ستظهر على إيصال البيع'),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر الحفظ. حاول مرة أخرى.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = ScreenLayout.of(context);
    final pad = layout.pageHorizontalGap;

    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: OilChangeFormTheme.appBar(
            context: context,
            title: 'بيانات المتجر',
            actions: [
              TextButton(
                onPressed: _loading || _saving ? null : _save,
                child: Text(
                  _saving ? 'جارٍ الحفظ…' : 'حفظ',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: OilChangeFormTheme.gold,
                  ),
                ),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: EdgeInsetsDirectional.fromSTEB(pad, 16, pad, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'تُستخدم هذه البيانات على إيصال البيع بعد كل عملية طباعة.',
                        style: TextStyle(
                          color: OilChangeFormTheme.secondaryText(context),
                          height: 1.4,
                        ),
                        textAlign: TextAlign.start,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: cs.error,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: OilChangeFormTheme.gold.withValues(alpha: 0.12),
                            border: Border.all(
                              color: OilChangeFormTheme.gold.withValues(alpha: 0.55),
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.store_rounded,
                            size: 42,
                            color: OilChangeFormTheme.gold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _StoreField(
                        controller: _name,
                        label: 'اسم المتجر',
                        icon: Icons.store_rounded,
                      ),
                      const SizedBox(height: 14),
                      _StoreField(
                        controller: _address,
                        label: 'العنوان',
                        icon: Icons.location_on_rounded,
                        minLines: 1,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_rounded,
                            size: 20,
                            color: OilChangeFormTheme.gold,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'أرقام هاتف المتجر',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: OilChangeFormTheme.emphasisText(context),
                            ),
                            textAlign: TextAlign.start,
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _saving ? null : _addPhoneField,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('إضافة رقم'),
                            style: TextButton.styleFrom(
                              foregroundColor: OilChangeFormTheme.gold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _phones.length; i++) ...[
                        if (i > 0) const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _StoreField(
                                controller: _phones[i],
                                label: i == 0
                                    ? 'الهاتف الرئيسي'
                                    : 'هاتف إضافي ${i + 1}',
                                icon: Icons.phone_rounded,
                                keyboard: TextInputType.phone,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.start,
                              ),
                            ),
                            if (_phones.length > 1) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'حذف الرقم',
                                onPressed:
                                    _saving ? null : () => _removePhoneField(i),
                                icon: Icon(
                                  Icons.remove_circle_outline_rounded,
                                  color: cs.error.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _StoreField extends StatelessWidget {
  const _StoreField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard = TextInputType.text,
    this.minLines = 1,
    this.maxLines = 1,
    this.textDirection,
    this.textAlign,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType keyboard;
  final int minLines;
  final int maxLines;
  final TextDirection? textDirection;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      minLines: minLines,
      maxLines: maxLines,
      textDirection: textDirection,
      textAlign: textAlign ?? TextAlign.start,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: OilChangeFormTheme.gold, size: 22),
      ),
    );
  }
}
