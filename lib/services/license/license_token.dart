import 'dart:convert';

/// يزيل المسافات والأسطر والعلامات الخفية من JWT المضغوط (أخطاء لصق شائعة).
String normalizeJwtCompactInput(String raw) {
  return raw
      .trim()
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .replaceAll(RegExp(r'\s+'), '');
}

/// رخصة v2 — ناتجة من JWT (RS256) بعد التحقق.
class LicenseToken {
  const LicenseToken({
    required this.tenantId,
    required this.plan,
    required this.maxDevices,
    required this.startsAt,
    required this.endsAt,
    required this.licenseId,
    required this.isTrial,
    required this.issuedAt,
    required this.kid,
  });

  final String tenantId;
  final String plan;
  final int maxDevices;
  final DateTime startsAt;
  final DateTime endsAt;
  final String licenseId;
  final bool isTrial;
  final DateTime issuedAt;

  /// Key-id from JWT header.
  final String kid;

  bool get isExpired => !DateTime.now().toUtc().isBefore(endsAt.toUtc());

  static LicenseToken fromJwt({
    required Map<String, dynamic> header,
    required Map<String, dynamic> claims,
  }) {
    final kid = (header['kid'] ?? '').toString().trim();
    if (kid.isEmpty) throw const FormatException('missing kid');

    String getStr(String key) =>
        (claims[key] ?? claims[key.replaceAll('_', '')] ?? '').toString();

    int getInt(String key, {int fallback = 0}) {
      final v = claims[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) return fallback;
      return int.tryParse(s) ?? fallback;
    }

    bool getBool(String key) {
      final v = claims[key];
      if (v is bool) return v;
      final s = v?.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }

    DateTime getDate(String key) {
      final v = claims[key];
      if (v is int) {
        // epoch seconds (JWT style)
        return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true);
      }
      if (v is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          v.toInt() * 1000,
          isUtc: true,
        );
      }
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) {
        throw FormatException('missing $key');
      }
      final dt = DateTime.parse(s);
      return dt.isUtc ? dt : dt.toUtc();
    }

    final tenantId = getStr('tenant_id').trim();
    final plan = getStr('plan').trim();
    final maxDevices = getInt('max_devices', fallback: 1);
    final startsAt = getDate('starts_at');
    final endsAt = getDate('ends_at');
    final licenseId = getStr('license_id').trim();
    final isTrial = getBool('is_trial');
    final issuedAt = getDate('issued_at');

    if (tenantId.isEmpty) throw const FormatException('missing tenant_id');
    if (plan.isEmpty) throw const FormatException('missing plan');
    if (licenseId.isEmpty) throw const FormatException('missing license_id');

    return LicenseToken(
      tenantId: tenantId,
      plan: plan,
      maxDevices: maxDevices,
      startsAt: startsAt,
      endsAt: endsAt,
      licenseId: licenseId,
      isTrial: isTrial,
      issuedAt: issuedAt,
      kid: kid,
    );
  }

  Map<String, dynamic> toJson() => {
    'tenant_id': tenantId,
    'plan': plan,
    'max_devices': maxDevices,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'license_id': licenseId,
    'is_trial': isTrial,
    'issued_at': issuedAt.toUtc().toIso8601String(),
    'kid': kid,
  };

  @override
  String toString() => jsonEncode(toJson());
}

