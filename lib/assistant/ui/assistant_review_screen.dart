import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../exec/assistant_exec_port.dart';
import '../exec/assistant_name_match.dart';
import 'assistant_view_models.dart' show isolateLtr;

/// جدول مراجعة فاتورة المورّد أو الجرد (م4-9، م4-14).
///
/// كل سطر: الاسم كما قُرئ، والمنتج المطابق، والكمية والسعر قابلة للتعديل.
/// «محتمل» لا يُعتمد حتى يختار المستخدم المنتج. «جديد» لا يدخل السند حتى
/// يُضاف كصنف من نموذج الإضافة المعبّأ. لا سند وفيه سطر غير محسوم، والسند
/// واحد لكل اتجاه عبر دوال المخزون الموجودة.
class AssistantReviewScreen extends StatefulWidget {
  const AssistantReviewScreen({
    super.key,
    required this.draft,
    required this.port,
    required this.onCommitted,
    required this.openNewProduct,
    this.qtyOf,
  });

  final AssistantReviewDraft draft;
  final AssistantExecPort port;
  final VoidCallback onCommitted;

  /// يفتح نموذج إضافة منتج معبّأً بالاسم ويرجع (المعرّف، الاسم) إن حُفظ.
  final Future<Object?> Function(String name) openNewProduct;

  /// كمية المنتج الحالية (للجرد بعد اختيار منتج يدوياً).
  final Future<double?> Function(int productId)? qtyOf;

  @override
  State<AssistantReviewScreen> createState() => _AssistantReviewScreenState();
}

class _AssistantReviewScreenState extends State<AssistantReviewScreen> {
  bool _saving = false;
  String? _error;

  bool get _count => widget.draft.mode == 'count';
  List<AssistantReviewLine> get _lines => widget.draft.lines;

  Future<void> _choose(AssistantReviewLine l, (int, String) c) async {
    final q = _count ? await widget.qtyOf?.call(c.$1) : null;
    if (!mounted) return;
    setState(() {
      l
        ..productId = c.$1
        ..productName = c.$2;
      if (_count) l.currentQty = q ?? 0;
    });
  }

  Future<void> _addNew(AssistantReviewLine l) async {
    final out = await widget.openNewProduct(l.readName);
    if (!mounted || out is! (int, String)) return;
    l.match = AssistantMatch(AssistantMatchGrade.likely, candidates: [out, ...l.match.candidates]);
    await _choose(l, out);
  }

