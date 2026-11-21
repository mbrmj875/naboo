import 'dart:convert';
import 'dart:typed_data';

/// بيانات فرع الموظف — اسم وعنوان وهاتف وشعار خاصة بهذا المستخدم فقط.
///
/// منفصلة عن [PrintSettingsData] المشتركة حتى لا يكتب موظف على بيانات
/// المتجر العامة التي يستخدمها صاحب العمل.
class StaffBranchProfile {
  const StaffBranchProfile({
    required this.storeTitleLine,
    required this.storeAddress,
    required this.storePhones,
    this.storeLatitude,
    this.storeLongitude,
    this.storeLogoBase64 = '',
  });

  factory StaffBranchProfile.empty() => const StaffBranchProfile(
        storeTitleLine: '',
        storeAddress: '',
        storePhones: [],
      );

  final String storeTitleLine;
  final String storeAddress;
  final List<String> storePhones;
  final double? storeLatitude;
  final double? storeLongitude;
  final String storeLogoBase64;

  /// هل عبّأ الموظف اسماً على الأقل؟ عندها نستخدم بياناته بدل العامة.
  bool get hasIdentity => storeTitleLine.trim().isNotEmpty;

  bool get hasStoreLogo => storeLogoBase64.trim().isNotEmpty;

  Uint8List? get storeLogoBytes {
    final raw = storeLogoBase64.trim();
    if (raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  bool get hasStoreLocation =>
      storeLatitude != null && storeLongitude != null;

  Map<String, dynamic> toJson() => {
        'storeTitleLine': storeTitleLine,
        'storeAddress': storeAddress,
        'storePhones': storePhones,
        'storeLatitude': storeLatitude,
        'storeLongitude': storeLongitude,
        'storeLogoBase64': storeLogoBase64,
      };

  factory StaffBranchProfile.fromJson(Map<String, dynamic>? m) {
    if (m == null) return StaffBranchProfile.empty();
    return StaffBranchProfile(
      storeTitleLine: (m['storeTitleLine'] as String? ?? '').trim(),
      storeAddress: (m['storeAddress'] as String? ?? '').trim(),
      storePhones: _phonesFromJson(m['storePhones']),
      storeLatitude: _coord(m['storeLatitude'], limit: 90),
      storeLongitude: _coord(m['storeLongitude'], limit: 180),
      storeLogoBase64: (m['storeLogoBase64'] as String? ?? '').trim(),
    );
  }

  factory StaffBranchProfile.fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return StaffBranchProfile.empty();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return StaffBranchProfile.fromJson(decoded);
      }
      if (decoded is Map) {
        return StaffBranchProfile.fromJson(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return StaffBranchProfile.empty();
  }

  String toJsonString() => jsonEncode(toJson());

  StaffBranchProfile copyWith({
    String? storeTitleLine,
    String? storeAddress,
    List<String>? storePhones,
    double? storeLatitude,
    double? storeLongitude,
    bool clearStoreLocation = false,
    String? storeLogoBase64,
  }) {
    return StaffBranchProfile(
      storeTitleLine: storeTitleLine ?? this.storeTitleLine,
      storeAddress: storeAddress ?? this.storeAddress,
      storePhones: storePhones ?? this.storePhones,
      storeLatitude:
          clearStoreLocation ? null : (storeLatitude ?? this.storeLatitude),
      storeLongitude:
          clearStoreLocation ? null : (storeLongitude ?? this.storeLongitude),
      storeLogoBase64: storeLogoBase64 ?? this.storeLogoBase64,
    );
  }

  static List<String> _phonesFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static double? _coord(Object? raw, {required double limit}) {
    final double? value;
    if (raw is num) {
      value = raw.toDouble();
    } else if (raw is String) {
      value = double.tryParse(raw.trim());
    } else {
      value = null;
    }
    if (value == null || value.isNaN || value.isInfinite) return null;
    if (value < -limit || value > limit) return null;
    return value;
  }
}
