import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';
import '../utils/whatsapp_failure_reason_ar.dart';

/// حالة الرسالة كما يعيدها واتساب — الترتيب هنا هو ترتيب التقدّم.
enum OilChangeMessageStatus { failed, sent, delivered, read, unknown }

extension OilChangeMessageStatusLabel on OilChangeMessageStatus {
  String get labelAr {
    switch (this) {
      case OilChangeMessageStatus.failed:
        return 'لم يتم الإرسال';
      case OilChangeMessageStatus.sent:
        return 'أُرسلت إلى Meta';
      case OilChangeMessageStatus.delivered:
        return 'وصلت للزبون';
      case OilChangeMessageStatus.read:
        return 'قرأها الزبون';
      case OilChangeMessageStatus.unknown:
        return 'غير معروفة';
    }
  }

  bool get isFailure => this == OilChangeMessageStatus.failed;

  /// وصلت فعلاً لجهاز الزبون — لا حاجة لإعادة الإرسال.
  bool get reachedCustomer =>
      this == OilChangeMessageStatus.delivered ||
      this == OilChangeMessageStatus.read;
}

/// دلو تحميل السحابة للتبويبين الجديدين.
enum OilChangeMessagesBucket { sent, notSent }

/// سطر واحد من سجل رسائل واتساب الصادرة.
class OilChangeMessageLogEntry {
  const OilChangeMessageLogEntry({
    required this.id,
    required this.createdAt,
    required this.status,
    required this.toPhone,
    this.templateKey = '',
    this.employeeName = '',
    this.orderRef = '',
    this.body = '',
    this.error = '',
    this.cardPayload = const {},
    this.idempotencyKey = '',
  });

