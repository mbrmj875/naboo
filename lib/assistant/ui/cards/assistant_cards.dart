import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/customer_phone_launch.dart';
import '../../../theme/design_tokens.dart';
import '../../data/assistant_memory_store.dart';
import '../../exec/assistant_actions.dart';
import '../assistant_view_models.dart';

/// بطاقات نتائج المساعد (م2-4). كل بطاقة تُرسم من نتيجة الأداة لا من نص
/// النموذج، وتنتهي بزر يفتح شاشتها. زوايا قائمة وحدود رفيعة كهوية التطبيق.
class AssistantCard extends StatelessWidget {
  const AssistantCard(this.data, {super.key, this.onOpen});

  final AssistantCardData data;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return switch (data) {
      AssistantStockCard() => _StockCard(data as AssistantStockCard, onOpen),
      AssistantCarSpecCard() => _CarSpecCard(data as AssistantCarSpecCard, onOpen),
      AssistantDraftCard(:final actionId?) => _ActionDraftCard(data as AssistantDraftCard, actionId),
      AssistantDraftCard() => _DraftCard(data as AssistantDraftCard, onOpen),
      AssistantConfirmCard() => _ConfirmCard(data as AssistantConfirmCard),
      AssistantProductCard() => _ProductCard(data as AssistantProductCard, onOpen),
      AssistantFactsCard() => _FactsCard(data as AssistantFactsCard, onOpen),
      AssistantMemoryCard() => _MemoryChip(data as AssistantMemoryCard),
      AssistantCustomerCard() => _CustomerCard(data as AssistantCustomerCard, onOpen),
      AssistantNoticeCard() => _NoticeLine(data as AssistantNoticeCard),
    };
  }
}

/// الإطار المشترك: عنوان، محتوى، زر سفلي.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.action,
    this.onAction,
    this.accent,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final String? action;
  final VoidCallback? onAction;

  /// شريط جانبي ملوّن لبطاقة تحتاج انتباهاً (المسودة).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: BorderDirectional(
          top: BorderSide(color: cs.outline),
          bottom: BorderSide(color: cs.outline),
          end: BorderSide(color: cs.outline),
          start: BorderSide(color: accent ?? cs.outline, width: accent == null ? 1 : 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(isolateLtr(title), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, color: cs.outline.withValues(alpha: 0.6)),
          child,
          if (action != null) ...[
            Divider(height: 1, color: cs.outline.withValues(alpha: 0.6)),
            _CardAction(label: action!, onTap: onAction),
          ],
        ],
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // الكحلي يختفي على الخلفية الداكنة، فيُستعمل الذهبي هناك.
    final fg = cs.brightness == Brightness.dark ? cs.secondary : cs.primary;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.adaptive.arrow_forward, size: 18, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شارة حالة صغيرة: نص + أيقونة، لا لون وحده (الوصولية).
