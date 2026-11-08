import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';

/// سطر في مطالبة الاسترجاع: مفتاح السطر الأصلي، الكمية المرتجعة، والمباع.
class ReturnClaimLine {
  const ReturnClaimLine({
    required this.key,
    required this.qty,
    required this.sold,
  });

  final String key;
  final double qty;
  final double sold;

  Map<String, dynamic> toJson() => {'key': key, 'qty': qty, 'sold': sold};
}

enum ReturnClaimStatus { ok, offline, exceeds, notReady, failed }

class ReturnClaimResult {
  const ReturnClaimResult(
    this.status, {
    this.lineKey,
    this.remaining,
    this.message,
  });

  final ReturnClaimStatus status;
  final String? lineKey;
  final double? remaining;
  final String? message;

  bool get ok => status == ReturnClaimStatus.ok;
}

/// مطالبة الخادم قبل حفظ المرتجع: تمنع استرجاع المادة نفسها مرتين من جهازين.
/// بلا إنترنت تعيد [ReturnClaimStatus.offline] — والاسترجاع يُمنع.
abstract final class ReturnClaimService {
  /// للاختبارات: استبدال الاستدعاء.
  static Future<Object?> Function(String fn, Map<String, dynamic> params) rpc =
      (fn, params) => Supabase.instance.client
          .rpc(fn, params: params)
          .timeout(const Duration(seconds: 15));

  static bool Function() isSignedIn = () =>
      Supabase.instance.client.auth.currentUser != null;

  static Future<ReturnClaimResult> claim({
    required String originalGlobalId,
    required String returnGlobalId,
    required List<ReturnClaimLine> lines,
    required double amount,
    required String actor,
  }) async {
    if (!isSignedIn())
      return const ReturnClaimResult(ReturnClaimStatus.offline);
    try {
      final res = await rpc('rpc_claim_invoice_return', {
        'p_original': originalGlobalId,
        'p_return': returnGlobalId,
        'p_lines': [for (final l in lines) l.toJson()],
        'p_amount': amount,
        'p_actor': actor,
      });
      final m = res is Map
          ? res
          : (res is List && res.isNotEmpty ? res.first : null);
      if (m is! Map) {
        return const ReturnClaimResult(
          ReturnClaimStatus.failed,
          message: 'رد غير متوقع من الخادم',
        );
      }
      if (m['ok'] == true) return const ReturnClaimResult(ReturnClaimStatus.ok);
      if (m['reason'] == 'exceeds_sold') {
        return ReturnClaimResult(
          ReturnClaimStatus.exceeds,
          lineKey: m['key']?.toString(),
          remaining: (m['remaining'] as num?)?.toDouble(),
        );
      }
      return ReturnClaimResult(
        ReturnClaimStatus.failed,
        message: 'رفض الخادم الطلب (${m['reason']})',
      );
    } on PostgrestException catch (e) {
      AppLogger.warn('ReturnClaimService', 'claim: ${e.code} ${e.message}');
      // الدالة غير موجودة بعد على الخادم.
      if (e.code == 'PGRST202' || e.code == '42883') {
        return const ReturnClaimResult(ReturnClaimStatus.notReady);
      }
      return ReturnClaimResult(ReturnClaimStatus.failed, message: e.message);
    } catch (e) {
      // انقطاع، مهلة، DNS… = لا إنترنت.
      AppLogger.warn('ReturnClaimService', 'claim offline: $e');
      return const ReturnClaimResult(ReturnClaimStatus.offline);
    }
  }

  /// يلغي مطالبة لم يكتمل حفظها محلياً. أفضل جهد: لا يرمي.
  static Future<void> voidClaim(String returnGlobalId) async {
    try {
      await rpc('rpc_void_return_claim', {'p_return': returnGlobalId});
    } catch (e) {
      AppLogger.warn('ReturnClaimService', 'void failed: $e');
    }
  }
}
