import 'package:flutter/material.dart';

import '../utils/whatsapp_failure_reason_ar.dart';

/// شريط واحد عند إيقاف طابور الإرسال، بدل عشرات الأخطاء المتشابهة.
class WhatsappSendBlockBanner extends StatelessWidget {
  const WhatsappSendBlockBanner({
    super.key,
    required this.block,
    required this.onAction,
  });

  final WhatsappSendBlock block;
  final ValueChanged<WhatsappFixAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final copy = block.copy;
    final label = whatsappFixActionLabelAr(copy.action);
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            copy.messageAr,
            textAlign: TextAlign.start,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onErrorContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            copy.fixAr,
            textAlign: TextAlign.start,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onErrorContainer,
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: () => onAction(copy.action),
                child: Text(label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
