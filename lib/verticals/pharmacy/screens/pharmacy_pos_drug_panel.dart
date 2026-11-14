import 'package:flutter/material.dart';

import '../../../utils/iraqi_currency_format.dart';
import '../../_contract/vertical_manifest.dart';
import '../models/pharmacy_batch.dart';
import '../models/pharmacy_pos_drug_panel_data.dart';
import '../models/pharmacy_rx_schedule.dart';
import '../models/pharmacy_substitute_candidate.dart';
import '../services/drug_catalog_repository.dart';
import '../services/fefo_picker_service.dart';
import '../services/pharmacy_pos_drug_panel_service.dart';

/// Host — يحمّل البيانات ويعرض [PharmacyPosDrugPanel] أو `SizedBox.shrink`.
class PharmacyPosDrugPanelHost extends StatefulWidget {
  const PharmacyPosDrugPanelHost({
    super.key,
    required this.args,
    this.panelService,
    this.fefoPicker,
    this.catalog,
  });

  final PosDrugPanelArgs args;
  final PharmacyPosDrugPanelService? panelService;
  final FefoPickerService? fefoPicker;
  final DrugCatalogRepository? catalog;

  @override
  State<PharmacyPosDrugPanelHost> createState() =>
      _PharmacyPosDrugPanelHostState();
}

class _PharmacyPosDrugPanelHostState extends State<PharmacyPosDrugPanelHost> {
  late final PharmacyPosDrugPanelService _service =
      widget.panelService ??
      PharmacyPosDrugPanelService(
        catalog: widget.catalog,
        fefoPicker: widget.fefoPicker,
      );
  late final FefoPickerService _fefoPicker =
      widget.fefoPicker ?? FefoPickerService(catalog: widget.catalog);

  PharmacyPosDrugPanelData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PharmacyPosDrugPanelHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.args.productId != widget.args.productId ||
        oldWidget.args.selectedBatchId != widget.args.selectedBatchId) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final catalog = widget.catalog ?? DrugCatalogRepository();
      final tenantId = await catalog.resolveTenantId();
      final data = await _service.load(
        tenantId: tenantId,
        productId: widget.args.productId,
        selectedBatchId: widget.args.selectedBatchId,
        productNameOverride: widget.args.productName,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _data = null;
        _loading = false;
      });
    }
  }

  Future<void> _pickBatch() async {
    final catalog = widget.catalog ?? DrugCatalogRepository();
    final tenantId = await catalog.resolveTenantId();
    final batches = await _fefoPicker.listSelectableBatches(
      tenantId: tenantId,
      productId: widget.args.productId,
    );
    final selectable = batches.where((b) => b.qty > 0).toList();
    if (!mounted || selectable.isEmpty) return;

    final picked = await showModalBottomSheet<PharmacyBatch>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsetsDirectional.all(16),
            itemCount: selectable.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final b = selectable[i];
              return ListTile(
                title: Text('دفعة ${b.batchNo}'),
                subtitle: Text(
                  'صلاحية ${_pharmacyPosFormatDate(b.expiryDate)} · كمية ${b.qty.toStringAsFixed(0)}',
                ),
                onTap: () => Navigator.pop(ctx, b),
              );
            },
          ),
        );
      },
    );
    if (picked == null) return;
    widget.args.onBatchChanged?.call(picked.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsetsDirectional.all(12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    return PharmacyPosDrugPanel(
      data: data,
      onChangeBatch: widget.args.onBatchChanged == null ? null : _pickBatch,
    );
  }
}

/// لوحة معلومات الدواء في POS — stateless.
class PharmacyPosDrugPanel extends StatelessWidget {
  const PharmacyPosDrugPanel({
    super.key,
    required this.data,
    this.onChangeBatch,
  });

  final PharmacyPosDrugPanelData data;
  final VoidCallback? onChangeBatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ref = data.drugReference;
    final headerLine = _buildHeaderLine();
    final inn = ref.nameEn.isNotEmpty ? ref.nameEn : ref.nameAr;
    final atc = ref.atcCode?.trim();
    final indications = _indicationsLabel(ref.indications, ref.indicationsFreeText);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              headerLine,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 6),
            Text(
              [
                'INN: $inn',
                if (atc != null && atc.isNotEmpty) 'ATC: $atc',
              ].join(' | '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.start,
            ),
            if (indications.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'دواعي: $indications',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.start,
              ),
            ],
            const Divider(height: 20),
            _fefoSection(context),
            if (data.substitutes.isNotEmpty) ...[
              const Divider(height: 20),
              Text(
                '💊 بدائل نفس المادة:',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 6),
              ...data.substitutes.map(_substituteLine),
            ],
            const Divider(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _rxBadge(context, data.rxSchedule),
                if (data.available)
                  Chip(
                    label: const Text('✓ متاح'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: cs.primaryContainer,
                  )
                else
                  Chip(
                    label: const Text('غير متاح'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: cs.errorContainer,
                  ),
                if (data.latestExpiry != null)
                  Text(
                    'آخر صلاحية: ${_pharmacyPosFormatDate(data.latestExpiry!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildHeaderLine() {
    final strength = data.strengthText?.trim();
    final name = data.productName;
    final withStrength =
        strength != null && strength.isNotEmpty ? '$name — $strength' : name;
    final mfgName = data.manufacturer?.name.trim();
    if (mfgName != null && mfgName.isNotEmpty) {
      return '$withStrength — $mfgName';
    }
    return withStrength;
  }

  Widget _fefoSection(BuildContext context) {
    final batch = data.selectedBatch;
    final theme = Theme.of(context);
    if (batch == null) {
      return Text(
        '🔥 FEFO: لا توجد دفعة صالحة',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.error,
        ),
        textAlign: TextAlign.start,
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            '🔥 FEFO: ${batch.batchNo} (تنتهي ${_pharmacyPosFormatDate(batch.expiryDate)})',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.start,
          ),
        ),
        if (onChangeBatch != null)
          TextButton(
            onPressed: onChangeBatch,
            child: const Text('تغيير الدفعة'),
          ),
      ],
    );
  }

  Widget _substituteLine(PharmacySubstituteCandidate s) {
    final tier = s.qualityTier?.trim();
    final tierLabel = tier == null || tier.isEmpty ? '—' : 'Tier $tier';
    final price = IraqiCurrencyFormat.formatIqd(s.sellPrice);
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 4),
      child: Text(
        '• ${s.productName} ($tierLabel · $price)',
        style: const TextStyle(fontSize: 13),
        textAlign: TextAlign.start,
      ),
    );
  }

  Widget _rxBadge(BuildContext context, String rxSchedule) {
    final label = switch (rxSchedule) {
      PharmacyRxSchedule.rx => 'Rx',
      PharmacyRxSchedule.monitored => 'مراقب',
      _ => 'OTC',
    };
    return Chip(
      label: Text('⚠️ Rx/OTC: $label'),
      visualDensity: VisualDensity.compact,
    );
  }

  static String _indicationsLabel(
    List<String> indications,
    String? freeText,
  ) {
    final parts = <String>[
      ...indications.map((e) => e.trim()).where((e) => e.isNotEmpty),
      if (freeText != null && freeText.trim().isNotEmpty) freeText.trim(),
    ];
    return parts.take(6).join(' · ');
  }
}

String _pharmacyPosFormatDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
