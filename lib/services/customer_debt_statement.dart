import 'package:intl/intl.dart';

import '../models/credit_debt_invoice.dart';
import '../printing/receipt_model.dart';
import '../utils/iqd_money.dart';

final _num = NumberFormat('#,##0', 'en');
/// dd/MM/yyyy بأرقام لاتينية، دون الحاجة لتهيئة بيانات اللغة.
final _day = _Day();

class _Day {
  String format(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _iqd(int fils) => '${_num.format(fils / 1000.0)} د.ع';

/// دفعة تسديد دين مسجّلة (صف من `customer_debt_payments`).
class CustomerDebtPaymentRow {
  const CustomerDebtPaymentRow({
    required this.id,
    required this.amountFils,
    required this.debtBeforeFils,
    required this.debtAfterFils,
    required this.createdAt,
    this.recordedBy,
    this.note,
    this.voidedAt,
    this.voidedBy,
    this.voidReason,
    this.hasAllocations = true,
  });

  final int id;
  final int amountFils;
  final int debtBeforeFils;
  final int debtAfterFils;
  final DateTime createdAt;
  final String? recordedBy;
  final String? note;

  /// إلغاء الدفعة (المرحلة 5 — الشريحة 3): تبقى ظاهرة «ملغاة» ولا تُحسب.
  final DateTime? voidedAt;
  final String? voidedBy;
  final String? voidReason;

  /// الدفعات القديمة (قبل حفظ التوزيع) لا يُعرف على أي فواتير وُزّعت.
  final bool hasAllocations;

  bool get isVoided => voidedAt != null;
  bool get canVoid => !isVoided && hasAllocations;

  factory CustomerDebtPaymentRow.fromRow(Map<String, Object?> r) {
    String? text(Object? v) {
      final s = (v ?? '').toString().trim();
      return s.isEmpty ? null : s;
    }

    return CustomerDebtPaymentRow(
      id: (r['id'] as num).toInt(),
      amountFils: IqdMoney.toFils((r['amount'] as num?)?.toDouble() ?? 0),
      debtBeforeFils: IqdMoney.toFils(
        (r['debtBefore'] as num?)?.toDouble() ?? 0,
      ),
      debtAfterFils: IqdMoney.toFils((r['debtAfter'] as num?)?.toDouble() ?? 0),
      createdAt:
          DateTime.tryParse((r['createdAt'] ?? '').toString())?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      recordedBy: text(r['createdByUserName']),
      note: text(r['note']),
      voidedAt: DateTime.tryParse((r['voidedAt'] ?? '').toString())?.toLocal(),
      voidedBy: text(r['voidedByUserName']),
      voidReason: text(r['voidReason']),
      hasAllocations: text(r['allocationsJson']) != null,
    );
  }
}

/// كشف حساب العميل: فواتيره المفتوحة (الإجمالي، المدفوع، الباقي) وآخر
/// دفعاته، والرصيد الآن. الأرقام من حالة الفواتير الحالية، فلا تقدير فيها.
class CustomerDebtStatement {
  CustomerDebtStatement({
    required this.customerName,
    required List<CreditDebtInvoice> invoices,
    required List<CustomerDebtPaymentRow> payments,
    this.maxPayments = 10,
    DateTime? now,
  }) : openInvoices =
           invoices.where((i) => i.remainingFils >= 500).toList()
             ..sort((a, b) => a.date.compareTo(b.date)),
       payments = payments
           .where((p) => !p.isVoided)
           .take(maxPayments)
           .toList(),
       date = now ?? DateTime.now();

  final String customerName;
  final List<CreditDebtInvoice> openInvoices;
  final List<CustomerDebtPaymentRow> payments;
  final int maxPayments;
  final DateTime date;

  int get balanceFils =>
      openInvoices.fold<int>(0, (s, i) => s + i.remainingFils);

  int get paymentsFils => payments.fold<int>(0, (s, p) => s + p.amountFils);

  static int _totalFils(CreditDebtInvoice i) =>
      i.totalFils ?? IqdMoney.toFils(i.total);

  /// نص الكشف للواتساب.
  String toWhatsAppText({String storeName = ''}) {
    final b = StringBuffer();
    final store = storeName.trim();
    b.writeln('كشف حساب${store.isEmpty ? '' : ' — $store'}');
    b.writeln('العميل: ${customerName.trim()}');
    b.writeln('التاريخ: ${_day.format(date)}');
    if (openInvoices.isEmpty) {
      b.writeln();
      b.writeln('لا يوجد دين مفتوح. شكراً لك.');
      return b.toString().trim();
    }
    b.writeln();
    b.writeln('الفواتير غير المسدَّدة:');
    for (final i in openInvoices) {
      final total = _totalFils(i);
      final paid = total - i.remainingFils;
      b.writeln(
        '• ${_day.format(i.date)} فاتورة #${i.invoiceId}: '
        '${_iqd(total)}'
        '${paid > 0 ? '، دُفع ${_iqd(paid)}' : ''}'
        '، الباقي ${_iqd(i.remainingFils)}',
      );
    }
    if (payments.isNotEmpty) {
      b.writeln();
      b.writeln('آخر الدفعات:');
      for (final p in payments) {
        b.writeln('• ${_day.format(p.createdAt)}: ${_iqd(p.amountFils)}');
      }
    }
    b.writeln();
    b.write('الرصيد المطلوب الآن: ${_iqd(balanceFils)}');
    return b.toString();
  }

  /// الكشف كإيصال قابل للطباعة بقالب «تسديد دين».
  ReceiptDocument toReceipt() => ReceiptDocument(
    kind: ReceiptKind.customerStatement,
    date: date,
    fields: [ReceiptField('العميل', customerName.trim(), bold: true)],
    lines: [
      for (final i in openInvoices)
        ReceiptLine(
          name: 'فاتورة #${i.invoiceId} · ${_day.format(i.date)}',
          totalFils: i.remainingFils,
        ),
    ],
    totals: [
      if (payments.isNotEmpty)
        ReceiptTotal('مجموع آخر ${payments.length} دفعات', paymentsFils),
      ReceiptTotal('الرصيد المطلوب الآن', balanceFils, emphasis: true),
    ],
    notes: [
      if (openInvoices.isNotEmpty) 'المبالغ أمام الفواتير هي الباقي منها.',
      for (final p in payments)
        'تسديد ${_day.format(p.createdAt)}: ${_iqd(p.amountFils)}',
    ],
  );
}

/// رسالة «ذكّره بالدين» الجاهزة (يرسلها الموظف بنفسه من واتساب).
String customerDebtReminderMessage({
  required String customerName,
  required int openFils,
  DateTime? oldestDate,
  String storeName = '',
}) {
  final name = customerName.trim();
  final store = storeName.trim();
  final since = oldestDate == null ? '' : ' منذ ${_day.format(oldestDate)}';
  return 'مرحباً${name.isEmpty ? '' : ' $name'}، '
      'نذكّرك بأن عليك${store.isEmpty ? '' : ' لدى $store'} '
      'مبلغ ${_iqd(openFils)}$since. '
      'نرجو التسديد في أقرب وقت يناسبك، وشكراً لك.';
}

/// تحذير المبلغ الزائد في نافذة التسديد؛ null = المبلغ ضمن الدين.
String? debtPaymentOverAmountWarning({
  required int enteredFils,
  required int openFils,
}) {
  if (enteredFils <= openFils + 500) return null;
  return 'المبلغ أكثر من الدين. يُسجَّل ${_iqd(openFils)} فقط، '
      'والباقي ${_iqd(enteredFils - openFils)} يُرجَع للعميل.';
}
