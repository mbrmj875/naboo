import 'package:flutter/material.dart';

import '../models/owner_command_center_snapshot.dart';
import '../models/owner_section_result.dart';

/// شريط تنبيه عند نجاح جزئي — بعض الأقسام فشلت والباقي يعمل.
///
/// يعرض:
/// - تنبيه عام بالعربية.
/// - عدد الأقسام الفاشلة + قائمة قابلة للتوسعة بأسماء الأقسام ورسائل الخطأ.
/// - زر "إعادة المحاولة" يستدعي [onRetry] إن توفّر (يُفضَّل تمرير
///   `OwnerCommandCenterProvider.refreshAll`).
class OwnerPartialStatusBanner extends StatefulWidget {
  const OwnerPartialStatusBanner({
    super.key,
    required this.status,
    this.snapshot,
    this.onRetry,
  });

  final CommandCenterScreenStatus status;
  final OwnerCommandCenterSnapshot? snapshot;
  final VoidCallback? onRetry;

  @override
  State<OwnerPartialStatusBanner> createState() =>
      _OwnerPartialStatusBannerState();
}

class _OwnerPartialStatusBannerState extends State<OwnerPartialStatusBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.status != CommandCenterScreenStatus.partial) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final failures = widget.snapshot?.failedSectionDiagnostics ?? const [];
    final count = failures.length;
    final countLabel = count > 0 ? ' ($count)' : '';

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
      child: Material(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: cs.onTertiaryContainer,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تعذّر تحميل بعض البطاقات$countLabel — يمكنك إعادة المحاولة من البطاقة أو السحب للتحديث',
                      style: TextStyle(
                        color: cs.onTertiaryContainer,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (count > 0)
                    IconButton(
                      tooltip: _expanded ? 'إخفاء التفاصيل' : 'إظهار التفاصيل',
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                  if (widget.onRetry != null)
                    TextButton.icon(
                      onPressed: widget.onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: cs.onTertiaryContainer,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('إعادة المحاولة'),
                    ),
                ],
              ),
              if (_expanded && failures.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 8),
                  child: _FailureList(
                    failures: failures,
                    onColor: cs.onTertiaryContainer,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FailureList extends StatelessWidget {
  const _FailureList({
    required this.failures,
    required this.onColor,
  });

  final List<({String label, String? error})> failures;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final f in failures)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.fiber_manual_record,
                    size: 8,
                    color: onColor.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.label,
                          style: TextStyle(
                            color: onColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if ((f.error ?? '').isNotEmpty)
                          Text(
                            f.error!,
                            style: TextStyle(
                              color: onColor.withValues(alpha: 0.75),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                      ],
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