class AssistantBadge extends StatelessWidget {
  const AssistantBadge(this.label, {super.key, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 6, 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 3)],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StockRows extends StatelessWidget {
  const _StockRows(this.rows);
  final List<AssistantStockRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 12, endIndent: 12, color: cs.outline.withValues(alpha: 0.35)),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 12, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isolateLtr(rows[i].name),
                        style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (rows[i].price != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(top: 2),
                          child: Text(
                            isolateLtr('سعر البيع ${rows[i].price}'),
                            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      isolateLtr('${_qty(rows[i].qty)} ${rows[i].unit}'.trim()),
                      style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (rows[i].out)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(top: 3),
                        child: AssistantBadge('خالص', color: AppSemanticColors.danger, icon: Icons.block),
                      )
                    else if (rows[i].low)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(top: 3),
                        child: AssistantBadge('قليل', color: AppSemanticColors.warning, icon: Icons.south),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _qty(num q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}

class _StockCard extends StatelessWidget {
  const _StockCard(this.d, this.onOpen);
  final AssistantStockCard d;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final more = (d.total ?? d.rows.length) - d.rows.length;
    return _Frame(
      icon: Icons.inventory_2_outlined,
      title: d.title,
      trailing: Text(
        '${d.total ?? d.rows.length} صنف',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      action: more > 0 ? '${d.openLabel} (+$more)' : d.openLabel,
      onAction: onOpen,
      child: _StockRows(d.rows),
    );
  }
}

class _CarSpecCard extends StatelessWidget {
  const _CarSpecCard(this.d, this.onOpen);
  final AssistantCarSpecCard d;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final verified = d.confidence == AssistantConfidence.verified;
    return _Frame(
      icon: Icons.directions_car_outlined,
      title: d.title,
      trailing: verified
          ? const AssistantBadge('مؤكد', color: AppSemanticColors.success, icon: Icons.verified_outlined)
          : const AssistantBadge('مصدر واحد', color: AppSemanticColors.warning, icon: Icons.info_outline),
      action: d.available.isEmpty ? null : 'افتح المخزون',
      onAction: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
            child: Text(isolateLtr(d.subtitle), style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ),
          for (final (k, v) in d.specs)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 5, 12, 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(k, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: Text(isolateLtr(v), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          if (!verified)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 6),
              child: Text(
                'تأكد بعصا القياس بعد التعبئة.',
                style: t.textTheme.bodySmall?.copyWith(color: AppSemanticColors.warning),
              ),
            ),
          if (d.available.isNotEmpty) ...[
            Container(
              margin: const EdgeInsetsDirectional.only(top: 6),
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Text('المتوفر عندك', style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
            ColoredBox(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), child: _StockRows(d.available)),
          ],
          if (d.sources.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('المصدر:', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  for (final s in d.sources)
                    Semantics(
                      link: true,
                      label: s.title,
                      child: Container(
                        padding: const EdgeInsetsDirectional.fromSTEB(6, 2, 6, 2),
                        decoration: BoxDecoration(border: Border.all(color: cs.outline)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_new, size: 12, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(s.host, style: t.textTheme.labelSmall?.copyWith(color: cs.primary)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard(this.d, this.onOpen, {this.footer});
  final Widget? footer;
  final AssistantDraftCard d;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return _Frame(
      icon: Icons.edit_note,
      title: d.title,
      accent: cs.secondary,
      trailing: AssistantBadge('مسودة', color: cs.secondary, icon: Icons.hourglass_empty),
      action: footer == null ? d.openLabel : null,
      onAction: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in d.fields)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(f.label, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: f.missing
                        ? Row(
                            children: [
                              const Icon(Icons.edit_outlined, size: 14, color: AppSemanticColors.warning),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  isolateLtr(f.value),
                                  style: t.textTheme.bodySmall?.copyWith(color: AppSemanticColors.warning),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            isolateLtr(f.value),
                            style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                  ),
                ],
              ),
            ),
          for (final w in d.warnings) _WarningLine(w),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 10),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'ما يُحفظ شي قبل ما تضغط «حفظ» بنفسك.',
                    style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          ?footer,
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard(this.d, this.onOpen);
  final AssistantProductCard d;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return _Frame(
      icon: Icons.oil_barrel_outlined,
      title: d.name,
      action: d.openLabel,
      onAction: onOpen,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
        child: Column(
          children: [
            for (final (k, v) in d.details)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 5, 12, 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(k, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                    Expanded(
                      child: Text(isolateLtr(v), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard(this.d, this.onOpen);
  final AssistantFactsCard d;
  final VoidCallback? onOpen;

  static IconData _icon(String kind) => switch (kind) {
    'sales' => Icons.point_of_sale_outlined,
    'cash' => Icons.account_balance_wallet_outlined,
    'debts' => Icons.receipt_long_outlined,
    'staff' => Icons.badge_outlined,
    'oil_card' => Icons.assignment_outlined,
    'car_history' => Icons.history,
    _ => Icons.info_outline,
  };

  static Widget? _flag(String? f) => switch (f) {
    'pending' => const AssistantBadge('معلّقة', color: AppSemanticColors.warning, icon: Icons.schedule),
    'done' || 'invoiced' => const AssistantBadge('مكتملة', color: AppSemanticColors.success, icon: Icons.check),
    'out' => const AssistantBadge('خالص', color: AppSemanticColors.danger, icon: Icons.block),
    'low' => const AssistantBadge('قليل', color: AppSemanticColors.warning, icon: Icons.south),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final more = (d.total ?? d.rows.length) - d.rows.length;
    final label = d.openLabel;
    return _Frame(
      icon: _icon(d.kind),
      title: d.title,
      trailing: d.rows.isEmpty
          ? null
          : Text('${d.total ?? d.rows.length}', style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
      action: label == null ? null : (more > 0 ? '$label (+$more)' : label),
      onAction: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.facts.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final (k, v) in d.facts)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 5, 12, 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(k, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                          Text(isolateLtr(v), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          for (var i = 0; i < d.rows.length; i++) ...[
            if (i > 0 || d.facts.isNotEmpty)
              Divider(height: 1, indent: 12, endIndent: 12, color: cs.outline.withValues(alpha: 0.35)),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 12, 9),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isolateLtr(d.rows[i].title),
                          style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if ((d.rows[i].subtitle ?? '').isNotEmpty)
                          Text(
                            isolateLtr(d.rows[i].subtitle!),
                            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  if (d.rows[i].trailing != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Text(
                        isolateLtr(d.rows[i].trailing!),
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (_flag(d.rows[i].flag) case final w?)
                    Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: w),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// «حفظت: …» مع تراجع فوري. التراجع يحذف الصف نفسه من ذاكرة المحل.
class _MemoryChip extends StatefulWidget {
  const _MemoryChip(this.data);
  final AssistantMemoryCard data;

  @override
  State<_MemoryChip> createState() => _MemoryChipState();
}

class _MemoryChipState extends State<_MemoryChip> {
  bool _undone = false;
  bool _busy = false;

  Future<void> _undo() async {
    setState(() => _busy = true);
    try {
      await AssistantMemoryStore.instance.delete(widget.data.id);
      if (mounted) setState(() => _undone = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ما گدرت أتراجع، تأكد من الإنترنت')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
      decoration: BoxDecoration(border: Border.all(color: cs.outline), color: cs.surface),
      child: Row(
        children: [
          Icon(_undone ? Icons.undo_rounded : Icons.bookmark_added_outlined, size: 18, color: cs.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _undone ? 'تراجعت، ما راح أتذكرها' : 'حفظت: ${widget.data.text}',
              style: t.textTheme.bodyMedium?.copyWith(decoration: _undone ? TextDecoration.lineThrough : null),
            ),
          ),
          if (!_undone && widget.data.id > 0)
            TextButton(onPressed: _busy ? null : () => unawaited(_undo()), child: const Text('تراجع')),
        ],
      ),
    );
  }
}

class _NoticeLine extends StatelessWidget {
  const _NoticeLine(this.data);
  final AssistantNoticeCard data;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final icon = data.kind == 'support' ? Icons.support_agent_rounded : Icons.inventory_2_outlined;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(border: Border.all(color: cs.outline), color: cs.surface),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text(data.text, style: t.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// يجلب هاتف الزبون من الجهاز لبطاقة الزبون (م2-18). تضبطه جلسة المساعد
/// بحسب صلاحية الزبائن؛ null يعني لا هاتف يظهر. الهاتف لا يمر بالنموذج.
abstract final class AssistantCustomerPhone {
  static Future<String?> Function(int customerId)? resolve;
}

class _CustomerCard extends StatefulWidget {
  const _CustomerCard(this.data, this.onOpen);
  final AssistantCustomerCard data;
  final VoidCallback? onOpen;

  @override
  State<_CustomerCard> createState() => _CustomerCardState();
}

class _CustomerCardState extends State<_CustomerCard> {
  late final Future<String?> _phone = _load();

  Future<String?> _load() async {
    final r = AssistantCustomerPhone.resolve;
    if (r == null || widget.data.customerId <= 0) return null;
    try {
      final p = (await r(widget.data.customerId))?.trim();
      return p == null || p.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final d = widget.data;
    return _Frame(
      icon: Icons.person_outline_rounded,
      title: d.name,
      action: widget.onOpen == null ? null : 'افتح الزبائن',
      onAction: widget.onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (k, v) in d.facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(k, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                  Text(v, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          FutureBuilder<String?>(
            future: _phone,
            builder: (context, snap) {
              final p = snap.data;
              if (p == null) return const SizedBox.shrink();
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      '\u2066$p\u2069',
                      style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'انسخ الرقم',
                    icon: const Icon(Icons.copy_outlined, size: 20),
                    onPressed: () {
                      unawaited(Clipboard.setData(ClipboardData(text: p)));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('نُسخ الرقم')));
                    },
                  ),
                  IconButton(
                    tooltip: 'اتصل',
                    icon: const Icon(Icons.call_outlined, size: 20),
                    onPressed: () => unawaited(launchUrl(Uri(scheme: 'tel', path: p))),
                  ),
                  IconButton(
                    tooltip: 'واتساب',
                    icon: const Icon(Icons.chat_outlined, size: 20),
                    onPressed: () =>
                        unawaited(launchUrl(customerWhatsAppUri(p), mode: LaunchMode.externalApplication)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ التنفيذ بتأكيد (م4)

/// سطر تنبيه داخل بطاقة: أيقونة ونص، لا لون وحده.
class _WarningLine extends StatelessWidget {
  const _WarningLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: AppSemanticColors.warning),
          const SizedBox(width: 6),
          Expanded(child: Text(isolateLtr(text), style: t.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// نص حالة الاقتراح بعد الضغط.
String? _stateText(AssistantPendingAction a, {required String doneText}) => switch (a.state.value) {
  AssistantActionState.done => doneText,
  AssistantActionState.cancelled => 'ألغيته. ما تغيّر شي.',
  AssistantActionState.failed => a.message ?? 'ما گدرت أكمل.',
  AssistantActionState.expired => 'هذا الاقتراح من جلسة سابقة. اسألني مرة ثانية.',
  _ => null,
};

class _StateLine extends StatelessWidget {
  const _StateLine(this.a, {required this.doneText});
  final AssistantPendingAction a;
  final String doneText;

  @override
  Widget build(BuildContext context) {
    final text = _stateText(a, doneText: doneText);
    if (text == null) return const SizedBox.shrink();
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final (icon, color) = switch (a.state.value) {
      AssistantActionState.done => (Icons.check_circle_outline, AppSemanticColors.success),
      AssistantActionState.failed => (Icons.error_outline, cs.error),
      _ => (Icons.info_outline, cs.onSurfaceVariant),
    };
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: t.textTheme.bodySmall?.copyWith(color: color))),
          ],
        ),
      ),
    );
  }
}

/// بطاقة تجهيز حية: الزر يفتح النموذج المعبّأ، والبدائل تفتحه بالبديل.
class _ActionDraftCard extends StatelessWidget {
  const _ActionDraftCard(this.d, this.actionId);
  final AssistantDraftCard d;
  final String actionId;

  @override
  Widget build(BuildContext context) {
    final a = AssistantActions.of(actionId);
    return ValueListenableBuilder<AssistantActionState>(
      valueListenable: a.state,
      builder: (context, state, _) {
        final busy = state == AssistantActionState.running;
        final open = state == AssistantActionState.ready || state == AssistantActionState.done && a.repeatable;
        final cs = Theme.of(context).colorScheme;
        return _DraftCard(
          d,
          null,
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (d.choices.isNotEmpty && open) ...[
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 4),
                  child: Text(
                    d.choicesLabel ?? 'أو اختر بديلاً:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in d.choices)
                        OutlinedButton(
                          onPressed: busy ? null : () => unawaited(AssistantActions.run(actionId, choice: c)),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                          child: Text(isolateLtr(c)),
                        ),
                    ],
                  ),
                ),
              ],
              _StateLine(a, doneText: 'انحفظت من الشاشة.'),
              if (open) ...[
                Divider(height: 1, color: cs.outline.withValues(alpha: 0.6)),
                _CardAction(
                  label: busy ? 'تنفتح الشاشة…' : d.openLabel,
                  onTap: busy ? null : () => unawaited(AssistantActions.run(actionId)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// «قبل ← بعد» بزرّي تأكيد وإلغاء. لا شيء يتغير قبل «تأكيد».
class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard(this.d);
  final AssistantConfirmCard d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final a = AssistantActions.of(d.actionId);
    return ValueListenableBuilder<AssistantActionState>(
      valueListenable: a.state,
      builder: (context, state, _) {
        final waiting = state == AssistantActionState.ready || state == AssistantActionState.running;
        final busy = state == AssistantActionState.running;
        return _Frame(
          icon: Icons.fact_check_outlined,
          title: d.title,
          accent: waiting ? cs.secondary : null,
          trailing: waiting ? AssistantBadge('ينتظر تأكيدك', color: cs.secondary, icon: Icons.hourglass_empty) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (label, before, after) in d.changes)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(label, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      Flexible(
                        child: Text(
                          isolateLtr(before),
                          style: t.textTheme.bodyMedium?.copyWith(
                            decoration: TextDecoration.lineThrough,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
                        child: Icon(Icons.adaptive.arrow_forward, size: 16, color: cs.onSurfaceVariant),
                      ),
                      Flexible(
                        child: Text(
                          isolateLtr(after),
                          style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final (label, value) in d.facts)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 84,
                        child: Text(label, style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ),
                      Expanded(child: Text(isolateLtr(value), style: t.textTheme.bodyMedium)),
                    ],
                  ),
                ),
              for (final w in d.warnings) _WarningLine(w),
              _StateLine(a, doneText: d.doneText),
              if (waiting)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: busy ? null : () => unawaited(AssistantActions.run(d.actionId)),
                          style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                          child: Text(busy ? 'لحظة…' : d.confirmLabel),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy ? null : () => AssistantActions.cancel(d.actionId),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(44, 44)),
                          child: const Text('إلغاء'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
