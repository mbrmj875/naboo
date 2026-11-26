import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/stock/stock_actions_repository.dart';
import '../../../services/stock/stock_engine.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/stock_qty_format.dart';
import '../../../verticals/oil_change/widgets/oil_change_form_theme.dart';

/// صنف تعمل عليه نوافذ المخزون.
class StockSheetProduct {
  const StockSheetProduct({
    required this.id,
    required this.name,
    this.unitLabel = '',
  });

  final int id;
  final String name;
  final String unitLabel;
}

/// إطار موحّد لنوافذ المخزون: ثيم بطاقة الغيار، عنوان ورصيد المكانين.
class _StockSheetFrame extends StatelessWidget {
  const _StockSheetFrame({
    required this.title,
    required this.product,
    required this.children,
  });

  final String title;
  final StockSheetProduct product;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = OilChangeFormTheme.wrap(context, Theme.of(context));
    final gold = OilChangeFormTheme.goldOf(context);
    return Theme(
      data: theme,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.md,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: OilChangeFormTheme.isDark(context)
                      ? gold
                      : OilChangeFormTheme.navyOf(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                product.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: OilChangeFormTheme.secondaryText(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(height: 1, color: gold.withValues(alpha: 0.35)),
              const SizedBox(height: AppSpacing.md),
              _BalancesRow(product: product),
              const SizedBox(height: AppSpacing.md),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// رصيد المحل والمخزن ومتوسط الكلفة.
class _BalancesRow extends StatelessWidget {
  const _BalancesRow({required this.product});

  final StockSheetProduct product;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({double shop, double store, double avgCost, bool track})>(
      future: StockActionsRepository.instance.balancesOf(product.id),
      builder: (context, snap) {
        final b = snap.data;
        final u = product.unitLabel.isEmpty ? '' : ' ${product.unitLabel}';
        Widget cell(String label, String value, {Color? color}) => Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: OilChangeFormTheme.fieldContainerDecoration(context),
                child: Column(
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: OilChangeFormTheme.goldOf(context),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: color ?? OilChangeFormTheme.emphasisText(context),
                          ),
                    ),
                  ],
                ),
              ),
            );
        if (b == null) return const SizedBox(height: 56);
        return Row(
          children: [
            cell(
              StockPlace.shop.label,
              '${StockQtyFormat.format(b.shop)}$u',
              color: b.shop < 0 ? AppSemanticColors.danger : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            cell(StockPlace.store.label, '${StockQtyFormat.format(b.store)}$u'),
            const SizedBox(width: AppSpacing.sm),
            cell('متوسط الكلفة', IraqiCurrencyFormat.formatIqd(b.avgCost)),
          ],
        );
      },
    );
  }
}

Widget _placePicker(
  BuildContext context,
  StockPlace value,
  ValueChanged<StockPlace> onChanged, {
  String label = 'المكان',
}) {
  return InputDecorator(
    decoration: OilChangeFormTheme.field(context: context, labelText: label),
    child: SegmentedButton<StockPlace>(
      segments: const [
        ButtonSegment(value: StockPlace.shop, label: Text('المحل')),
        ButtonSegment(value: StockPlace.store, label: Text('المخزن')),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
    ),
  );
}

String _actorOf(BuildContext context) {
  try {
    return context.read<AuthProvider>().displayName;
  } catch (_) {
    return '';
  }
}

bool _isOwnerOf(BuildContext context) {
  try {
    final a = context.read<AuthProvider>();
    return a.isOwner || a.isAdmin;
  } catch (_) {
    return true;
  }
}

Future<bool?> _sheet(BuildContext context, Widget child) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => child,
    );

/// «استلام بضاعة» (ق-8): الكمية، سعر الشراء للوحدة، المورد، المكان.
Future<bool?> showReceiveGoodsSheet(
  BuildContext context,
  StockSheetProduct product, {
  StockPlace place = StockPlace.shop,
}) =>
    _sheet(context, _ReceiveSheet(product: product, initialPlace: place));

