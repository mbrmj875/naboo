import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../../utils/app_logger.dart';
import '../models/oil_change_whatsapp_notify_outcome.dart';
import '../utils/oil_change_whatsapp_notify_classifier.dart';
import '../utils/whatsapp_delivery_proof_key.dart';
import 'oil_change_whatsapp_delivery_reconcile.dart';
import 'oil_change_whatsapp_outbox.dart';

/// يعيد إرسال طابور واتساب المحلي تلقائياً عند عودة الشبكة — بشروط آمنة فقط.
///
/// لا يعيد: رقم غير صالح، محفظة، أخطاء نهائية.
/// حد أقصى للمحاولات التلقائية لكل صف، مع تأخير بين الرسائل.
class OilChangeWhatsappOutboxAutoRetry with WidgetsBindingObserver {
  OilChangeWhatsappOutboxAutoRetry._();

  static final OilChangeWhatsappOutboxAutoRetry instance =
      OilChangeWhatsappOutboxAutoRetry._();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  var _started = false;
  var _running = false;
  DateTime? _lastRunAt;

  static const _minGapBetweenRuns = Duration(seconds: 45);
  static const _gapBetweenMessages = Duration(seconds: 8);

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any(
        (r) =>
            r == ConnectivityResult.wifi ||
            r == ConnectivityResult.mobile ||
            r == ConnectivityResult.ethernet,
      );
      if (online) unawaited(kick(reason: 'connectivity'));
    });
    unawaited(kick(reason: 'start'));
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(kick(reason: 'resume'));
    }
  }

  Future<void> kick({String reason = 'manual'}) async {
    if (_running) return;
    final last = _lastRunAt;
    if (last != null &&
        DateTime.now().difference(last) < _minGapBetweenRuns &&
        reason != 'manual') {
      return;
    }
    if (!await deviceHasNetworkForWhatsappNotify()) return;

    _running = true;
    _lastRunAt = DateTime.now();
    try {
      final outbox = OilChangeWhatsappOutbox.instance;
      // دفعات متتالية — حتى 3 جولات × 40 لتجنّب ترك باقي الطابور بلا معالجة.
      var totalSent = 0;
      for (var batch = 0; batch < 3; batch++) {
        final pending = await outbox.loadPending(limit: 40, onlyDue: true);
        final queue = pending.where((e) {
          if (!OilChangeWhatsappOutbox.isAutoRetryableReason(e.reason)) {
            return false;
          }
          if (e.attempts >= OilChangeWhatsappOutbox.maxAutoRetryAttempts) {
            return false;
          }
          return true;
        }).toList();
        if (queue.isEmpty) break;

        final proofs =
            await OilChangeWhatsappDeliveryReconcile.loadProofKeys();

        AppLogger.info(
          'wa_outbox_auto',
          'retry batch=$batch count=${queue.length} (reason=$reason)',
        );

        for (final entry in queue) {
          if (!await deviceHasNetworkForWhatsappNotify()) {
            return;
          }
          final proofKey = whatsappDeliveryProofKey(
            orderRef: '${entry.orderId}',
            phone: entry.customerPhone,
          );
          if (proofKey != null && proofs.contains(proofKey)) {
            await outbox.discard(entry.id);
            AppLogger.info(
              'wa_outbox_auto',
              'skip send; already logged order=${entry.orderId}',
            );
            continue;
          }
          final result = await outbox.retry(entry);
          if (result == OilChangeWhatsappNotifyReason.sent) {
            totalSent++;
            AppLogger.info(
              'wa_outbox_auto',
              'sent outbox id=${entry.id} order=${entry.orderId}',
            );
          }
          await Future<void>.delayed(_gapBetweenMessages);
        }
      }
      if (totalSent > 0) {
        AppLogger.info('wa_outbox_auto', 'done sent=$totalSent');
      }
    } catch (e, st) {
      AppLogger.warn('wa_outbox_auto', 'kick failed: $e\n$st');
    } finally {
      _running = false;
    }
  }
}