  factory OilChangeMessageLogEntry.fromMap(Map<String, dynamic> map) {
    final payload = map['card_payload'];
    return OilChangeMessageLogEntry(
      id: (map['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['created_at'] ?? '').toString())?.toLocal() ??
              DateTime.now(),
      status: _parseStatus((map['status'] ?? '').toString()),
      toPhone: (map['to_phone'] ?? '').toString(),
      templateKey: (map['template_key'] ?? '').toString(),
      employeeName: (map['employee_name'] ?? '').toString(),
      orderRef: (map['order_ref'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
      error: (map['error'] ?? '').toString(),
      cardPayload: payload is Map
          ? payload.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()))
          : const {},
      idempotencyKey: (map['idempotency_key'] ?? '').toString(),
    );
  }

  final String id;
  final DateTime createdAt;
  final OilChangeMessageStatus status;
  final String toPhone;
  final String templateKey;
  final String employeeName;
  final String orderRef;
  final String body;
  final String error;
  final Map<String, String> cardPayload;
  final String idempotencyKey;

  bool get isOilChangeCard => templateKey == 'oil_change_card';

  bool get isAutoReply => templateKey == 'rating_auto_reply';

  String get customerName =>
      (cardPayload['customer'] ?? '').trim().isNotEmpty
          ? cardPayload['customer']!.trim()
          : '';

  /// بلا نص ولا حقول بطاقة لا يمكن إعادة تركيب الرسالة.
  bool get canResend => body.trim().isNotEmpty || cardPayload.isNotEmpty;

  static OilChangeMessageStatus _parseStatus(String raw) {
    switch (raw.toLowerCase()) {
      case 'failed':
        return OilChangeMessageStatus.failed;
      case 'sent':
        return OilChangeMessageStatus.sent;
      case 'delivered':
        return OilChangeMessageStatus.delivered;
      case 'read':
        return OilChangeMessageStatus.read;
      default:
        return OilChangeMessageStatus.unknown;
    }
  }
}

/// قراءة سجل رسائل واتساب وإعادة إرسال ما لم يصل — RLS تحصر النتائج
/// على حساب المحل الحالي.
class OilChangeWhatsappMessagesRepository {
  OilChangeWhatsappMessagesRepository._();

  static final OilChangeWhatsappMessagesRepository instance =
      OilChangeWhatsappMessagesRepository._();

  static const pageSize = 30;

  bool get isSignedIn => Supabase.instance.client.auth.currentUser != null;

  /// صفحة مرتبة بالأحدث؛ [beforeCreatedAt] مؤشّر الصفحة التالية.
  ///
  /// [bucket] يحدّد تبويب تم الإرسال / لم يتم الإرسال.
  Future<List<OilChangeMessageLogEntry>> loadPage({
    DateTime? beforeCreatedAt,
    OilChangeMessagesBucket bucket = OilChangeMessagesBucket.sent,
    @Deprecated('Use bucket') bool failedOnly = false,
    @Deprecated('Removed from UI') bool cardsOnly = false,
  }) async {
    if (!isSignedIn) return const [];
    try {
      var query = Supabase.instance.client
          .from('whatsapp_message_logs')
          .select(
            'id, created_at, status, to_phone, template_key, employee_name, '
            'order_ref, body, error, card_payload, idempotency_key',
          );

      final useFailed = failedOnly || bucket == OilChangeMessagesBucket.notSent;
      if (useFailed) {
        query = query.eq('status', 'failed');
      } else {
        query = query.inFilter('status', ['sent', 'delivered', 'read']);
      }
      if (cardsOnly) query = query.eq('template_key', 'oil_change_card');
      if (beforeCreatedAt != null) {
        query = query.lt('created_at', beforeCreatedAt.toUtc().toIso8601String());
      }

      final rows =
          await query.order('created_at', ascending: false).limit(pageSize);

      return (rows as List)
          .map((r) =>
              OilChangeMessageLogEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.warn('oil_change_wa_logs', 'page load failed :: $e');
      rethrow;
    }
  }

  /// حالة رسالة التجربة. null إذا لم يظهر سجلها بعد أو تعذرت القراءة.
  Future<({String status, String error})?> statusByKey(String key) async {
    if (!isSignedIn) return null;
    try {
      final row = await Supabase.instance.client
          .from('whatsapp_message_logs')
          .select('status, error')
          .eq('idempotency_key', key)
          .maybeSingle();
      if (row == null) return null;
      return (
        status: (row['status'] ?? '').toString(),
        error: (row['error'] ?? '').toString(),
      );
    } catch (e) {
      AppLogger.warn('oil_change_wa_logs', 'statusByKey failed :: $e');
      return null;
    }
  }

  /// أثر كل رسالة فاشلة على الرصيد. خطأ القراءة لا يوقف القائمة، ويغيب السطر فقط.
  Future<Map<String, WhatsappWalletEffect>> loadWalletEffects(
    List<OilChangeMessageLogEntry> entries,
  ) async {
    if (!isSignedIn) return const {};
    final withKey = entries.where((e) => e.idempotencyKey.isNotEmpty).toList();
    final effects = <String, WhatsappWalletEffect>{};
    try {
      // عائلة المفتاح: K وK#2 للخصم، وK#r1 وK#r2 للإعادة.
      const chunk = 15;
      for (var i = 0; i < withKey.length; i += chunk) {
        final part = withKey.skip(i).take(chunk).toList();
        final keys = <String>[
          for (final e in part) ...[
            e.idempotencyKey,
            '${e.idempotencyKey}#2',
            '${e.idempotencyKey}#r1',
            '${e.idempotencyKey}#r2',
          ],
        ];
        final rows = await Supabase.instance.client
            .from('wa_message_ledger')
            .select('idempotency_key, reason, created_at')
            .inFilter('idempotency_key', keys);
        final grouped = groupWalletEffects(
          (rows as List).cast<Map<String, dynamic>>(),
        );
        for (final e in part) {
          final effect = grouped[e.idempotencyKey];
          if (effect != null) effects[e.id] = effect;
        }
      }
    } catch (e) {
      AppLogger.warn('oil_change_wa_logs', 'wallet effects failed :: $e');
    }
    return effects;
  }

  /// يجمع قيود الدفتر حسب المفتاح الأصلي قبل اللاحقة.
  @visibleForTesting
  static Map<String, WhatsappWalletEffect> groupWalletEffects(
    List<Map<String, dynamic>> rows,
  ) {
    final sends = <String, int>{};
    final refunds = <String, int>{};
    final last = <String, DateTime>{};
    final suffix = RegExp(r'#r?[0-9]+$');
    for (final row in rows) {
      final base =
          (row['idempotency_key'] ?? '').toString().replaceFirst(suffix, '');
      final reason = (row['reason'] ?? '').toString();
      if (reason == 'send') {
        sends[base] = (sends[base] ?? 0) + 1;
        final at = DateTime.tryParse((row['created_at'] ?? '').toString());
        final seen = last[base];
        if (at != null && (seen == null || at.isAfter(seen))) last[base] = at;
      } else if (reason == 'refund_failed_send') {
        refunds[base] = (refunds[base] ?? 0) + 1;
      }
    }
    return {
      for (final base in {...sends.keys, ...refunds.keys})
        base: WhatsappWalletEffect(
          sends: sends[base] ?? 0,
          refunds: refunds[base] ?? 0,
          lastDebitAt: last[base],
        ),
    };
  }

  /// عدد سجلات السحابة بحالة failed (لم يتم الإرسال).
  Future<int> countFailed() async {
    if (!isSignedIn) return 0;
    try {
      return await Supabase.instance.client
          .from('whatsapp_message_logs')
          .count()
          .eq('status', 'failed');
    } catch (e) {
      AppLogger.warn('oil_change_wa_logs', 'countFailed failed :: $e');
      return 0;
    }
  }

  /// إثباتات وصول حديثة لمطابقة التوأم الفاشل. قراءة فقط.
  Future<List<OilChangeMessageLogEntry>> loadRecentDeliveryProofs({
    int limit = 200,
  }) async {
    if (!isSignedIn) return const [];
    final rows = await Supabase.instance.client
        .from('whatsapp_message_logs')
        .select('id, created_at, status, to_phone, order_ref')
        .inFilter('status', ['sent', 'delivered', 'read'])
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => OilChangeMessageLogEntry.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// إحصاء رسائل الفترة للمساعد — بدون أسعار.
  Future<OilChangeWhatsappMessageStats> countStats({
    required DateTime fromInclusive,
    required DateTime toExclusive,
  }) async {
    if (!isSignedIn) {
      return const OilChangeWhatsappMessageStats.empty();
    }
    final fromIso = fromInclusive.toUtc().toIso8601String();
    final toIso = toExclusive.toUtc().toIso8601String();
    final client = Supabase.instance.client;

    Future<int> countWhere({String? status}) async {
      var q = client.from('whatsapp_message_logs').count().gte(
            'created_at',
            fromIso,
          ).lt('created_at', toIso);
      if (status != null) {
        q = q.eq('status', status);
      }
      return await q;
    }

    try {
      final total = await countWhere();
      final failed = await countWhere(status: 'failed');
      final sent = await countWhere(status: 'sent');
      final delivered = await countWhere(status: 'delivered');
      final read = await countWhere(status: 'read');
      return OilChangeWhatsappMessageStats(
        total: total,
        failed: failed,
        sent: sent,
        deliveredOrRead: delivered + read,
        other: (total - failed - sent - delivered - read).clamp(0, total),
      );
    } catch (e) {
      AppLogger.warn('oil_change_wa_logs', 'countStats failed :: $e');
      rethrow;
    }
  }
}

class OilChangeWhatsappMessageStats {
  const OilChangeWhatsappMessageStats({
    required this.total,
    required this.failed,
    required this.sent,
    required this.deliveredOrRead,
    required this.other,
  });

  const OilChangeWhatsappMessageStats.empty()
      : total = 0,
        failed = 0,
        sent = 0,
        deliveredOrRead = 0,
        other = 0;

  final int total;
  final int failed;
  final int sent;
  final int deliveredOrRead;
  final int other;
}
