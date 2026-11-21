import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../services/oil_change_whatsapp_campaign_queue.dart';
import '../widgets/oil_change_log_stitch.dart';

/// طبقة تقدّم حملة واتساب + شريحة مصغّرة.
class OilChangeWhatsappCampaignProgressLayer extends StatelessWidget {
  const OilChangeWhatsappCampaignProgressLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OilChangeWhatsappCampaignQueue.instance,
      builder: (context, _) {
        final q = OilChangeWhatsappCampaignQueue.instance;
        if (!q.isActive &&
            q.phase != OilChangeCampaignPhase.completed &&
            q.phase != OilChangeCampaignPhase.paused &&
            q.phase != OilChangeCampaignPhase.cancelled) {
          return const SizedBox.shrink();
        }

        if (q.minimized && q.isActive) {
          return Align(
            alignment: AlignmentDirectional.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 88),
              child: _MinimizedChip(queue: q),
            ),
          );
        }

        if (q.phase == OilChangeCampaignPhase.completed ||
            q.phase == OilChangeCampaignPhase.cancelled ||
            q.phase == OilChangeCampaignPhase.paused) {
          return _ResultBanner(queue: q);
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            ModalBarrier(
              color: AppColors.primary.withValues(alpha: 0.45),
              dismissible: false,
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _ProgressCard(queue: q),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MinimizedChip extends StatelessWidget {
  const _MinimizedChip({required this.queue});

  final OilChangeWhatsappCampaignQueue queue;

  @override
  Widget build(BuildContext context) {
    final done = queue.sent + queue.failed + queue.skipped;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(999),
      color: OilChangeLogStitchMetrics.success,
      child: InkWell(
        onTap: () => queue.setMinimized(false),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'إرسال $done/${queue.total}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.queue});

  final OilChangeWhatsappCampaignQueue queue;

  String _formatCountdown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final pct = (queue.progressFraction * 100).round();
    final done = queue.sent + queue.failed + queue.skipped;

    return Material(
      elevation: 18,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                children: [
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: queue.progressFraction,
                          strokeWidth: 7,
                          color: AppColors.accentGold,
                          backgroundColor:
                              OilChangeLogStitchMetrics.surfaceContainerHigh,
                        ),
                        Text(
                          '$pct%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'جاري الإرسال صامتاً…',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'لا تغلق التطبيق — يمكنك متابعة العمل',
                    style: TextStyle(
                      fontSize: 12,
                      color: OilChangeLogStitchMetrics.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _StatCell(
                        label: 'نُجح',
                        value: '${queue.sent}',
                        color: OilChangeLogStitchMetrics.success,
                      ),
                      _StatCell(
                        label: 'فشل',
                        value: '${queue.failed}',
                        color: OilChangeLogStitchMetrics.error,
                      ),
                      _StatCell(
                        label: 'متبقي',
                        value: '${queue.pending}',
                        color: OilChangeLogStitchMetrics.outline,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(value: queue.progressFraction),
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      '$done / ${queue.total} رسالة',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  if (queue.currentCustomerName != null) ...[
                    const SizedBox(height: 12),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(
                          queue.currentCustomerName!.characters.first,
                        ),
                      ),
                      title: Text(queue.currentCustomerName!),
                      subtitle: Text(queue.currentCarLabel ?? ''),
                      trailing: Text(
                        queue.lastOutcomeLabel ?? '',
                        style: TextStyle(
                          fontSize: 11,
                          color: OilChangeLogStitchMetrics.success,
                        ),
                      ),
                    ),
                  ],
                  if (queue.phase ==
                          OilChangeCampaignPhase.waitingInterval &&
                      queue.secondsUntilNext > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'الرسالة التالية خلال ${_formatCountdown(queue.secondsUntilNext)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            if (queue.phase == OilChangeCampaignPhase.resting)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                color: AppColors.accentGold.withValues(alpha: 0.18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'استراحة أمان',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      queue.pauseReason ?? '',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '${_formatCountdown(queue.restSecondsRemaining)} متبقية',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => queue.setMinimized(true),
                      child: const Text('تصغير'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: OilChangeLogStitchMetrics.error,
                      ),
                      onPressed: queue.requestCancel,
                      child: const Text('إيقاف'),
                    ),
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

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: OilChangeLogStitchMetrics.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.queue});

  final OilChangeWhatsappCampaignQueue queue;

  @override
  Widget build(BuildContext context) {
    final msg = switch (queue.phase) {
      OilChangeCampaignPhase.completed =>
        'اكتملت الحملة — نجح ${queue.sent} · فشل ${queue.failed}',
      OilChangeCampaignPhase.cancelled => 'تم إيقاف الحملة',
      OilChangeCampaignPhase.paused =>
        queue.pauseReason ?? 'توقفت الحملة مؤقتاً',
      _ => '',
    };

    return Align(
      alignment: AlignmentDirectional.topCenter,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: OilChangeLogStitchMetrics.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(msg, style: const TextStyle(color: Colors.white))),
              const SizedBox(width: 8),
              TextButton(
                onPressed: queue.resetToIdle,
                child: const Text('إغلاق', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
