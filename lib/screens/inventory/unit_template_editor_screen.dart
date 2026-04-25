import 'package:flutter/material.dart';

import '../../services/product_repository.dart';

/// إنشاء أو تعديل قالب وحدات — الوحدة الأساسية، وحدات أكبر بمعامل تحويل، اسم القالب، نشط.
class UnitTemplateEditorScreen extends StatefulWidget {
  const UnitTemplateEditorScreen({super.key, this.templateId});

  final int? templateId;

  @override
  State<UnitTemplateEditorScreen> createState() =>
      _UnitTemplateEditorScreenState();
}

class _ConvField {
  _ConvField();

  final TextEditingController name = TextEditingController();
  final TextEditingController factor = TextEditingController();
  final TextEditingController symbol = TextEditingController();

  void dispose() {
    name.dispose();
    factor.dispose();
    symbol.dispose();
  }
}

class _UnitTemplateEditorScreenState extends State<UnitTemplateEditorScreen> {
  final _repo = ProductRepository();
  final _baseNameCtrl = TextEditingController();
  final _baseSymbolCtrl = TextEditingController();
  final _templateNameCtrl = TextEditingController();

  final List<_ConvField> _conversions = [];

  bool _active = true;
  bool _loading = true;
  bool _saving = false;
  bool _missingTemplate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.templateId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final t = await _repo.getUnitTemplateById(widget.templateId!);
      if (t == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _missingTemplate = true;
          });
        }
        return;
      }
      final conv = await _repo.listUnitTemplateConversions(widget.templateId!);
      _templateNameCtrl.text = (t['name'] as String?) ?? '';
      _baseNameCtrl.text = (t['baseUnitName'] as String?) ?? '';
      _baseSymbolCtrl.text = (t['baseUnitSymbol'] as String?) ?? '';
      _active = ((t['isActive'] as int?) ?? 1) == 1;
      for (final c in conv) {
        final row = _ConvField();
        row.name.text = (c['unitName'] as String?) ?? '';
        row.factor.text = _fmtFactor((c['factorToBase'] as num?)?.toDouble());
        row.symbol.text = (c['unitSymbol'] as String?) ?? '';
        _conversions.add(row);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtFactor(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
    _baseNameCtrl.dispose();
    _baseSymbolCtrl.dispose();
    _templateNameCtrl.dispose();
    for (final c in _conversions) {
      c.dispose();
    }
    super.dispose();
  }

  void _addConversionRow() {
    setState(() => _conversions.add(_ConvField()));
  }

  void _removeConversionAt(int i) {
    setState(() {
      _conversions[i].dispose();
      _conversions.removeAt(i);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final convMaps = <Map<String, dynamic>>[];
    for (final c in _conversions) {
      final f = double.tryParse(
            c.factor.text.trim().replaceAll(',', '.'),
          ) ??
          0;
      convMaps.add({
        'unitName': c.name.text,
        'unitSymbol': c.symbol.text,
        'factorToBase': f,
      });
    }

    final String? err;
    if (widget.templateId == null) {
      err = await _repo.insertUnitTemplate(
        name: _templateNameCtrl.text,
        baseUnitName: _baseNameCtrl.text,
        baseUnitSymbol: _baseSymbolCtrl.text,
        isActive: _active,
        conversions: convMaps,
      );
    } else {
      err = await _repo.updateUnitTemplate(
        id: widget.templateId!,
        name: _templateNameCtrl.text,
        baseUnitName: _baseNameCtrl.text,
        baseUnitSymbol: _baseSymbolCtrl.text,
        isActive: _active,
        conversions: convMaps,
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.templateId == null
            ? 'تم إنشاء القالب'
            : 'تم حفظ التعديلات'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = cs.brightness == Brightness.dark
        ? const Color(0xFF121212)
        : const Color(0xFFF0F4F8);

    final title = widget.templateId == null ? 'قالب جديد' : 'تعديل القالب';

    if (_missingTemplate) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E3A5F),
            foregroundColor: Colors.white,
            title: Text(title),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: const Center(child: Text('القالب غير موجود.')),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E3A5F),
          foregroundColor: Colors.white,
          title: Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Tooltip(
                                          message:
                                              'أصغر وحدة للقياس في هذا القالب (مثال: كيلوغرام عند بيع بالوزن).',
                                          child: Icon(
                                            Icons.help_outline_rounded,
                                            size: 20,
                                            color: cs.primary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            'اسم الوحدة الأساسية',
                                            textAlign: TextAlign.right,
                                            style: theme.textTheme.labelLarge,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    TextField(
                                      controller: _baseNameCtrl,
                                      textAlign: TextAlign.right,
                                      decoration: InputDecoration(
                                        hintText: 'مثال: جرام',
                                        hintStyle: TextStyle(
                                          color: cs.onSurfaceVariant
                                              .withValues(alpha: 0.85),
                                          fontSize: 13,
                                        ),
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _simpleField(
                                  context,
                                  label: 'التمييز',
                                  hint: 'مثال: جم',
                                  controller: _baseSymbolCtrl,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.zero,
                              border: Border.all(color: cs.outlineVariant),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < _conversions.length; i++)
                                  _conversionRow(context, i),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.tonalIcon(
                                    onPressed: _addConversionRow,
                                    icon: const Icon(Icons.add_rounded, size: 20),
                                    label: const Text('أضف الوحدة'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _simpleField(
                            context,
                            label: 'القالب',
                            hint: 'مثال: الوزن',
                            controller: _templateNameCtrl,
                          ),
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('نشط'),
                            value: _active,
                            onChanged: (v) =>
                                setState(() => _active = v ?? true),
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('حفظ'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _conversionRow(BuildContext context, int i) {
    final cs = Theme.of(context).colorScheme;
    final c = _conversions[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.topStart,
            child: IconButton(
              onPressed: () => _removeConversionAt(i),
              style: IconButton.styleFrom(
                backgroundColor: cs.errorContainer,
                foregroundColor: cs.onErrorContainer,
                minimumSize: const Size(36, 36),
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _simpleField(
                  context,
                  label: 'اسم الوحدة الأكبر',
                  hint: 'مثال: كيلوغرام',
                  controller: c.name,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _simpleField(
                  context,
                  label: 'معامل التحويل',
                  hint: 'مثال: 1000',
                  controller: c.factor,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _simpleField(
                  context,
                  label: 'التمييز',
                  hint: 'مثال: كجم',
                  controller: c.symbol,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _simpleField(
    BuildContext context, {
    required String label,
    required String hint,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textAlign: TextAlign.right,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.85),
              fontSize: 13,
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
