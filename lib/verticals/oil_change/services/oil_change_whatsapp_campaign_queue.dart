import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../utils/app_logger.dart';
import '../models/oil_change_campaign_recipient.dart';
import '../models/oil_change_campaign_settings.dart';
import '../utils/oil_change_campaign_message_renderer.dart';
import '../utils/oil_change_whatsapp_user_messages.dart';
import 'oil_change_whatsapp_notify_service.dart';

enum OilChangeCampaignPhase {
  idle,
  /// جارٍ رفع الحملة للسيرفر مرة واحدة.
  submitting,
  running,
  waitingInterval,
  resting,
  paused,
  /// سُلِّمت للسيرفر — الإرسال يكمل بعد إغلاق التطبيق.
  handedOff,
  completed,
  cancelled,
}

/// طابور حملة واتساب — التسليم للسيرفر (n8n) ثم يعمل بدون بقاء التطبيق مفتوحاً.
class OilChangeWhatsappCampaignQueue extends ChangeNotifier {
  OilChangeWhatsappCampaignQueue._();

  static final OilChangeWhatsappCampaignQueue instance =
      OilChangeWhatsappCampaignQueue._();

  OilChangeCampaignPhase phase = OilChangeCampaignPhase.idle;
  bool minimized = false;

  int total = 0;
  int sent = 0;
  int failed = 0;
  int skipped = 0;

  int secondsUntilNext = 0;
  int restSecondsRemaining = 0;

  String? currentCustomerName;
  String? currentCarLabel;
  String? lastOutcomeLabel;
  String? pauseReason;

  bool _cancelRequested = false;
  Future<void>? _runFuture;

  int get pending => (total - sent - failed - skipped).clamp(0, total);

  double get progressFraction {
    if (total <= 0) return 0;
    if (phase == OilChangeCampaignPhase.submitting) return 0.15;
    if (phase == OilChangeCampaignPhase.handedOff) return 1;
    return ((sent + failed + skipped) / total).clamp(0.0, 1.0);
  }

  bool get isActive {
    return phase == OilChangeCampaignPhase.submitting ||
        phase == OilChangeCampaignPhase.running ||
        phase == OilChangeCampaignPhase.waitingInterval ||
        phase == OilChangeCampaignPhase.resting ||
        phase == OilChangeCampaignPhase.paused;
  }

  bool get isServerHandedOff => phase == OilChangeCampaignPhase.handedOff;

  Future<void> start({
    required List<OilChangeCampaignRecipient> recipients,
    required String messageTemplate,
    required String storeTitle,
    OilChangeCampaignSettings settings = const OilChangeCampaignSettings(),
  }) async {
    if (isActive || phase == OilChangeCampaignPhase.handedOff) return;

    final capped = recipients.take(settings.maxMessages).toList();
    if (capped.isEmpty) return;

    _cancelRequested = false;
    minimized = false;
    total = capped.length;
    sent = 0;
    failed = 0;
    skipped = 0;
    pauseReason = null;
    lastOutcomeLabel = null;
    currentCustomerName = null;
    currentCarLabel = null;
    phase = OilChangeCampaignPhase.submitting;
    notifyListeners();

    _runFuture = _submitToServer(
      recipients: capped,
      messageTemplate: messageTemplate,
      storeTitle: storeTitle,
      settings: settings,
    );
    await _runFuture;
  }

  void requestCancel() {
    _cancelRequested = true;
    if (phase == OilChangeCampaignPhase.submitting) {
      phase = OilChangeCampaignPhase.cancelled;
      pauseReason = 'تم إلغاء التسليم قبل الإرسال';
      notifyListeners();
    }
  }

  void setMinimized(bool value) {
    if (minimized == value) return;
    minimized = value;
    notifyListeners();
  }

  Future<void> _submitToServer({
    required List<OilChangeCampaignRecipient> recipients,
    required String messageTemplate,
    required String storeTitle,
    required OilChangeCampaignSettings settings,
  }) async {
    try {
      final messages = <Map<String, dynamic>>[];
      for (final recipient in recipients) {
        if (_cancelRequested) {
          phase = OilChangeCampaignPhase.cancelled;
          notifyListeners();
          return;
        }

        final message = renderOilChangeCampaignMessage(
          template: messageTemplate,
          recipient: recipient,
          storeTitle: storeTitle,
        );
        if (message.length > settings.maxMessageLength) {
          skipped++;
          continue;
        }
        if (recipient.phone.trim().isEmpty) {
          skipped++;
          continue;
        }

        messages.add({
          'customer_phone': recipient.phone.trim(),
          'message_text': message,
          if (recipient.orderId > 0) 'order_id': recipient.orderId,
          'customer_name': recipient.customerName,
        });
      }

      total = messages.length + skipped;
      if (messages.isEmpty) {
        phase = OilChangeCampaignPhase.paused;
        pauseReason = skipped > 0
            ? 'لا رسائل صالحة للإرسال (تخطي $skipped)'
            : 'لا رسائل للإرسال';
        notifyListeners();
        return;
      }

      if (_cancelRequested) {
        phase = OilChangeCampaignPhase.cancelled;
        notifyListeners();
        return;
      }

      lastOutcomeLabel = 'جارٍ التسليم للسيرفر…';
      notifyListeners();

      final outcome =
          await OilChangeWhatsappNotifyService.instance.submitCampaignBatch(
        messages: messages,
        intervalSeconds: settings.intervalSeconds,
        restEveryMessages: settings.restEveryMessages,
        restMinutes: settings.restMinutes,
        storeTitle: storeTitle,
      );

      if (_cancelRequested) {
        phase = OilChangeCampaignPhase.cancelled;
        notifyListeners();
        return;
      }

      if (outcome.isSent) {
        sent = messages.length;
        phase = OilChangeCampaignPhase.handedOff;
        lastOutcomeLabel = 'سُلِّمت للسيرفر';
        pauseReason =
            'تم تسليم $sent رسالة للسيرفر — الإرسال يكمل حتى لو أغلقت التطبيق';
        notifyListeners();
        AppLogger.info(
          'oil_change_wa_campaign',
          'handed off to server sent=$sent skipped=$skipped',
        );
        return;
      }

      failed = messages.length;
      phase = OilChangeCampaignPhase.paused;
      pauseReason = OilChangeWhatsappUserMessages.snackbarForOutcome(outcome);
      lastOutcomeLabel = 'فشل التسليم';
      notifyListeners();
    } catch (e, st) {
      AppLogger.error('oil_change_wa_campaign', 'queue failed', e, st);
      phase = OilChangeCampaignPhase.paused;
      pauseReason = 'تعذّر تسليم الحملة للسيرفر';
      notifyListeners();
    } finally {
      _runFuture = null;
    }
  }

  void resetToIdle() {
    if (isActive) return;
    phase = OilChangeCampaignPhase.idle;
    total = 0;
    sent = 0;
    failed = 0;
    skipped = 0;
    minimized = false;
    secondsUntilNext = 0;
    restSecondsRemaining = 0;
    currentCustomerName = null;
    currentCarLabel = null;
    lastOutcomeLabel = null;
    pauseReason = null;
    notifyListeners();
  }
}
