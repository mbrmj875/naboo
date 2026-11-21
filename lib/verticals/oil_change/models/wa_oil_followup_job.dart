class WaOilFollowupJob {
  const WaOilFollowupJob({
    required this.id,
    required this.orderRef,
    required this.customerPhone,
    required this.dueAt,
    required this.status,
    required this.customerName,
    required this.carLabel,
  });

  final String id;
  final String orderRef;
  final String customerPhone;
  final DateTime dueAt;
  final String status;
  final String customerName;
  final String carLabel;

  String get statusAr {
    switch (status) {
      case 'queued':
        return 'مجدول';
      case 'sending':
        return 'جاري الإرسال';
      case 'sent':
        return 'أُرسل';
      case 'skipped_no_wallet':
        return 'بانتظار الرصيد';
      case 'skipped_no_template':
        return 'بانتظار القالب';
      case 'cancelled':
        return 'ملغى';
      case 'failed':
        return 'فشل';
      default:
        return status;
    }
  }

  factory WaOilFollowupJob.fromMap(Map<String, dynamic> row) {
    final payload = row['payload'];
    final map = payload is Map
        ? Map<String, dynamic>.from(payload as Map)
        : <String, dynamic>{};
    return WaOilFollowupJob(
      id: (row['id'] ?? '').toString(),
      orderRef: (row['order_ref'] ?? '').toString(),
      customerPhone: (row['customer_phone'] ?? '').toString(),
      dueAt: DateTime.tryParse(row['due_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      status: (row['status'] ?? 'queued').toString(),
      customerName: (map['customer_name'] ?? '—').toString(),
      carLabel: (map['car'] ?? '—').toString(),
    );
  }
}
