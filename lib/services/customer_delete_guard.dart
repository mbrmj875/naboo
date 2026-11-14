// PR-2 (roadmap_phase2_execution_v1 §4) — منع حذف العميل بديون مفتوحة.
//
// السياسة:
//   • فاتورة credit أو installment مفتوحة (advancePayment < total) ⇒ يمنع.
//   • خطة تقسيط نشطة (paidAmount < totalAmount) ⇒ يمنع.
//   • فاتورة isReturned=1 أو deleted_at IS NOT NULL ⇒ لا تمنع.
//   • فاتورة cash لا تُحتسب (لا دين).
//
// الـ helper مستقل عن DatabaseHelper ليكون قابلاً للاختبار بـ in-memory DB.

import 'package:sqflite/sqflite.dart';

/// قيم InvoiceType.credit.index و InvoiceType.installment.index.
/// مكرّرة هنا لتجنب الاعتماد الدوري مع enum invoice.dart.
const int _kInvoiceTypeCredit = 1;
const int _kInvoiceTypeInstallment = 2;

/// عقبة واحدة تمنع حذف عميل — تفاصيل ديونه المفتوحة.
class CustomerDeleteObstacle {
  const CustomerDeleteObstacle({
    required this.customerId,
    required this.customerName,
    required this.openInvoiceCount,
    required this.outstandingFils,
    required this.openInstallmentPlanCount,
    required this.outstandingInstallmentFils,
  });

  final int customerId;
  final String customerName;

  /// عدد الفواتير المفتوحة (credit/installment، غير مرتجعة، غير محذوفة، رصيدها > 0).
  final int openInvoiceCount;

  /// مجموع المتبقي على هذه الفواتير بالفلس.
  final int outstandingFils;

  /// عدد خطط التقسيط النشطة (paidAmount < totalAmount).
  final int openInstallmentPlanCount;

  /// مجموع المتبقي على خطط التقسيط بالفلس (تحويل من REAL).
  final int outstandingInstallmentFils;

  bool get hasObstacles =>
      openInvoiceCount > 0 || openInstallmentPlanCount > 0;
}

/// يُرفع عند رفض حذف عميل لوجود ديون مفتوحة.
/// رسالته بالعربية وتذكر الأسماء والأعداد ليظهرها UI مباشرة.
class CustomerDeleteBlockedException implements Exception {
  CustomerDeleteBlockedException(this.obstacles);

  final List<CustomerDeleteObstacle> obstacles;

  @override
  String toString() {
    if (obstacles.isEmpty) {
      return 'CustomerDeleteBlockedException: لا توجد عقبات (حالة غير متوقعة)';
    }
    final lines = <String>[
      'تعذر حذف العميل: توجد التزامات مالية مفتوحة.',
    ];
    for (final o in obstacles) {
      final parts = <String>[];
      if (o.openInvoiceCount > 0) {
        parts.add('${o.openInvoiceCount} فاتورة مفتوحة');
      }
      if (o.openInstallmentPlanCount > 0) {
        parts.add('${o.openInstallmentPlanCount} خطة تقسيط نشطة');
      }
      lines.add('• ${o.customerName}: ${parts.join(' + ')}.');
    }
    lines.add('سدّد الفواتير/الأقساط أو امسحها قبل حذف العميل.');
    return lines.join('\n');
  }
}

