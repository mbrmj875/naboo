import 'package:flutter/material.dart';

import '../../../theme/sale_brand.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../utils/oil_notes_money_parser.dart';

/// شريط معاينة مبالغ من الملاحظات — محلي + تحليل ذكي عند الطلب + تأكيد يدوي.
class OilNotesMoneyPreviewBar extends StatefulWidget {
  const OilNotesMoneyPreviewBar({
    super.key,
    required this.result,
    required this.onConfirm,
    required this.onDismiss,
    this.onRequestAi,
    this.aiLoading = false,
    this.enabled = true,
    this.showAiEvenIfEmpty = false,
  });

  final OilNotesMoneyParseResult result;

  /// يُستدعى بمجموع الفلس للمبالغ المختارة فقط.
  final ValueChanged<int> onConfirm;
  final VoidCallback onDismiss;

  /// طلب تحليل DeepSeek (اختياري).
  final VoidCallback? onRequestAi;
  final bool aiLoading;
  final bool enabled;

  /// إظهار زر التحليل الذكي حتى لو لم يجد المحلل المحلي شيئاً.
  final bool showAiEvenIfEmpty;

  @override
  State<OilNotesMoneyPreviewBar> createState() =>
      _OilNotesMoneyPreviewBarState();
}

class _OilNotesMoneyPreviewBarState extends State<OilNotesMoneyPreviewBar> {
  late List<bool> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<bool>.from(widget.result.defaultSelection);
  }

  @override
  void didUpdateWidget(covariant OilNotesMoneyPreviewBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameHits(oldWidget.result, widget.result)) {
      _selected = List<bool>.from(widget.result.defaultSelection);
    }
  }

  bool _sameHits(OilNotesMoneyParseResult a, OilNotesMoneyParseResult b) {
    if (a.source != b.source) return false;
    if (a.hits.length != b.hits.length) return false;
    for (var i = 0; i < a.hits.length; i++) {
      if (a.hits[i].dinars != b.hits[i].dinars ||
          a.hits[i].start != b.hits[i].start ||
          a.hits[i].type != b.hits[i].type ||
          a.hits[i].defaultSelected != b.hits[i].defaultSelected) {
        return false;
      }
    }
    return true;
  }

  int get _selectedFils => widget.result.totalFilsForSelection(_selected);

  int get _selectedDinars => _selectedFils ~/ 1000;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final hasHits = result.isNotEmpty;
    if (!hasHits && !widget.showAiEvenIfEmpty && !widget.aiLoading) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final gold = SaleBrandColors.gold;
    final totalLabel = IraqiCurrencyFormat.formatInt(_selectedDinars);
    final canAi = widget.onRequestAi != null &&
        widget.enabled &&
        !widget.aiLoading;

    return Container(
      margin: const EdgeInsetsDirectional.only(top: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withValues(alpha: 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasHits
                      ? (result.isFromAi
                          ? 'تحليل ذكي — راجع البنود ثم أضف'
                          : 'اكتشاف محلي — يمكنك تحسينه بالتحليل الذكي')
                      : 'لم يُعثر على مبالغ واضحة محلياً',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
              if (result.isFromAi)
                Container(
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'AI',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          if (result.summary != null && result.summary!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              result.summary!,
              style: TextStyle(
                fontSize: 11.5,
                color: cs.onSurfaceVariant,
                height: 1.3,
              ),
              textAlign: TextAlign.start,
            ),
          ],
          if (widget.aiLoading) ...[
            const SizedBox(height: 10),
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'جارٍ التحليل الذكي…',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            if (hasHits) ...[
              const SizedBox(height: 6),
              for (var i = 0; i < result.hits.length; i++) ...[
                if (i > 0) const SizedBox(height: 2),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _selected[i],
                  onChanged: !widget.enabled
                      ? null
                      : (v) {
                          setState(() => _selected[i] = v ?? false);
                        },
                  title: Text(
                    '${IraqiCurrencyFormat.formatInt(result.hits[i].dinars)} د.ع',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.start,
                  ),
                  subtitle: Text(
                    '${result.hits[i].typeLabelAr}: ${result.hits[i].contextLabel}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant,
                      height: 1.25,
                    ),
                    textAlign: TextAlign.start,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'المجموع المختار: $totalLabel د.ع',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: cs.primary,
                ),
                textAlign: TextAlign.start,
              ),
            ],
            const SizedBox(height: 8),
            if (canAi)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 8),
                child: OutlinedButton.icon(
                  onPressed: widget.onRequestAi,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(
                    hasHits && !result.isFromAi
                        ? 'تحليل ذكي أفضل'
                        : (result.isFromAi
                            ? 'إعادة التحليل الذكي'
                            : 'تحليل ذكي للمبالغ'),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: widget.enabled ? widget.onDismiss : null,
                    child: const Text('تجاهل'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: !widget.enabled || !hasHits || _selectedFils <= 0
                        ? null
                        : () => widget.onConfirm(_selectedFils),
                    style: FilledButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('إضافة للمجموع'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
