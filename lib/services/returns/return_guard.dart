import '../../models/store_policy.dart';

/// نتيجة فحص الاسترجاع قبل الحفظ.
enum ReturnVerdict { allowed, needsApproval, forbidden }

/// لماذا يحتاج الاسترجاع موافقة.
enum ReturnApprovalReason { legacyReceipt, outsideWindow, limitedStaff }

class ReturnDecision {
  const ReturnDecision._(this.verdict, {this.message, this.reasons = const {}});

  const ReturnDecision.allowed({Set<ReturnApprovalReason> notes = const {}})
    : this._(ReturnVerdict.allowed, reasons: notes);

  const ReturnDecision.forbidden(String message)
    : this._(ReturnVerdict.forbidden, message: message);

  const ReturnDecision.needsApproval(Set<ReturnApprovalReason> reasons)
    : this._(ReturnVerdict.needsApproval, reasons: reasons);

  final ReturnVerdict verdict;

  /// سبب المنع (عربي).
  final String? message;

  /// أسباب الموافقة. عند «مسموح» للمالك: ما تجاوزه بنفسه (يُسجَّل).
  final Set<ReturnApprovalReason> reasons;

  bool get isForbidden => verdict == ReturnVerdict.forbidden;
  bool get needsApproval => verdict == ReturnVerdict.needsApproval;

  /// نص الأسباب للعرض.
  String reasonsAr() => reasons.map(returnApprovalReasonAr).join('، ');
}

String returnApprovalReasonAr(ReturnApprovalReason r) => switch (r) {
  ReturnApprovalReason.legacyReceipt => 'إيصال قديم بلا رمز موثّق',
  ReturnApprovalReason.outsideWindow => 'خارج مدة الاسترجاع',
  ReturnApprovalReason.limitedStaff => 'صلاحية الموظف محدودة',
};

/// قرار الاسترجاع — دالة صافية (بلا قاعدة ولا واجهة).
abstract final class ReturnGuard {
  static const offlineMessage =
      'لا يمكن الاسترجاع بدون إنترنت. تأكد من الاتصال ثم أعد المحاولة.';

  static ReturnDecision evaluate({
    required ReturnPolicy policy,
    required DateTime invoiceDate,
    required DateTime now,
    required bool legacy,
    required bool fullyReturned,
    required bool isOwner,
    required bool elevated,
    required bool hasOpenShift,
  }) {
    if (!policy.enabled) {
      return const ReturnDecision.forbidden('الاسترجاع مطفأ في إعدادات المحل.');
    }
    if (fullyReturned) {
      return const ReturnDecision.forbidden(
        'أُرجعت هذه الفاتورة بالكامل سابقاً.',
      );
    }
    if (!hasOpenShift) {
      return const ReturnDecision.forbidden(
        'لا يمكن الاسترجاع بدون وردية مفتوحة. افتح الوردية أولاً.',
      );
    }
    final outside = isOutsideWindow(
      invoiceDate: invoiceDate,
      now: now,
      windowDays: policy.windowDays,
    );
    if (outside && policy.afterWindow == ReturnAfterWindow.forbidden) {
      return ReturnDecision.forbidden(
        'انتهت مدة الاسترجاع (${policy.windowDays} يوم) والسياسة تمنع بعدها.',
      );
    }
    final reasons = <ReturnApprovalReason>{
      if (legacy) ReturnApprovalReason.legacyReceipt,
      if (outside) ReturnApprovalReason.outsideWindow,
    };
    // المالك يوافق لنفسه دائماً؛ ما تجاوزه يُسجَّل.
    if (isOwner) return ReturnDecision.allowed(notes: reasons);
    if (!elevated) reasons.add(ReturnApprovalReason.limitedStaff);
    if (reasons.isEmpty) return const ReturnDecision.allowed();
    return ReturnDecision.needsApproval(reasons);
  }

  /// خارج المدة: مرّ أكثر من [windowDays] يوماً تقويمياً على يوم الفاتورة.
  static bool isOutsideWindow({
    required DateTime invoiceDate,
    required DateTime now,
    required int windowDays,
  }) {
    final d0 = DateTime(invoiceDate.year, invoiceDate.month, invoiceDate.day);
    final d1 = DateTime(now.year, now.month, now.day);
    return d1.difference(d0).inDays > windowDays;
  }
}
