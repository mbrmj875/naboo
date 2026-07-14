/// تعابير SQL مشتركة لحساب المبالغ بـ fils داخل SQLite.
///
/// تُستخدم في الاستعلامات التجميعية لتفضيل الأعمدة الصحيحة (`*Fils`)
/// مع fallback آمن للسجلات القديمة (`ROUND(* * 1000)`).
abstract final class MoneySql {
  MoneySql._();

  /// إجمالي الفاتورة بالفلس (بدون alias).
  static const invoiceTotalFils = '''
    CASE
      WHEN IFNULL(totalFils, 0) != 0 THEN IFNULL(totalFils, 0)
      ELSE ROUND(IFNULL(total, 0) * 1000)
    END
  ''';

  /// المتبقي المفتوح للفاتورة الآجلة بالفلس (بدون alias).
  static const invoiceOpenRemainingFils = '''
    CASE
      WHEN IFNULL(totalFils, 0) != 0 OR IFNULL(advancePaymentFils, 0) != 0
        THEN MAX(0, IFNULL(totalFils, 0) - IFNULL(advancePaymentFils, 0))
      ELSE MAX(0, ROUND(IFNULL(total, 0) * 1000) - ROUND(IFNULL(advancePayment, 0) * 1000))
    END
  ''';

  /// مبلغ المصروف/قيد الصندوق بالفلس (بدون alias).
  static const expenseAmountFils = '''
    CASE
      WHEN IFNULL(amountFils, 0) != 0 THEN IFNULL(amountFils, 0)
      ELSE ROUND(IFNULL(amount, 0) * 1000)
    END
  ''';

  /// إجمالي الفاتورة بالفلس مع alias جدول (مثل `i`).
  static String invoiceTotalFilsOf(String alias) => '''
    CASE
      WHEN IFNULL($alias.totalFils, 0) != 0 THEN IFNULL($alias.totalFils, 0)
      ELSE ROUND(IFNULL($alias.total, 0) * 1000)
    END
  ''';

  /// المتبقي المفتوح بالفلس مع alias جدول (مثل `i`).
  static String invoiceOpenRemainingFilsOf(String alias) => '''
    CASE
      WHEN IFNULL($alias.totalFils, 0) != 0 OR IFNULL($alias.advancePaymentFils, 0) != 0
        THEN MAX(0, IFNULL($alias.totalFils, 0) - IFNULL($alias.advancePaymentFils, 0))
      ELSE MAX(0, ROUND(IFNULL($alias.total, 0) * 1000) - ROUND(IFNULL($alias.advancePayment, 0) * 1000))
    END
  ''';

  /// الدفعة المقدمة بالفلس مع alias جدول (مثل `i`).
  static String invoiceAdvancePaymentFilsOf(String alias) => '''
    CASE
      WHEN IFNULL($alias.advancePaymentFils, 0) != 0
        THEN IFNULL($alias.advancePaymentFils, 0)
      ELSE ROUND(IFNULL($alias.advancePayment, 0) * 1000)
    END
  ''';

  /// إجمالي بند الفاتورة بالفلس مع alias جدول (مثل `ii`).
  static String invoiceItemTotalFilsOf(String alias) => '''
    CASE
      WHEN IFNULL($alias.totalFils, 0) != 0
        THEN IFNULL($alias.totalFils, 0)
      ELSE ROUND(IFNULL($alias.total, 0) * 1000)
    END
  ''';
}
