import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../services/connectivity_resume_sync.dart';
import '../models/oil_change_whatsapp_notify_outcome.dart';

OilChangeWhatsappNotifyOutcome classifyWhatsappWebhookResponse({
  required int statusCode,
  required String body,
}) {
  Map<String, dynamic>? json;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      json = decoded;
    }
  } catch (_) {}

  if (statusCode == 401 || statusCode == 403) {
    return OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.unauthorized,
      httpStatus: statusCode,
    );
  }
  if (statusCode == 429) {
    return OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.rateLimited,
      httpStatus: statusCode,
    );
  }
  if (statusCode >= 500) {
    return OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.serverError,
      httpStatus: statusCode,
    );
  }

  if (json != null) {
    final okRaw = json['ok'];
    if (_looksLikeBrokenN8nExpression(okRaw) ||
        _looksLikeBrokenN8nExpression(json['reason'])) {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.serverError,
      );
    }

    if (okRaw == true || okRaw == 'true') {
      return const OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.sent,
      );
    }

    final reason = (json['reason'] ?? json['error'] ?? '').toString().trim();
    final mapped = _mapServerReason(reason);
    if (mapped != null) {
      return OilChangeWhatsappNotifyOutcome(
        reason: mapped,
        httpStatus: statusCode,
      );
    }

    if (okRaw == false || okRaw == 'false') {
      return OilChangeWhatsappNotifyOutcome(
        reason: OilChangeWhatsappNotifyReason.unknown,
        httpStatus: statusCode,
      );
    }
  }

  // رد 200 بجسم فارغ أو غير JSON — غالباً رفض سر/workflow بدون JSON.
  // سابقاً كان يُصنَّف خطأً كـ «تم الإرسال» فيظهر نجاح وهمي.
  final trimmed = body.trim();
  if (statusCode >= 200 && statusCode < 300 && trimmed.isEmpty) {
    return OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.unauthorized,
      httpStatus: statusCode,
    );
  }

  return OilChangeWhatsappNotifyOutcome(
    reason: OilChangeWhatsappNotifyReason.unknown,
    httpStatus: statusCode,
  );
}

OilChangeWhatsappNotifyReason? _mapServerReason(String reason) {
  final r = reason.toLowerCase();
  if (r.isEmpty) return null;
  if (r.contains('disconnect') ||
      r.contains('not_connected') ||
      r.contains('session') ||
      r == 'whatsapp_disconnected') {
    return OilChangeWhatsappNotifyReason.whatsappDisconnected;
  }
  if (r.contains('rate') || r.contains('limit')) {
    return OilChangeWhatsappNotifyReason.rateLimited;
  }
  if (r.contains('unauthorized') || r.contains('secret')) {
    return OilChangeWhatsappNotifyReason.unauthorized;
  }
  if (r.contains('same_as_shop') || r.contains('sameasshop')) {
    return OilChangeWhatsappNotifyReason.sameAsShopPhone;
  }
  if (r.contains('evolution') || r.contains('instance')) {
    return OilChangeWhatsappNotifyReason.evolutionError;
  }
  if (r.contains('phone') || r.contains('number')) {
    return OilChangeWhatsappNotifyReason.invalidPhone;
  }
  return null;
}

bool _looksLikeBrokenN8nExpression(Object? value) {
  if (value is! String) return false;
  return value.contains('={{') || value.contains(r'$json');
}

OilChangeWhatsappNotifyOutcome classifyWhatsappNotifyException(Object error) {
  if (error is TimeoutException) {
    return const OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.timeout,
    );
  }
  if (error is SocketException) {
    return const OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.noInternet,
    );
  }
  final text = error.toString().toLowerCase();
  if (text.contains('timeout') || text.contains('timed out')) {
    return const OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.timeout,
    );
  }
  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused')) {
    return const OilChangeWhatsappNotifyOutcome(
      reason: OilChangeWhatsappNotifyReason.noInternet,
    );
  }
  return const OilChangeWhatsappNotifyOutcome(
    reason: OilChangeWhatsappNotifyReason.unknown,
  );
}

Future<bool> deviceHasNetworkForWhatsappNotify() async {
  final results = await Connectivity().checkConnectivity();
  return connectivityResultsOnline(results);
}
