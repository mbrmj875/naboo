/// حالة جلسة واتساب المحل على Evolution (سحابة — لكل حساب).
enum TenantWhatsappGatewayStatus {
  unknown,
  connecting,
  connected,
  disconnected,
}

class TenantWhatsappGatewayRecord {
  const TenantWhatsappGatewayRecord({
    required this.evolutionInstanceName,
    required this.status,
    this.whatsappPhone,
    this.updatedAt,
  });

  final String evolutionInstanceName;
  final TenantWhatsappGatewayStatus status;
  final String? whatsappPhone;
  final DateTime? updatedAt;

  bool get isConnected => status == TenantWhatsappGatewayStatus.connected;

  bool get isDisconnected =>
      status == TenantWhatsappGatewayStatus.disconnected;

  factory TenantWhatsappGatewayRecord.fromMap(Map<String, dynamic> m) {
    return TenantWhatsappGatewayRecord(
      evolutionInstanceName:
          (m['evolution_instance_name'] ?? '').toString().trim(),
      status: _parseStatus((m['status'] ?? '').toString()),
      whatsappPhone: (m['whatsapp_phone'] as String?)?.trim(),
      updatedAt: DateTime.tryParse((m['updated_at'] ?? '').toString()),
    );
  }

  static TenantWhatsappGatewayStatus _parseStatus(String raw) {
    switch (raw.trim()) {
      case 'connecting':
        return TenantWhatsappGatewayStatus.connecting;
      case 'connected':
        return TenantWhatsappGatewayStatus.connected;
      case 'disconnected':
        return TenantWhatsappGatewayStatus.disconnected;
      default:
        return TenantWhatsappGatewayStatus.unknown;
    }
  }
}

TenantWhatsappGatewayStatus tenantWhatsappGatewayStatusFromCloudName(
  String? raw,
) {
  return TenantWhatsappGatewayRecord.fromMap({'status': raw ?? ''}).status;
}
