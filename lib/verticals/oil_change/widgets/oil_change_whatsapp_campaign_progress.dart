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
            q.phase != OilChangeCampaignPhase.handedOff &&
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
            q.phase == OilChangeCampaignPhase.handedOff ||
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
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(999),
      color: OilChangeLogStitchMetrics.success,
      child: InkWell(
        onTap: () => queue.setMinimized(false),
        borderRadius: BorderRadius.circular(999),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'تسليم للسيرفر…',
                style: TextStyle(
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

  @override
  Widget build(BuildContext context) {
    final pct = (queue.progressFraction * 100).round();

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
                          value: queue.progressFraction > 0
                              ? queue.progressFraction
                              : null,
                          strokeWidth: 7,
                          color: AppColors.accentGold,
                          backgroundColor:
                              OilChangeLogStitchMetrics.surfaceContainerHigh,
                        ),
                        Text(
                          queue.phase == OilChangeCampaignPhase.submitting
                              ? '…'
                              : '$pct%',
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
                    'جارٍ تسليم الحملة للسيرفر…',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'بعد التسليم يكمل الإرسال حتى لو أغلقت التطبيق',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: OilChangeLogStitchMetrics.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${queue.total} رسالة جاهزة',
                    style: const TextStyle(fontSize: 13),
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
                      child: const Text('إلغاء'),
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

class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.queue});

  final OilChangeWhatsappCampaignQueue queue;

  @override
  Widget build(BuildContext context) {
    final msg = switch (queue.phase) {
      OilChangeCampaignPhase.handedOff =>
        queue.pauseReason ??
            'تم التسليم للسيرفر — الإرسال يكمل بعد إغلاق التطبيق',
      OilChangeCampaignPhase.completed =>
        'اكتملت الحملة — نجح ${queue.sent} · فشل ${queue.failed}',
      OilChangeCampaignPhase.cancelled => 'تم إيقاف الحملة',
      OilChangeCampaignPhase.paused =>
        queue.pauseReason ?? 'توقفت الحملة مؤقتاً',
      _ => '',
    };

    final bg = queue.phase == OilChangeCampaignPhase.paused ||
            queue.phase == OilChangeCampaignPhase.cancelled
        ? OilChangeLogStitchMetrics.error
        : OilChangeLogStitchMetrics.success;

    return Align(
      alignment: AlignmentDirectional.topCenter,
      child: SafeArea(
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          color: bg,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    msg,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: queue.resetToIdle,
                  child: const Text(
                    'إغلاق',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
