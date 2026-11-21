import 'dart:convert';

/// بيانات الاسترجاع المحفوظة داخل فاتورة المرتجع (`invoices.returnMeta`).
/// تُدمج مع الفاتورة بالمعرّف العالمي فتصل لكل أجهزة المحل كما هي.
class ReturnMeta {
  const ReturnMeta({
    this.originalNumber,
    this.originalDate,
    this.actor,
    this.actorUserId,
    this.approver,
    this.approverUserId,
    this.approverIsOwner = false,
    this.refundMethodAr,
    this.intactConfirmedBy,
    this.legacyReceipt = false,
    this.outsideWindow = false,
  });

  final int? originalNumber;
  final DateTime? originalDate;
  final String? actor;
  final int? actorUserId;
  final String? approver;
  final int? approverUserId;
  final bool approverIsOwner;
  final String? refundMethodAr;

  /// من أكّد أن المواد سليمة وغير مفتوحة.
  final String? intactConfirmedBy;
  final bool legacyReceipt;
  final bool outsideWindow;

  Map<String, dynamic> toJson() => {
    if (originalNumber != null) 'originalNumber': originalNumber,
    if (originalDate != null) 'originalDate': originalDate!.toIso8601String(),
    if (actor != null) 'actor': actor,
    if (actorUserId != null) 'actorUserId': actorUserId,
    if (approver != null) 'approver': approver,
    if (approverUserId != null) 'approverUserId': approverUserId,
    'approverIsOwner': approverIsOwner,
    if (refundMethodAr != null) 'refundMethod': refundMethodAr,
    if (intactConfirmedBy != null) 'intactConfirmedBy': intactConfirmedBy,
    'legacyReceipt': legacyReceipt,
    'outsideWindow': outsideWindow,
  };

  String encode() => jsonEncode(toJson());

  static ReturnMeta parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const ReturnMeta();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const ReturnMeta();
      String? str(String k) {
        final v = m[k];
        return v is String && v.trim().isNotEmpty ? v : null;
      }

      int? n(String k) => m[k] is num ? (m[k] as num).toInt() : null;
      return ReturnMeta(
        originalNumber: n('originalNumber'),
        originalDate: DateTime.tryParse(str('originalDate') ?? ''),
        actor: str('actor'),
        actorUserId: n('actorUserId'),
        approver: str('approver'),
        approverUserId: n('approverUserId'),
        approverIsOwner: m['approverIsOwner'] == true,
        refundMethodAr: str('refundMethod'),
        intactConfirmedBy: str('intactConfirmedBy'),
        legacyReceipt: m['legacyReceipt'] == true,
        outsideWindow: m['outsideWindow'] == true,
      );
    } catch (_) {
      return const ReturnMeta();
    }
  }
}