class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({required this.product, required this.initialPlace});

  final StockSheetProduct product;
  final StockPlace initialPlace;

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  final _supplier = TextEditingController();
  late StockPlace _place = widget.initialPlace;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _supplier.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = StockQtyFormat.parse(_qty.text) ?? 0;
    final c = StockQtyFormat.parse(_cost.text) ?? 0;
    if (q <= 0) {
      setState(() => _error = 'اكتب الكمية المستلمة');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await StockActionsRepository.instance.receive(
      productId: widget.product.id,
      qty: q,
      unitCost: c,
      place: _place,
      supplierName: _supplier.text.trim().isEmpty ? null : _supplier.text.trim(),
      actor: _actorOf(context),
    );
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _saving = false;
        _error = r.message;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.product.unitLabel;
    return _StockSheetFrame(
      title: 'استلام بضاعة',
      product: widget.product,
      children: [
        TextField(
          controller: _qty,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: OilChangeFormTheme.field(
            context: context,
            labelText: u.isEmpty ? 'الكمية المستلمة' : 'الكمية المستلمة ($u)',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _cost,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: OilChangeFormTheme.field(
            context: context,
            labelText: u.isEmpty ? 'سعر الشراء للوحدة' : 'سعر الشراء / $u',
            helperText: 'يتحدّث متوسط الكلفة تلقائياً',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _supplier,
          decoration: OilChangeFormTheme.field(
            context: context,
            labelText: 'المورد (اختياري)',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _placePicker(context, _place, (p) => setState(() => _place = p),
            label: 'تدخل إلى'),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: const TextStyle(color: AppSemanticColors.danger)),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ…' : 'استلام'),
        ),
      ],
    );
  }
}

/// تحويل بين المحل والمخزن. [qty] اقتراح (مثلاً الكمية الناقصة، ق-3).
Future<bool?> showTransferSheet(
  BuildContext context,
  StockSheetProduct product, {
  StockPlace from = StockPlace.store,
  double? qty,
}) =>
    _sheet(context, _TransferSheet(product: product, from: from, qty: qty));

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.product, required this.from, this.qty});

  final StockSheetProduct product;
  final StockPlace from;
  final double? qty;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  late final _qty = TextEditingController(
    text: widget.qty == null ? '' : StockQtyFormat.format(widget.qty),
  );
  late StockPlace _from = widget.from;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final q = StockQtyFormat.parse(_qty.text) ?? 0;
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await StockActionsRepository.instance.transfer(
      productId: widget.product.id,
      qty: q,
      from: _from,
      actor: _actorOf(context),
    );
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _saving = false;
        _error = r.message;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final to = _from == StockPlace.shop ? StockPlace.store : StockPlace.shop;
    return _StockSheetFrame(
      title: 'تحويل: من ${_from.label} إلى ${to.label}',
      product: widget.product,
      children: [
        _placePicker(context, _from, (p) => setState(() => _from = p),
            label: 'من'),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _qty,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: OilChangeFormTheme.field(
            context: context,
            labelText: 'الكمية',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: const TextStyle(color: AppSemanticColors.danger)),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ التحويل…' : 'تحويل'),
        ),
      ],
    );
  }
}

/// «جرد هذا الصنف» (ق-10): العدّ يصير الرصيد. للمالك فوراً، وللموظف بعد
/// موافقة المالك (ق-17).
Future<bool?> showQuickCountSheet(
  BuildContext context,
  StockSheetProduct product, {
  StockPlace place = StockPlace.shop,
}) =>
    _sheet(context, _CountSheet(product: product, place: place));

class _CountSheet extends StatefulWidget {
  const _CountSheet({required this.product, required this.place});

  final StockSheetProduct product;
  final StockPlace place;

  @override
  State<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends State<_CountSheet> {
  final _count = TextEditingController();
  late StockPlace _place = widget.place;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = StockQtyFormat.parse(_count.text);
    if (c == null) {
      setState(() => _error = 'اكتب العدد الموجود فعلاً');
      return;
    }
    final owner = _isOwnerOf(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final diff = await StockActionsRepository.instance.count(
        productId: widget.product.id,
        place: _place,
        counted: c,
        approveNow: owner,
        actor: _actorOf(context),
      );
      if (!mounted) return;
      final msg = diff.abs() < 1e-9
          ? 'لا فرق: الرصيد مطابق'
          : owner
              ? (diff > 0
                  ? 'زيادة جرد ${StockQtyFormat.format(diff)}'
                  : 'عجز جرد ${StockQtyFormat.format(-diff)}')
              : 'سُجّل العدّ، وينتظر موافقة المالك';
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(msg)));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _StockSheetFrame(
      title: 'جرد هذا الصنف',
      product: widget.product,
      children: [
        _placePicker(context, _place, (p) => setState(() => _place = p)),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _count,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          decoration: OilChangeFormTheme.field(
            context: context,
            labelText: 'العدد الموجود على الرف',
            helperText: _isOwnerOf(context)
                ? 'الفرق يُطبَّق فوراً ويظهر في «حركات المخزون»'
                : 'الفرق يُطبَّق بعد موافقة المالك',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: const TextStyle(color: AppSemanticColors.danger)),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ العدّ'),
        ),
      ],
    );
  }
}
