import 'package:intl/intl.dart';

import '../models/supplier_ap_models.dart';
import '../printing/receipt_model.dart';

/// المرحلة 5 — الشريحة 4: استحقاق وصولات المورد وكشف حسابه.
///
/// كل الحسابات بالفلس (int) ثم تُعرض بالدينار.

final _num = NumberFormat('#,##0', 'en');

String _iqd(int fils) => '${_num.format(fils / 1000.0)} د.ع';

int supplierFils(double amount) => (amount * 1000).round();

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _fmtDay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// صيغة حفظ «يُدفع قبل» في `supplier_bills.dueDate` (يوم فقط، بلا ساعة).
String supplierDueDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// تاريخ الوصل الذي يُرتَّب به: تاريخ وصلهم إن وُجد وإلا وقت تسجيله.
DateTime supplierBillDate(SupplierBill b) =>
    (b.theirBillDate ?? b.createdAt).toLocal();

/// حالة الاستحقاق لمورد واحد.
class SupplierDueStatus {
  const SupplierDueStatus({
    this.dueFils = 0,
    this.daysLate = 0,
    this.oldestDueDate,
    this.nextDueDate,
  });

  /// الباقي من الوصولات التي حلّ موعد دفعها (اليوم أو قبله).
  final int dueFils;

  /// أيام مضت على أقدم موعد حلّ (0 = موعده اليوم).
  final int daysLate;
  final DateTime? oldestDueDate;

  /// أقرب موعد قادم لوصل لم يُسدَّد بعد (للعرض فقط).
  final DateTime? nextDueDate;

  bool get isDue => dueFils >= 500;
}

