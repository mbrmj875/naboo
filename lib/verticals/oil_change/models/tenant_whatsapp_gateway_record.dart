/// حالة جلسة واتساب المحل على السحابة — لكل حساب.
enum TenantWhatsappGatewayStatus {
  unknown,
  connecting,
  connected,
  disconnected,
}

/// مزود الربط: QR أو واتس360 أو واتساب الرسمي أو WAHA.
enum TenantWhatsappProvider {
  waha,
  evolution,
  cloudApi,
  whats360,
  ycloud,
  dualhook,
}

/// حالة جاهزية مبسّطة للواجهة — محسوبة على الخادم.
enum WhatsappReadyState {
  disconnected,
  preparing,
  ready,
}

class TenantWhatsappGatewayRecord {
  const TenantWhatsappGatewayRecord({
    required this.evolutionInstanceName,
    required this.status,
    this.whatsappPhone,
    this.updatedAt,
    this.provider = TenantWhatsappProvider.waha,
    this.cloudSetupStatus = 'none',
    this.readyState = WhatsappReadyState.disconnected,
    this.ratingAutoReply = true,
  });

  final String evolutionInstanceName;
  final TenantWhatsappGatewayStatus status;
  final String? whatsappPhone;
  final DateTime? updatedAt;
  final TenantWhatsappProvider provider;
  final String cloudSetupStatus;
  final WhatsappReadyState readyState;

  /// ردود واتساب التلقائية (ذكاء + تحية + تقييم) — عمود rating_auto_reply.
  final bool ratingAutoReply;

  bool get isConnected => status == TenantWhatsappGatewayStatus.connected;

  bool get isDisconnected =>
      status == TenantWhatsappGatewayStatus.disconnected;

  bool get isCloudApi => provider == TenantWhatsappProvider.cloudApi;

  bool get isWhats360 => provider == TenantWhatsappProvider.whats360;

  bool get isYcloud => provider == TenantWhatsappProvider.ycloud;

  /// قيمة DB التاريخية `dualhook` = مرسِل نابو الرسمي عبر Meta.
  bool get isNabooShared => provider == TenantWhatsappProvider.dualhook;

  bool get isOfficialTransport => isNabooShared || isYcloud || isCloudApi;

  /// شاشة إعداد بمفاتيح API (واتس360 فقط — ليس مسار Meta Embedded Signup).
  bool get needsApiCredentialSetup => isWhats360;

  bool get usesQr =>
      provider == TenantWhatsappProvider.evolution ||
      provider == TenantWhatsappProvider.waha;

  String get readyStateLabelAr {
    switch (readyState) {
      case WhatsappReadyState.ready:
        return 'جاهز';
      case WhatsappReadyState.preparing:
        return 'جاري تجهيز الخدمة…';
      case WhatsappReadyState.disconnected:
        return 'غير متصل';
    }
  }

  factory TenantWhatsappGatewayRecord.fromMap(Map<String, dynamic> m) {
    final status = _parseStatus((m['status'] ?? '').toString());
    final provider = _parseProvider((m['whatsapp_provider'] ?? '').toString());
    final cloudSetup =
        (m['cloud_setup_status'] ?? 'none').toString().trim();
    final explicitReady = (m['ready_state'] ?? '').toString().trim();
    return TenantWhatsappGatewayRecord(
      evolutionInstanceName:
          (m['evolution_instance_name'] ?? '').toString().trim(),
      status: status,
      whatsappPhone: (m['whatsapp_phone'] as String?)?.trim(),
      updatedAt: DateTime.tryParse((m['updated_at'] ?? '').toString()),
      provider: provider,
      cloudSetupStatus: cloudSetup,
      // عمود ready_state غير موجود في DB — يُحسب على السيرفر عند ready_status.
      // بدون ذلك كانت الواجهة تعرض «متصل» + «غير متصل» معاً.
      readyState: explicitReady.isNotEmpty
          ? _parseReadyState(explicitReady)
          : _deriveReadyState(
              status: status,
              cloudSetup: cloudSetup,
              provider: provider,
            ),
      ratingAutoReply: m['rating_auto_reply'] != false,
    );
  }

  static WhatsappReadyState _deriveReadyState({
    required TenantWhatsappGatewayStatus status,
    required String cloudSetup,
    required TenantWhatsappProvider provider,
  }) {
    if (status != TenantWhatsappGatewayStatus.connected) {
      return WhatsappReadyState.disconnected;
    }
    final isOfficial = provider == TenantWhatsappProvider.dualhook ||
        provider == TenantWhatsappProvider.ycloud ||
        provider == TenantWhatsappProvider.cloudApi;
    if (!isOfficial) {
      return WhatsappReadyState.ready;
    }
    if (cloudSetup == 'ready') return WhatsappReadyState.ready;
    if (cloudSetup == 'pending' || cloudSetup == 'syncing') {
      return WhatsappReadyState.preparing;
    }
    return WhatsappReadyState.preparing;
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

  static TenantWhatsappProvider _parseProvider(String raw) {
    switch (raw.trim()) {
      case 'evolution':
        return TenantWhatsappProvider.evolution;
      case 'cloud_api':
        return TenantWhatsappProvider.cloudApi;
      case 'whats360':
        return TenantWhatsappProvider.whats360;
      case 'ycloud':
        return TenantWhatsappProvider.ycloud;
      case 'dualhook':
        return TenantWhatsappProvider.dualhook;
      default:
        return TenantWhatsappProvider.waha;
    }
  }

  static WhatsappReadyState _parseReadyState(String raw) {
    switch (raw.trim()) {
      case 'ready':
        return WhatsappReadyState.ready;
      case 'preparing':
        return WhatsappReadyState.preparing;
      default:
        return WhatsappReadyState.disconnected;
    }
  }
}

TenantWhatsappGatewayStatus tenantWhatsappGatewayStatusFromCloudName(
  String? raw,
) {
  return TenantWhatsappGatewayRecord.fromMap({'status': raw ?? ''}).status;
}
