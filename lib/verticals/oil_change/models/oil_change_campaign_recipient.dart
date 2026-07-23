import '../utils/oil_change_log_format.dart';
import 'oil_change_wa_notify_status.dart';

/// عميل واحد في حملة واتساب — آخر زيارة غيار زيت (بدون تكرار بالهاتف).
class OilChangeCampaignRecipient {
  const OilChangeCampaignRecipient({
    required this.orderId,
    required this.customerName,
    required this.phone,
    required this.deviceName,
    required this.carModel,
    required this.engineSize,
    required this.lastVisitIso,
    required this.orderRow,
    this.waNotifyStatus = OilChangeWaNotifyStatus.unknown,
  });

  final int orderId;
  final String customerName;
  final String phone;
  final String deviceName;
  final String carModel;
  final String engineSize;
  final String? lastVisitIso;
  final Map<String, dynamic> orderRow;
  final OilChangeWaNotifyStatus waNotifyStatus;

  OilChangeCampaignRecipient copyWith({
    OilChangeWaNotifyStatus? waNotifyStatus,
  }) {
    return OilChangeCampaignRecipient(
      orderId: orderId,
      customerName: customerName,
      phone: phone,
      deviceName: deviceName,
      carModel: carModel,
      engineSize: engineSize,
      lastVisitIso: lastVisitIso,
      orderRow: orderRow,
      waNotifyStatus: waNotifyStatus ?? this.waNotifyStatus,
    );
  }

  String get displayCar {
    final parts = <String>[
      if (deviceName.isNotEmpty) deviceName,
      if (carModel.isNotEmpty && carModel != deviceName) carModel,
      if (engineSize.isNotEmpty) engineSize,
    ];
    if (parts.isEmpty) return '—';
    return parts.join(' · ');
  }

  String get lastVisitLabel => oilFormatDate(lastVisitIso);

  static OilChangeCampaignRecipient? fromLogRow(Map<String, dynamic> r) {
    final phone = (r['customerPhone'] ?? '').toString().trim();
    if (phone.isEmpty) return null;
    final id = (r['id'] as num?)?.toInt();
    if (id == null || id <= 0) return null;
    final name = (r['customerNameSnapshot'] ?? '').toString().trim();
    return OilChangeCampaignRecipient(
      orderId: id,
      customerName: name.isEmpty ? 'عميل' : name,
      phone: phone,
      deviceName: (r['deviceName'] ?? '').toString().trim(),
      carModel: (r['carModel'] ?? '').toString().trim(),
      engineSize: (r['engineSize'] ?? '').toString().trim(),
      lastVisitIso: (r['createdAt'] ?? r['updatedAt'])?.toString(),
      orderRow: r,
      waNotifyStatus: OilChangeWaNotifyStatusDb.fromDb(r['waNotifyStatus']),
    );
  }

  static String phoneKey(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    if (!d.startsWith('964')) {
      if (d.startsWith('0')) return '964${d.substring(1)}';
      if (d.length == 10 && d.startsWith('7')) return '964$d';
    }
    return d;
  }
}
