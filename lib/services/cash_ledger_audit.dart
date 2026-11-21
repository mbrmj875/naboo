/// المرحلة 5 — الشريحة 5: فحص (قراءة فقط) لقيود صندوق زائدة من خللين قديمين.
///
/// 1) عكس دفعة مورد قبل الإصلاح: كان يحذف قيد الدفعة (السالب) حذفاً ناعماً ثم
///    يضيف قيداً عكسياً موجباً، فيزيد الصندوق بقيمة الدفعة مرة إضافية.
/// 2) إصلاح «القيود الناقصة» قبل الإصلاح: كان ينشئ قيد «مقدّم» لفاتورة آجلة
///    بلا عربون بعد تسديدها، فيُحسب التسديد مرتين.
///
/// لا يغيّر الفحص شيئاً. التصحيح قيد سالب لكل حالة، بقرار المالك وبرمزه.
enum CashAuditKind { supplierReversal, phantomCreditAdvance }

class CashAuditFinding {
  const CashAuditFinding({
    required this.kind,
    required this.key,
    required this.excessFils,
    required this.date,
    required this.label,
  });

  final CashAuditKind kind;

  /// مفتاح ثابت بين الأجهزة يمنع تصحيح الحالة نفسها مرتين.
  final String key;

  /// ما زاد في الصندوق بغير حق (موجب).
  final int excessFils;
  final DateTime date;
  final String label;

  String get kindLabel => switch (kind) {
    CashAuditKind.supplierReversal => 'عكس دفعة مورد حُسب مرتين',
    CashAuditKind.phantomCreditAdvance => 'تسديد دين حُسب مرتين',
  };

  /// نص قيد التصحيح؛ المفتاح بين قوسين يُبحث عنه لاحقاً.
  String get correctionDescription => 'تصحيح فحص الصندوق — $kindLabel — $label [$key]';
}

class CashAuditReport {
  const CashAuditReport(this.findings);

  final List<CashAuditFinding> findings;

  int get totalExcessFils =>
      findings.fold<int>(0, (s, f) => s + f.excessFils);

  bool get isClean => findings.isEmpty;
}

/// نوع قيد التصحيح في `cash_ledger`.
const String kCashAuditCorrectionType = 'cash_audit_correction';