  Future<void> _commit() async {
    final d = widget.draft;
    if (!d.canCommit || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final moves = <AssistantStockMove>[
      for (final l in _lines)
        if (!l.removed)
          (
            productId: l.productId!,
            delta: _count ? l.qty - (l.currentQty ?? 0) : l.qty,
            unitPriceIqd: (l.unitPriceFils ?? 0) / 1000,
          ),
    ].where((m) => m.delta != 0).toList();
    if (moves.isEmpty) {
      setState(() {
        _saving = false;
        _error = _count ? 'المعدود يطابق المخزون. ما في فرق يُسجَّل.' : 'ما في كميات.';
      });
      return;
    }
    final err = await widget.port.applyStockMoves(
      moves: moves,
      reason: _count ? 'جرد' : 'فاتورة مورّد${d.supplier == null ? '' : ' ${d.supplier}'}',
      sourceType: _count ? 'assistant_count' : 'supplier',
      supplier: _count ? null : d.supplier,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _saving = false;
        _error = err;
      });
      return;
    }
    widget.onCommitted();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final open = _lines.where((l) => !l.resolved).length;
    final image = widget.draft.image;
    return Scaffold(
      appBar: AppBar(title: Text(_count ? 'مراجعة الجرد' : 'مراجعة فاتورة المورّد')),
      body: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
        children: [
          Text(
            _count
                ? 'راجع كل صنف والكمية التي عددتها. الفرق عن المخزون يُسجَّل بسند بعد ضغطك فقط.'
                : 'قارن كل رقم بالفاتورة بعينك. لا يُسجَّل شيء قبل ضغطك على «سجّل السند».',
            style: t.textTheme.bodyMedium,
          ),
          if (image != null) ...[
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: 'صورة الفاتورة، اضغط للتكبير',
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (c) => Dialog.fullscreen(
                    child: Stack(
                      children: [
                        InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(image))),
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: IconButton.filled(
                            tooltip: 'إغلاق',
                            onPressed: () => Navigator.of(c).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: ClipRect(
                  child: SizedBox(height: 160, child: Image.memory(image, fit: BoxFit.cover)),
                ),
              ),
            ),
          ],
          if (widget.draft.supplier != null) ...[
            const SizedBox(height: 12),
            Text('المورّد: ${widget.draft.supplier}', style: t.textTheme.titleSmall),
          ],
          const SizedBox(height: 8),
          for (final l in _lines)
            _LineTile(
              line: l,
              count: _count,
              onChoose: (c) => _choose(l, c),
              onAddNew: () => _addNew(l),
              onChanged: () => setState(() {}),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: t.textTheme.bodySmall?.copyWith(color: cs.error)),
                ),
              Text(
                open == 0 ? 'كل الأصناف محسومة.' : 'باقي $open غير محسوم. احسمها أو احذفها قبل التسجيل.',
                style: t.textTheme.bodySmall?.copyWith(
                  color: open == 0 ? AppSemanticColors.success : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: widget.draft.canCommit && !_saving ? _commit : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(_saving ? 'لحظة…' : 'سجّل السند'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.count,
    required this.onChoose,
    required this.onAddNew,
    required this.onChanged,
  });

  final AssistantReviewLine line;
  final bool count;
  final ValueChanged<(int, String)> onChoose;
  final VoidCallback onAddNew;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final l = line;
    final (label, icon, color) = l.removed
        ? ('محذوف من القائمة', Icons.remove_circle_outline, cs.onSurfaceVariant)
        : l.productId != null
        ? ('مطابق', Icons.check_circle_outline, AppSemanticColors.success)
        : l.match.candidates.isNotEmpty
        ? ('تختاره أنت', Icons.help_outline, AppSemanticColors.warning)
        : ('غير موجود بالمخزون', Icons.add_box_outlined, cs.primary);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        color: l.removed ? cs.surfaceContainerHighest.withValues(alpha: 0.4) : cs.surface,
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: t.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                tooltip: l.removed ? 'أرجعه للقائمة' : 'احذفه من القائمة',
                onPressed: () {
                  l.removed = !l.removed;
                  onChanged();
                },
                icon: Icon(l.removed ? Icons.undo : Icons.delete_outline),
              ),
            ],
          ),
          Text(
            'المقروء: ${isolateLtr(l.readName)}',
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (!l.removed) ...[
            const SizedBox(height: 6),
            if (l.productId != null)
              Text(
                'الصنف: ${isolateLtr(l.productName ?? '')}',
                style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            if (l.match.candidates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in l.match.candidates)
                      ChoiceChip(
                        label: Text(isolateLtr(c.$2)),
                        selected: l.productId == c.$1,
                        onSelected: (_) => onChoose(c),
                      ),
                  ],
                ),
              ),
            if (l.productId == null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onAddNew,
                  icon: const Icon(Icons.add),
                  label: const Text('أضفه كصنف جديد'),
                ),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _NumField(
                    label: count ? 'المعدود' : 'الكمية',
                    value: l.qty,
                    onChanged: (v) {
                      l.qty = v ?? 0;
                      onChanged();
                    },
                  ),
                ),
                if (!count) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NumField(
                      label: 'سعر المفرد (دينار)',
                      value: l.unitPriceFils == null ? null : l.unitPriceFils! / 1000,
                      onChanged: (v) {
                        l.unitPriceFils = v == null ? null : (v * 1000).round();
                        onChanged();
                      },
                    ),
                  ),
                ],
              ],
            ),
            if (count && l.productId != null && l.currentQty != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'بالمخزون ${_fmt(l.currentQty!)}، الفرق ${_signed(l.qty - l.currentQty!)}',
                  style: t.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(2);
  static String _signed(double v) => v > 0 ? '+${_fmt(v)}' : _fmt(v);
}

class _NumField extends StatefulWidget {
  const _NumField({required this.label, required this.value, required this.onChanged});
  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value == null ? '' : _LineTile._fmt(widget.value!),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: widget.label, isDense: true, border: const OutlineInputBorder()),
    onChanged: (s) => widget.onChanged(double.tryParse(s.replaceAll(',', '').trim())),
  );
}