/// الدفعات لا تُخصَّص لوصل بعينه، فتُوزَّع على الوصولات بالأقدم أولاً،
/// والباقي من كل وصل موعده اليوم أو قبله يُعدّ مستحقاً.
SupplierDueStatus computeSupplierDue({
  required List<SupplierBill> bills,
  required int paidFils,
  DateTime? today,
}) {
  final now = _day(today ?? DateTime.now());
  final sorted = [...bills]
    ..sort((a, b) {
      final c = supplierBillDate(a).compareTo(supplierBillDate(b));
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  var left = paidFils;
  var due = 0;
  DateTime? oldest;
  DateTime? next;
  for (final b in sorted) {
    final amt = supplierFils(b.amount);
    final cover = left >= amt ? amt : (left > 0 ? left : 0);
    left -= cover;
    final rem = amt - cover;
    if (rem <= 0 || b.dueDate == null) continue;
    final d = _day(b.dueDate!);
    if (!d.isAfter(now)) {
      due += rem;
      if (oldest == null || d.isBefore(oldest)) oldest = d;
    } else if (next == null || d.isBefore(next)) {
      next = d;
    }
  }
  return SupplierDueStatus(
    dueFils: due,
    daysLate: oldest == null ? 0 : now.difference(oldest).inDays,
    oldestDueDate: oldest,
    nextDueDate: next,
  );
}

/// نص قصير لحالة الاستحقاق على بطاقة المورد.
String supplierDueLabel(SupplierDueStatus s) {
  if (!s.isDue) return '';
  final when = s.daysLate == 0 ? 'حان دفعه اليوم' : 'متأخر ${s.daysLate} يوماً';
  return '$when · ${_iqd(s.dueFils)}';
}

enum SupplierStatementKind { bill, payment, supplierReturn, externalPayment }

class SupplierStatementLine {
  const SupplierStatementLine({
    required this.kind,
    required this.date,
    required this.fils,
    required this.balanceAfterFils,
    required this.label,
  });

  final SupplierStatementKind kind;
  final DateTime date;

  /// موجب للوصل (يزيد ما علينا)، سالب للدفعة والمرتجع.
  final int fils;
  final int balanceAfterFils;
  final String label;
}

/// كشف حساب المورد: قائمة بالتاريخ (وصل، دفعة، مرتجع) والرصيد بعد كل سطر.
/// الدفعات الملغاة لا تدخل الكشف.
class SupplierStatement {
  SupplierStatement({
    required this.supplierName,
    required List<SupplierBill> bills,
    required List<SupplierPayout> payouts,
    DateTime? now,
  }) : date = now ?? DateTime.now(),
       lines = _build(bills, payouts);

  final String supplierName;
  final DateTime date;
  final List<SupplierStatementLine> lines;

  int get balanceFils => lines.isEmpty ? 0 : lines.last.balanceAfterFils;

  static SupplierStatementKind _payoutKind(SupplierPayout p) {
    if (p.affectsCash) return SupplierStatementKind.payment;
    final note = (p.note ?? '').trim();
    return note.startsWith('مرتجع')
        ? SupplierStatementKind.supplierReturn
        : SupplierStatementKind.externalPayment;
  }

  static List<SupplierStatementLine> _build(
    List<SupplierBill> bills,
    List<SupplierPayout> payouts,
  ) {
    final raw = <({DateTime date, int order, int fils, SupplierStatementKind kind, String label})>[
      for (final b in bills)
        (
          date: supplierBillDate(b),
          order: 0,
          fils: supplierFils(b.amount),
          kind: SupplierStatementKind.bill,
          label: (b.theirReference ?? '').trim().isEmpty
              ? 'وصل'
              : 'وصل ${b.theirReference!.trim()}',
        ),
      for (final p in payouts.where((p) => !p.isVoided))
        (
          date: p.createdAt.toLocal(),
          order: 1,
          fils: -supplierFils(p.amount),
          kind: _payoutKind(p),
          label: switch (_payoutKind(p)) {
            SupplierStatementKind.payment => 'دفعة',
            SupplierStatementKind.supplierReturn => 'مرتجع',
            _ => 'دفعة خارج الصندوق',
          },
        ),
    ]..sort((a, b) {
        final c = _day(a.date).compareTo(_day(b.date));
        return c != 0 ? c : a.order.compareTo(b.order);
      });
    var bal = 0;
    return [
      for (final r in raw)
        SupplierStatementLine(
          kind: r.kind,
          date: r.date,
          fils: r.fils,
          balanceAfterFils: bal += r.fils,
          label: r.label,
        ),
    ];
  }

  String toWhatsAppText({String storeName = ''}) {
    final b = StringBuffer();
    final store = storeName.trim();
    b.writeln('كشف حساب مورد${store.isEmpty ? '' : ' — $store'}');
    b.writeln('المورد: ${supplierName.trim()}');
    b.writeln('التاريخ: ${_fmtDay(date)}');
    b.writeln();
    if (lines.isEmpty) {
      b.write('لا حركات مسجّلة.');
      return b.toString();
    }
    for (final l in lines) {
      final amt = l.fils >= 0 ? _iqd(l.fils) : '- ${_iqd(-l.fils)}';
      b.writeln(
        '• ${_fmtDay(l.date)} ${l.label}: $amt، الرصيد ${_iqd(l.balanceAfterFils)}',
      );
    }
    b.writeln();
    b.write('الرصيد الآن: ${_iqd(balanceFils)}');
    return b.toString();
  }

  ReceiptDocument toReceipt() => ReceiptDocument(
    kind: ReceiptKind.supplierStatement,
    date: date,
    fields: [ReceiptField('المورد', supplierName.trim(), bold: true)],
    lines: [
      for (final l in lines)
        ReceiptLine(
          name: '${_fmtDay(l.date)} ${l.label}',
          totalFils: l.fils,
        ),
    ],
    totals: [ReceiptTotal('الرصيد الآن', balanceFils, emphasis: true)],
    notes: const ['الموجب وصل علينا، والسالب دفعة أو مرتجع.'],
  );
}

/// مورد حان دفع وصل له (أعلى تبويب الموردين وفي الإشعارات).
class SupplierDueEntry {
  const SupplierDueEntry({
    required this.supplierId,
    required this.name,
    required this.status,
  });

  final int supplierId;
  final String name;
  final SupplierDueStatus status;
}
