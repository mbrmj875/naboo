import 'package:flutter/material.dart';

import '../utils/iraq_plate.dart';

/// حقل لوحة منظم (المرحلة 6 — الشريحة 2): رقم بلوحة أرقام، وزرّا الحرف
/// والمحافظة. يكتب اللوحة كاملة في [controller] («12345 B البصرة»)، ويقرأ
/// منه أي نص يوضع فيه من خارج الحقل (زيارة سابقة، تعديل بطاقة).
class IraqPlateField extends StatefulWidget {
  const IraqPlateField({
    super.key,
    required this.controller,
    this.defaultProvince,
    this.required = false,
    this.suffixIcon,
    this.onNumberDone,
  });

  final TextEditingController controller;

  /// محافظة المحل: تُوضع للوحة جديدة فارغة.
  final String? defaultProvince;
  final bool required;
  final Widget? suffixIcon;

  /// الموظف أنهى كتابة الرقم (خرج من الحقل أو ضغط «تم»).
  final VoidCallback? onNumberDone;

  @override
  State<IraqPlateField> createState() => _IraqPlateFieldState();
}

class _IraqPlateFieldState extends State<IraqPlateField> {
  final _number = TextEditingController();
  final _focus = FocusNode();
  String? _letter;
  String? _province;
  bool _writing = false;
  bool _defaultApplied = false;

  /// قائمة الحرف أو المحافظة مفتوحة: خروج التركيز من الرقم ليس «انتهاء».
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _readFromController();
    _maybeApplyDefault();
    widget.controller.addListener(_onExternal);
    _number.addListener(_write);
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focus.hasFocus) return;
    // التركيز يخرج أيضاً حين يُفتح اختيار الحرف أو المحافظة؛ ننتظر إطاراً
    // لنعرف، فالسؤال عن السيارة يأتي بعد الاختيار لا فوقه.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _picking || _focus.hasFocus) return;
      widget.onNumberDone?.call();
    });
  }

  @override
  void didUpdateWidget(IraqPlateField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onExternal);
      widget.controller.addListener(_onExternal);
      _readFromController();
    }
    _maybeApplyDefault();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExternal);
    _number.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// محافظة المحل للوحة لم يُكتب فيها شيء بعد.
  void _maybeApplyDefault() {
    if (_defaultApplied) return;
    final d = widget.defaultProvince;
    if (d == null || d.isEmpty) return;
    if (widget.controller.text.trim().isNotEmpty) {
      _defaultApplied = true;
      return;
    }
    _province = d;
    _defaultApplied = true;
  }

  void _readFromController() {
    final p = IraqPlate.parse(widget.controller.text);
    _letter = p.letter;
    _province = p.province;
    if (_number.text != p.number) {
      _writing = true;
      _number.text = p.number;
      _writing = false;
    }
  }

  void _onExternal() {
    if (_writing) return;
    if (widget.controller.text == _compose()) return;
    setState(() {
      _readFromController();
      _defaultApplied = true;
    });
  }

  String _compose() => IraqPlate(
    number: _number.text,
    letter: _letter,
    province: _province,
  ).format();

  void _write() {
    if (_writing) return;
    final v = _compose();
    if (widget.controller.text == v) return;
    _writing = true;
    widget.controller.text = v;
    _writing = false;
  }

  Future<void> _pick({
    required String title,
    required List<String> options,
    required String? current,
    required String noneLabel,
    required String keyPrefix,
    required void Function(String?) onPicked,
  }) async {
    _picking = true;
    final String? picked;
    try {
      picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: Key('${keyPrefix}None'),
                      label: Text(noneLabel),
                      selected: current == null,
                      onSelected: (_) => Navigator.pop(ctx, ''),
                    ),
                    for (final o in options)
                      ChoiceChip(
                        key: Key('${keyPrefix}_$o'),
                        label: Text(o),
                        selected: current == o,
                        onSelected: (_) => Navigator.pop(ctx, o),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _picking = false;
    }
    if (picked == null || !mounted) return;
    setState(() => onPicked(picked!.isEmpty ? null : picked));
    _write();
    widget.onNumberDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chipStyle = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 44),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const Key('plateNumberField'),
          controller: _number,
          focusNode: _focus,
          decoration: InputDecoration(
            labelText: 'رقم اللوحة',
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: '12345',
            suffixIcon: widget.suffixIcon,
          ),
          validator: (v) => widget.required && (v == null || v.trim().isEmpty)
              ? 'رقم اللوحة مطلوب'
              : null,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.start,
          onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('plateLetterButton'),
                style: chipStyle,
                onPressed: () => _pick(
                  title: 'حرف اللوحة',
                  options: kIraqPlateLetters,
                  current: _letter,
                  noneLabel: 'بلا حرف',
                  keyPrefix: 'plateLetter',
                  onPicked: (v) => _letter = v,
                ),
                child: Text(
                  _letter == null ? 'حرف' : 'الحرف $_letter',
                  style: TextStyle(
                    color: _letter == null ? cs.onSurfaceVariant : null,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: OutlinedButton(
                key: const Key('plateProvinceButton'),
                style: chipStyle,
                onPressed: () => _pick(
                  title: 'المحافظة',
                  options: kIraqProvinces,
                  current: _province,
                  noneLabel: 'بلا محافظة',
                  keyPrefix: 'plateProvince',
                  onPicked: (v) => _province = v,
                ),
                child: Text(
                  _province ?? 'المحافظة',
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    color: _province == null ? cs.onSurfaceVariant : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
