import 'package:sqflite/sqflite.dart';

/// البند 4.3: البطاقة المدفوعة تُقفل بعد إغلاق ورديتها.
///
/// تعديل البطاقة المفوترة أو إبطالها يغيّر الفاتورة وقيد الصندوق الأصليين،
/// فيتغير رقم وردية سُلّم صندوقها. ما دامت الوردية مفتوحة يبقى ذلك مسموحاً.
/// بعد إغلاقها يكون التصحيح بمرتجع ثم بطاقة جديدة، فيظهر في وردية اليوم.
class PaidCardLock {
  static const message =
      'وردية هذه البطاقة أُغلقت وسُلّم صندوقها، فلا يمكن تعديلها أو إبطالها. '
      'للتصحيح: اعمل مرتجعاً لفاتورتها من شاشة المرتجعات، ثم بطاقة جديدة.';

  /// هل وردية الفاتورة مغلقة؟ فاتورة بلا وردية لا تُقفل.
  ///
  /// تُعرف الوردية أولاً من قيد الصندوق بمعرفها العام، لأنه يبقى صحيحاً على
  /// كل جهاز، ثم من رقم الوردية المحلي في الفاتورة.
  static Future<bool> isLocked(DatabaseExecutor db, int invoiceId) async {
    if (invoiceId <= 0) return false;
    final cash = await db.rawQuery('''
      SELECT ws.closedAt FROM cash_ledger c
      JOIN work_shifts ws ON ws.global_id = c.work_shift_global_id
      WHERE c.invoiceId = ? AND c.deleted_at IS NULL
        AND c.work_shift_global_id IS NOT NULL
        AND TRIM(c.work_shift_global_id) <> ''
      LIMIT 1
    ''', [invoiceId]);
    if (cash.isNotEmpty) return _closed(cash.first['closedAt']);
    final inv = await db.rawQuery('''
      SELECT ws.closedAt FROM invoices i
      JOIN work_shifts ws ON ws.id = i.workShiftId
      WHERE i.id = ?
      LIMIT 1
    ''', [invoiceId]);
    if (inv.isNotEmpty) return _closed(inv.first['closedAt']);
    return false;
  }

  static bool _closed(Object? closedAt) =>
      closedAt != null && closedAt.toString().trim().isNotEmpty;
}
