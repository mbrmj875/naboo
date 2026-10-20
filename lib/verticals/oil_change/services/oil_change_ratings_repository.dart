import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';
import '../models/oil_change_rating.dart';

/// قراءة تقييمات العملاء — RLS تحصر النتائج على حساب المحل الحالي.
class OilChangeRatingsRepository {
  OilChangeRatingsRepository._();

  static final OilChangeRatingsRepository instance =
      OilChangeRatingsRepository._();

  static const pageSize = 30;

  bool get isSignedIn => Supabase.instance.client.auth.currentUser != null;

  Future<List<OilChangeEmployeeRatingSummary>> loadEmployeeSummary() async {
    if (!isSignedIn) return const [];
    try {
      final rows = await Supabase.instance.client
          .from('oil_change_employee_rating_summary')
          .select()
          .order('ratings_count', ascending: false);
      return (rows as List)
          .map((r) =>
              OilChangeEmployeeRatingSummary.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.warn('oil_change_ratings', 'summary load failed :: $e');
      rethrow;
    }
  }

  /// صفحة من التقييمات مرتبة بالأحدث؛ [beforeCreatedAt] هو مؤشّر الصفحة.
  ///
  /// [unassignedOnly] يجلب الردود التي لم تُسنَد لأي فني.
  Future<List<OilChangeRatingEntry>> loadEntries({
    String? employeeName,
    DateTime? beforeCreatedAt,
    bool unassignedOnly = false,
  }) async {
    if (!isSignedIn) return const [];
    try {
      var query = Supabase.instance.client
          .from('oil_change_service_ratings')
          .select(
            'id, customer_phone, created_at, employee_name, order_ref, '
            'score, note, source',
          )
          .filter('deleted_at', 'is', null);

      if (unassignedOnly) {
        query = query.or('employee_name.is.null,employee_name.eq.');
      } else if (employeeName != null && employeeName.trim().isNotEmpty) {
        query = query.eq('employee_name', employeeName.trim());
      }
      if (beforeCreatedAt != null) {
        query = query.lt('created_at', beforeCreatedAt.toIso8601String());
      }

      final rows = await query
          .order('created_at', ascending: false)
          .limit(pageSize);

      return (rows as List)
          .map((r) => OilChangeRatingEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.warn('oil_change_ratings', 'entries load failed :: $e');
      rethrow;
    }
  }
}
