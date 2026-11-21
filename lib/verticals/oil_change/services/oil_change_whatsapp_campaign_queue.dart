import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../utils/app_logger.dart';
import '../models/oil_change_campaign_recipient.dart';
import '../models/oil_change_campaign_settings.dart';
import '../models/oil_change_whatsapp_notify_outcome.dart';
import '../utils/oil_change_campaign_message_renderer.dart';
import 'oil_change_whatsapp_notify_service.dart';

enum OilChangeCampaignPhase {
  idle,
  running,
  waitingInterval,
  resting,
  paused,
  completed,
  cancelled,
}

/// طابور إرسال حملة واتساب — يعمل في الخلفية مع عدّادات واستراحات أمان.
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
    return ((sent + failed + skipped) / total).clamp(0.0, 1.0);
  }

  bool get isActive {
    return phase == OilChangeCampaignPhase.running ||
        phase == OilChangeCampaignPhase.waitingInterval ||
        phase == OilChangeCampaignPhase.resting ||
        phase == OilChangeCampaignPhase.paused;
  }

  Future<void> start({
    required List<OilChangeCampaignRecipient> recipients,
    required String messageTemplate,
    required String storeTitle,
    OilChangeCampaignSettings settings = const OilChangeCampaignSettings(),
  }) async {
    if (isActive) return;

    final capped = recipients.take(settings.maxMessages).toList();
    if (capped.isEmpty) return;

    _cancelRequested = false;
    minimized = false;
    total = capped.length;
    sent = 0;
    failed = 0;
    skipped = 0;
    pauseReason = null;
    phase = OilChangeCampaignPhase.running;
    notifyListeners();

    _runFuture = _runLoop(
      recipients: capped,
      messageTemplate: messageTemplate,
      storeTitle: storeTitle,
      settings: settings,
    );
    await _runFuture;
  }

  void requestCancel() {
    _cancelRequested = true;
    if (phase == OilChangeCampaignPhase.resting ||
        phase == OilChangeCampaignPhase.waitingInterval ||
        phase == OilChangeCampaignPhase.paused) {
      phase = OilChangeCampaignPhase.cancelled;
      notifyListeners();
    }
  }

  void setMinimized(bool value) {
    if (minimized == value) return;
    minimized = value;
    notifyListeners();
  }

  Future<void> _runLoop({
    required List<OilChangeCampaignRecipient> recipients,
    required String messageTemplate,
    required String storeTitle,
    required OilChangeCampaignSettings settings,
  }) async {
    try {
      for (var i = 0; i < recipients.length; i++) {
        if (_cancelRequested) {
          phase = OilChangeCampaignPhase.cancelled;
          notifyListeners();
          return;
        }

        final recipient = recipients[i];
        currentCustomerName = recipient.customerName;
        currentCarLabel = recipient.displayCar;
        phase = OilChangeCampaignPhase.running;
        notifyListeners();

        final message = renderOilChangeCampaignMessage(
          template: messageTemplate,
          recipient: recipient,
          storeTitle: storeTitle,
        );

        if (message.length > settings.maxMessageLength) {
          skipped++;
          lastOutcomeLabel = 'تخطّي — الرسالة طويلة';
          notifyListeners();
        } else {
          final outcome =
              await OilChangeWhatsappNotifyService.instance.sendCustomMessage(
            customerPhone: recipient.phone,
            messageText: message,
            order: recipient.orderRow,
            orderId: recipient.orderId,
            storeTitle: storeTitle,
          );

          if (outcome.isSent) {
            sent++;
            lastOutcomeLabel = 'تم الإرسال';
          } else if (outcome.reason ==
              OilChangeWhatsappNotifyReason.invalidPhone) {
            skipped++;
            lastOutcomeLabel = 'رقم غير صالح';
          } else {
            failed++;
            lastOutcomeLabel = _labelForOutcome(outcome);
          }
          notifyListeners();

          if (outcome.reason ==
                  OilChangeWhatsappNotifyReason.whatsappDisconnected ||
              outcome.reason == OilChangeWhatsappNotifyReason.unauthorized) {
            phase = OilChangeCampaignPhase.paused;
            pauseReason = lastOutcomeLabel;
            notifyListeners();
            return;
          }

          if (outcome.reason == OilChangeWhatsappNotifyReason.rateLimited) {
            phase = OilChangeCampaignPhase.paused;
            pauseReason =
                'تم إيقاف الحملة مؤقتاً — انتظر 10 دقائق ثم أعد المحاولة';
            notifyListeners();
            return;
          }
        }

        final sentSoFar = sent + failed + skipped;
        if (sent > 0 &&
            settings.restEveryMessages > 0 &&
            sent % settings.restEveryMessages == 0 &&
            sentSoFar < total) {
          final rested = await _restCountdown(
            settings.restMinutes * 60,
            reason:
                'تم إرسال $sent رسالة — استراحة ${settings.restMinutes} دقائق',
          );
          if (!rested) return;
        }

        if (i < recipients.length - 1 && !_cancelRequested) {
          final waited = await _intervalCountdown(settings.intervalSeconds);
          if (!waited) return;
        }
      }

      phase = OilChangeCampaignPhase.completed;
      notifyListeners();
      AppLogger.info(
        'oil_change_wa_campaign',
        'done sent=$sent failed=$failed skipped=$skipped',
      );
    } catch (e, st) {
      AppLogger.error('oil_change_wa_campaign', 'queue failed', e, st);
      phase = OilChangeCampaignPhase.paused;
      pauseReason = 'تعذّر إكمال الحملة';
      notifyListeners();
    } finally {
      _runFuture = null;
    }
  }

  Future<bool> _intervalCountdown(int seconds) async {
    phase = OilChangeCampaignPhase.waitingInterval;
    for (var s = seconds; s > 0; s--) {
      if (_cancelRequested) {
        phase = OilChangeCampaignPhase.cancelled;
        notifyListeners();
        return false;
      }
      secondsUntilNext = s;
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    secondsUntilNext = 0;
    return true;
  }

  Future<bool> _restCountdown(int seconds, {required String reason}) async {
    phase = OilChangeCampaignPhase.resting;
    pauseReason = reason;
    for (var s = seconds; s > 0; s--) {
      if (_cancelRequested) {
        phase = OilChangeCampaignPhase.cancelled;
        notifyListeners();
        return false;
      }
      restSecondsRemaining = s;
      notifyListeners();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    restSecondsRemaining = 0;
    pauseReason = null;
    return true;
  }

  String _labelForOutcome(OilChangeWhatsappNotifyOutcome outcome) {
    switch (outcome.reason) {
      case OilChangeWhatsappNotifyReason.sent:
        return 'تم الإرسال';
      case OilChangeWhatsappNotifyReason.noInternet:
        return 'لا يوجد إنترنت';
      case OilChangeWhatsappNotifyReason.rateLimited:
        return 'حد الإرسال';
      case OilChangeWhatsappNotifyReason.whatsappDisconnected:
        return 'واتساب غير متصل';
      case OilChangeWhatsappNotifyReason.invalidPhone:
        return 'رقم غير صالح';
      default:
        return 'فشل الإرسال';
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
