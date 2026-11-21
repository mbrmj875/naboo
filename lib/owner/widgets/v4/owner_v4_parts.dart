import 'package:flutter/material.dart';

import '../../models/owner_section_result.dart';
import '../../theme/owner_dashboard_tokens.dart';

/// بطاقة قسم: عنوان بخط ذهبي قصير في بدايته + محتوى.
class OwnerV4Section extends StatelessWidget {
  const OwnerV4Section({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.semanticsLabel,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Container(
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.cardBorder),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: t.gold,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: TextStyle(
                        color: t.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// رقم واحد: عنوان + قيمة كاملة (بلا قص) + سطر ثانوي، ويفتح تفاصيله عند اللمس.
class OwnerV4StatTile extends StatelessWidget {
  const OwnerV4StatTile({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    this.subtitle,
    this.onTap,
    this.valueSize = 22,
    this.loading = false,
    this.errorText,
    this.onRetry,
    this.accent,
    this.highlight = false,
  });

  final String label;
  final IconData icon;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;
  final double valueSize;
  final bool loading;
  final String? errorText;
  final VoidCallback? onRetry;
  final Color? accent;

  /// بطاقة رئيسية (المبيعات): إطار ذهبي رفيع.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = OwnerDashboardTokens.of(context);
    final iconColor = accent ?? t.ink;

    final Widget valueWidget;
    if (loading) {
      valueWidget = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Semantics(
          label: 'جارٍ التحميل',
          child: Container(
            height: valueSize,
            width: 110,
            decoration: BoxDecoration(
              color: t.navySoft,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      );
    } else if (errorText != null) {
      valueWidget = Row(
        children: [
          Expanded(
            child: Text(
              errorText!,
              style: TextStyle(color: t.danger, fontSize: 13),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('إعادة')),
        ],
      );
    } else {
      valueWidget = Text(value, style: t.numberStyle(valueSize));
    }

    return Material(
      color: t.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highlight ? t.gold : t.cardBorder,
              width: highlight ? 1.4 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: t.navySoft,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 17, color: iconColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: t.inkMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_left,
                        size: 18,
                        color: t.inkMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              valueWidget,
              if (subtitle != null && subtitle!.isNotEmpty && !loading) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(color: t.inkMuted, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// صف من عناصر متساوية العرض؛ يصبح عموداً إذا ضاق كل عنصر عن [minChildWidth].
class OwnerV4AdaptiveRow extends StatelessWidget {
  const OwnerV4AdaptiveRow({
    super.key,
    required this.children,
    this.minChildWidth = 160,
    this.gap = 10,
  });

  final List<Widget> children;
  final double minChildWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final needed = minChildWidth * scale.clamp(1.0, 1.6);
        final perChild =
            (constraints.maxWidth - gap * (children.length - 1)) /
            children.length;
        if (perChild >= needed) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(child: children[i]),
                ],
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: gap),
              children[i],
            ],
          ],
        );
      },
    );
  }
}

/// حالة قسم واحد للعرض في بطاقة رقم.
({bool loading, String? error}) ownerV4SectionState(
  OwnerSectionResult<dynamic>? section,
) {
  if (section == null) return (loading: false, error: null);
  if (!section.hasData && section.isLoading)
    return (loading: true, error: null);
  if (!section.hasData && section.isError) {
    return (loading: false, error: section.errorMessage ?? 'تعذّر التحميل');
  }
  return (loading: false, error: null);
}
