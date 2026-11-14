import 'package:sqflite/sqflite.dart';

import '../services/database_helper.dart';
import '../utils/app_logger.dart';
import '../utils/iqd_money.dart';
import 'models/owner_kpi_models.dart';

/// ملخص الصندوق — نفس مصدر [CashScreen].
class OwnerFinanceRepository {
  OwnerFinanceRepository({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  Future<CashSummary> loadCashSummary({
    required int tenantId,
    String? staffName,
  }) async {
    final db = await _db.database;
    final int balanceFils;
    if (staffName == null || staffName.trim().isEmpty) {
      final sum = await _db.getCashSummary();
      balanceFils = IqdMoney.toFils(sum['balance'] ?? 0);
    } else {
      await _db.ensureCashLedgerIntegrityForSummary();
      balanceFils =
          await _sumStaffShiftBalanceFils(db, tenantId, staffName.trim());
    }

    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final nextDay = dayStart.add(const Duration(days: 1));
    final today = await _sumTodayCashFils(
      db,
      tenantId: tenantId,
      start: dayStart,
      endExclusive: nextDay,
      staffName: staffName,
    );

    return CashSummary(
      balanceFils: balanceFils,
      todayInFils: today.inFils,
      todayOutFils: today.outFils,
    );
  }

  static Future<int> _sumStaffShiftBalanceFils(
    Database db,
    int tenantId,
    String staffName,
  ) async {
    try {
      final rows = await db.rawQuery(
        '''
        SELECT COALESCE(SUM(
          CASE WHEN cl.amountFils != 0 THEN cl.amountFils ELSE ROUND(cl.amount * 1000) END
        ), 0) AS balanceFils
        FROM cash_ledger cl
        WHERE cl.tenantId = ?
          AND cl.deleted_at IS NULL
          AND (
            cl.workShiftId IN (
              SELECT ws.id FROM work_shifts ws
              WHERE ws.deleted_at IS NULL
                AND (
                  LOWER(TRIM(COALESCE(ws.shiftStaffName, ''))) = LOWER(?)
                  OR ws.shiftStaffUserId IN (
                    SELECT u.id FROM users u
                    WHERE LOWER(TRIM(COALESCE(u.displayName, u.username, ''))) = LOWER(?)
                  )
                )
            )
            OR cl.invoiceId IN (
              SELECT i.id FROM invoices i
              WHERE i.tenantId = ?
                AND i.deleted_at IS NULL
                AND TRIM(COALESCE(i.createdByUserName, '')) = ?
            )
          )
        ''',
        [tenantId, staffName, staffName, tenantId, staffName],
      );
      return (rows.first['balanceFils'] as num?)?.toInt() ?? 0;
    } catch (e, st) {
      AppLogger.error(
        'OwnerFinanceRepository',
        'تعذر حساب رصيد صندوق الموظف',
        e,
        st,
      );
      return 0;
    }
  }

  static Future<({int inFils, int outFils})> _sumTodayCashFils(
    Database db, {
    required int tenantId,
    required DateTime start,
    required DateTime endExclusive,
    String? staffName,
  }) async {
    try {
      final staffFilter = staffName != null && staffName.trim().isNotEmpty;
      final staff = staffFilter ? staffName.trim() : '';
      final rows = await db.rawQuery(
        '''
        SELECT
          COALESCE(SUM(CASE WHEN fils > 0 THEN fils ELSE 0 END), 0) AS inFils,
          COALESCE(SUM(CASE WHEN fils < 0 THEN -fils ELSE 0 END), 0) AS outFils
        FROM (
          SELECT CASE
            WHEN cl.amountFils != 0 THEN cl.amountFils
            ELSE ROUND(cl.amount * 1000)
          END AS fils
          FROM cash_ledger cl
          WHERE cl.tenantId = ?
            AND cl.deleted_at IS NULL
            AND cl.createdAt >= ?
            AND cl.createdAt < ?
            ${staffFilter ? '''
            AND (
              cl.workShiftId IN (
                SELECT ws.id FROM work_shifts ws
                WHERE ws.deleted_at IS NULL
                  AND (
                    LOWER(TRIM(COALESCE(ws.shiftStaffName, ''))) = LOWER(?)
                    OR ws.shiftStaffUserId IN (
                      SELECT u.id FROM users u
                      WHERE LOWER(TRIM(COALESCE(u.displayName, u.username, ''))) = LOWER(?)
                    )
                  )
              )
              OR cl.invoiceId IN (
                SELECT i.id FROM invoices i
                WHERE i.tenantId = ?
                  AND i.deleted_at IS NULL
                  AND TRIM(COALESCE(i.createdByUserName, '')) = ?
              )
            )
            ''' : ''}
        )
        ''',
        staffFilter
            ? [
                tenantId,
                start.toIso8601String(),
                endExclusive.toIso8601String(),
                staff,
                staff,
                tenantId,
                staff,
              ]
            : [
                tenantId,
                start.toIso8601String(),
                endExclusive.toIso8601String(),
              ],
      );
      final row = rows.first;
      return (
        inFils: (row['inFils'] as num?)?.toInt() ?? 0,
        outFils: (row['outFils'] as num?)?.toInt() ?? 0,
      );
    } catch (e, st) {
      AppLogger.error(
        'OwnerFinanceRepository',
        'تعذر حساب حركة الصندوق اليومية',
        e,
        st,
      );
      return (inFils: 0, outFils: 0);
    }
  }
}