/// يقرأ التزامات عميل واحد ويرجع [CustomerDeleteObstacle] دائماً
/// (حتى لو ليست له عقبات — للحالات التي يريد المستدعي إحصاءها).
///
/// يستخدم أعمدة `*Fils` إن وُجدت ويسقط للقيم العشرية كاحتياط للبيانات القديمة.
Future<CustomerDeleteObstacle> inspectCustomerObligations(
  DatabaseExecutor exec, {
  required int customerId,
  int? tenantId,
}) async {
  // 1) اسم العميل (للرسالة).
  final customerRow = await exec.query(
    'customers',
    columns: ['name'],
    where: tenantId == null
        ? 'id = ?'
        : 'id = ? AND tenantId = ?',
    whereArgs: tenantId == null ? [customerId] : [customerId, tenantId],
    limit: 1,
  );
  final name = customerRow.isEmpty
      ? '#$customerId'
      : (customerRow.first['name'] as String?)?.trim().isNotEmpty == true
          ? customerRow.first['name'] as String
          : '#$customerId';

  // 2) فواتير credit/installment مفتوحة.
  // نستخدم COALESCE(totalFils, total*1000) للتوافق مع البيانات القديمة.
  final invWhere = StringBuffer()
    ..write('customerId = ? ')
    ..write('AND type IN (?, ?) ')
    ..write('AND IFNULL(isReturned, 0) = 0 ')
    ..write('AND deleted_at IS NULL ')
    ..write(
      'AND (CAST(COALESCE(totalFils, total * 1000) AS INTEGER) - '
      'CAST(COALESCE(advancePaymentFils, advancePayment * 1000) AS INTEGER)) > 0',
    );
  final invArgs = <Object?>[
    customerId,
    _kInvoiceTypeCredit,
    _kInvoiceTypeInstallment,
  ];
  if (tenantId != null) {
    invWhere.write(' AND tenantId = ?');
    invArgs.add(tenantId);
  }
  final invRows = await exec.rawQuery(
    'SELECT COUNT(*) AS c, '
    'SUM(CAST(COALESCE(totalFils, total * 1000) AS INTEGER) - '
    '    CAST(COALESCE(advancePaymentFils, advancePayment * 1000) AS INTEGER)) AS rem '
    'FROM invoices WHERE $invWhere',
    invArgs,
  );
  final invCount = (invRows.first['c'] as num?)?.toInt() ?? 0;
  final invRem = (invRows.first['rem'] as num?)?.toInt() ?? 0;

  // 3) خطط تقسيط نشطة.
  int planCount = 0;
  int planRem = 0;
  // الجدول قد لا يكون موجوداً في كل اختبار — نتحقق أولاً.
  final tableExists = await _tableExists(exec, 'installment_plans');
  if (tableExists) {
    final planWhere = StringBuffer()
      ..write('customerId = ? ')
      ..write('AND IFNULL(paidAmount, 0) < IFNULL(totalAmount, 0)');
    final planArgs = <Object?>[customerId];
    if (tenantId != null &&
        await _columnExists(exec, 'installment_plans', 'tenantId')) {
      planWhere.write(' AND tenantId = ?');
      planArgs.add(tenantId);
    }
    final planRows = await exec.rawQuery(
      'SELECT COUNT(*) AS c, '
      'SUM((IFNULL(totalAmount, 0) - IFNULL(paidAmount, 0)) * 1000) AS rem '
      'FROM installment_plans WHERE $planWhere',
      planArgs,
    );
    planCount = (planRows.first['c'] as num?)?.toInt() ?? 0;
    planRem = (planRows.first['rem'] as num?)?.toInt() ?? 0;
  }

  return CustomerDeleteObstacle(
    customerId: customerId,
    customerName: name,
    openInvoiceCount: invCount,
    outstandingFils: invRem,
    openInstallmentPlanCount: planCount,
    outstandingInstallmentFils: planRem,
  );
}

/// يفحص قائمة من العملاء ويرمي [CustomerDeleteBlockedException]
/// إذا كان أي منهم لديه التزامات مفتوحة.
///
/// مرّر [tenantId] لقصر الفحص على مستأجر محدد (يُفضّل دائماً).
Future<void> assertCustomersHaveNoOpenObligations(
  DatabaseExecutor exec,
  List<int> customerIds, {
  int? tenantId,
}) async {
  if (customerIds.isEmpty) return;
  final obstacles = <CustomerDeleteObstacle>[];
  for (final id in customerIds) {
    final o = await inspectCustomerObligations(
      exec,
      customerId: id,
      tenantId: tenantId,
    );
    if (o.hasObstacles) obstacles.add(o);
  }
  if (obstacles.isNotEmpty) {
    throw CustomerDeleteBlockedException(obstacles);
  }
}

Future<bool> _tableExists(DatabaseExecutor exec, String name) async {
  final rows = await exec.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
    [name],
  );
  return rows.isNotEmpty;
}

Future<bool> _columnExists(
  DatabaseExecutor exec,
  String table,
  String col,
) async {
  final rows = await exec.rawQuery('PRAGMA table_info($table)');
  return rows.any(
    (r) => (r['name']?.toString().toLowerCase() ?? '') == col.toLowerCase(),
  );
}
