import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';
import '../../../services/stock/stock_actions_repository.dart';
import '../../../services/stock/stock_engine.dart';
import '../../../theme/app_corner_style.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/design_tokens.dart';
import '../../../utils/stock_qty_format.dart';
import '../../../verticals/oil_change/widgets/oil_change_form_theme.dart';
import '../inventory_management_screen.dart';

/// «حركات المخزون» (المرحلة 2): كل حركة بنوعها — بيع، إرجاع، بطاقة، استلام،
/// تحويل، جرد — بالمكان والموظف والوقت.
class StockMovesScreen extends StatefulWidget {
  const StockMovesScreen({super.key, this.productId, this.productName});

  /// لعرض حركات صنف واحد.
  final int? productId;
  final String? productName;

  @override
  State<StockMovesScreen> createState() => _StockMovesScreenState();
}

class _StockMovesScreenState extends State<StockMovesScreen> {
  final _repo = StockActionsRepository.instance;
  StockPlace? _place;
  String? _kind;
  List<StockMoveRow> _rows = const [];
  int _pending = 0;
  bool _loading = true;

  static const _kinds = <String?, String>{
    null: 'كل الأنواع',
    StockMoveKind.sale: 'بيع',
    StockMoveKind.card: 'بطاقة غيار',
    StockMoveKind.directSale: 'بيع مباشر',
    StockMoveKind.saleReturn: 'إرجاع',
    StockMoveKind.cardReturn: 'إرجاع بطاقة',
    StockMoveKind.receive: 'استلام بضاعة',
    StockMoveKind.purchaseList: 'قائمة مشتريات',
    StockMoveKind.transfer: 'تحويل',
    StockMoveKind.countGain: 'زيادة جرد',
    StockMoveKind.countLoss: 'عجز جرد',
    StockMoveKind.voucherIn: 'إذن وارد',
    StockMoveKind.voucherOut: 'إذن صادر',
    StockMoveKind.edit: 'تعديل',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _repo.moves(
      productId: widget.productId,
      place: _place,
      kind: _kind,
    );
    final pending = await _repo.listPending();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _pending = pending.length;
      _loading = false;
    });
  }

  bool get _isOwner {
    try {
      final a = context.read<AuthProvider>();
      return a.isOwner || a.isAdmin;
    } catch (_) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = OilChangeFormTheme.wrap(context, Theme.of(context));
    final gold = OilChangeFormTheme.goldOf(context);
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: widget.productName == null
              ? 'حركات المخزون'
              : 'حركات: ${widget.productName}',
          actions: [
            IconButton(
              tooltip: 'السندات',
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InventoryManagementScreen(),
                ),
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (_pending > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: InkWell(
                    borderRadius: AppCornerStyle.of(context).md,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PendingCountsScreen(),
                        ),
                      );
                      await _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: OilChangeFormTheme.fieldContainerDecoration(
                        context,
                      ).copyWith(
                        border: Border.all(color: AppSemanticColors.warning),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.pending_actions_rounded,
                            color: AppSemanticColors.warning,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _isOwner
                                  ? '$_pending فرق جرد بانتظار موافقتك'
                                  : '$_pending فرق جرد بانتظار موافقة المالك',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_left_rounded, color: gold),
                        ],
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<StockPlace?>(
                      segments: const [
                        ButtonSegment(value: null, label: Text('الكل')),
                        ButtonSegment(
                          value: StockPlace.shop,
                          label: Text('المحل'),
                        ),
                        ButtonSegment(
                          value: StockPlace.store,
                          label: Text('المخزن'),
                        ),
                      ],
                      selected: {_place},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) {
                        setState(() => _place = s.first);
                        _load();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                initialValue: _kind,
                decoration: OilChangeFormTheme.field(
                  context: context,
                  labelText: 'نوع الحركة',
                ),
                items: [
                  for (final e in _kinds.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) {
                  setState(() => _kind = v);
                  _load();
                },
              ),
              const SizedBox(height: AppSpacing.md),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Center(
                    child: Text(
                      'لا حركات بعد',
                      style: TextStyle(
                        color: OilChangeFormTheme.secondaryText(context),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  decoration: OilChangeFormTheme.fieldContainerDecoration(
                    context,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < _rows.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            color: gold.withValues(alpha: 0.18),
                          ),
                        _MoveTile(row: _rows[i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoveTile extends StatelessWidget {
  const _MoveTile({required this.row});

  final StockMoveRow row;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final up = row.delta > 0;
    final color = up ? AppSemanticColors.success : AppSemanticColors.danger;
    final when = DateFormat('yyyy/MM/dd  HH:mm').format(row.at);
    final who = (row.actor ?? '').trim();
    final note = (row.note ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.productName,
                  style: t.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: OilChangeFormTheme.emphasisText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    row.label,
                    row.place.label,
                    if (who.isNotEmpty) who,
                    if (note.isNotEmpty) note,
                  ].join(' · '),
                  style: t.bodySmall?.copyWith(
                    color: OilChangeFormTheme.goldOf(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  when,
                  style: t.labelSmall?.copyWith(
                    color: OilChangeFormTheme.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${up ? '+' : ''}${StockQtyFormat.format(row.delta)}',
            style: t.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// فروق الجرد بانتظار موافقة المالك (ق-17).
class PendingCountsScreen extends StatefulWidget {
  const PendingCountsScreen({super.key});

  @override
  State<PendingCountsScreen> createState() => _PendingCountsScreenState();
}

class _PendingCountsScreenState extends State<PendingCountsScreen> {
  final _repo = StockActionsRepository.instance;
  List<PendingCount> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _repo.listPending();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  ({bool owner, String name}) get _who {
    try {
      final a = context.read<AuthProvider>();
      return (owner: a.isOwner || a.isAdmin, name: a.displayName);
    } catch (_) {
      return (owner: true, name: '');
    }
  }

  Future<void> _decide(PendingCount c, bool approve) async {
    await _repo.decide(c, approve: approve, owner: _who.name);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = OilChangeFormTheme.wrap(context, Theme.of(context));
    final gold = OilChangeFormTheme.goldOf(context);
    final owner = _who.owner;
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: 'فروق الجرد بانتظار الموافقة',
          actions: const [],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
                ? Center(
                    child: Text(
                      'لا فروق تنتظر الموافقة',
                      style: TextStyle(
                        color: OilChangeFormTheme.secondaryText(context),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final c = _rows[i];
                      final gain = c.diff > 0;
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration:
                            OilChangeFormTheme.fieldContainerDecoration(context),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              c.productName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${c.place.label} · الرصيد عند العدّ '
                              '${StockQtyFormat.format(c.systemQty)} · العدّ '
                              '${StockQtyFormat.format(c.counted)}'
                              '${c.countedBy.isEmpty ? '' : ' · ${c.countedBy}'}',
                              style: TextStyle(color: gold, fontSize: 12.5),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              gain
                                  ? 'زيادة جرد ${StockQtyFormat.format(c.diff)}'
                                  : 'عجز جرد ${StockQtyFormat.format(-c.diff)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: gain
                                    ? AppSemanticColors.success
                                    : AppSemanticColors.danger,
                              ),
                            ),
                            if (owner) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => _decide(c, true),
                                      child: const Text('موافقة'),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _decide(c, false),
                                      child: const Text('رفض'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
