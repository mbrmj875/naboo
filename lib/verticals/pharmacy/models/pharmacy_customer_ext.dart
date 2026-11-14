import 'dart:convert';

/// دواء مزمن مسجّل لدى العميل.
class PharmacyChronicMedication {
  const PharmacyChronicMedication({
    required this.productId,
    required this.productName,
    required this.startDate,
    this.lastPurchaseDate,
  });

  final int productId;
  final String productName;
  final DateTime startDate;
  final DateTime? lastPurchaseDate;

  PharmacyChronicMedication copyWith({
    int? productId,
    String? productName,
    DateTime? startDate,
    DateTime? lastPurchaseDate,
    bool clearLastPurchaseDate = false,
  }) {
    return PharmacyChronicMedication(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      startDate: startDate ?? this.startDate,
      lastPurchaseDate: clearLastPurchaseDate
          ? null
          : (lastPurchaseDate ?? this.lastPurchaseDate),
    );
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_name': productName,
        'start_date': _isoDate(startDate),
        if (lastPurchaseDate != null)
          'last_purchase_date': _isoDate(lastPurchaseDate!),
      };

  factory PharmacyChronicMedication.fromJson(Map<String, dynamic> json) {
    return PharmacyChronicMedication(
      productId: (json['product_id'] as num?)?.toInt() ?? 0,
      productName: (json['product_name'] ?? '').toString().trim(),
      startDate: _parseDate(json['start_date']) ?? DateTime.now(),
      lastPurchaseDate: _parseDate(json['last_purchase_date']),
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  static String _isoDate(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day).toIso8601String().split('T').first;
}

/// امتداد صيدلاني لسجل العميل في Core.
class PharmacyCustomerExt {
  const PharmacyCustomerExt({
    this.id,
    required this.tenantId,
    required this.customerId,
    this.allergies = const [],
    this.chronicMedications = const [],
    this.medicalNotes,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final int tenantId;
  final int customerId;
  final List<String> allergies;
  final List<PharmacyChronicMedication> chronicMedications;
  final String? medicalNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const int maxMedicalNotesLength = 500;

  PharmacyCustomerExt copyWith({
    int? id,
    int? tenantId,
    int? customerId,
    List<String>? allergies,
    List<PharmacyChronicMedication>? chronicMedications,
    String? medicalNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearMedicalNotes = false,
  }) {
    return PharmacyCustomerExt(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      customerId: customerId ?? this.customerId,
      allergies: allergies ?? this.allergies,
      chronicMedications: chronicMedications ?? this.chronicMedications,
      medicalNotes: clearMedicalNotes ? null : (medicalNotes ?? this.medicalNotes),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toInsertMap({required DateTime now}) {
    return {
      'tenantId': tenantId,
      'customerId': customerId,
      'allergiesJson': jsonEncode(allergies),
      'chronicMedsJson': jsonEncode(
        chronicMedications.map((m) => m.toJson()).toList(),
      ),
      'medicalNotes': _nullableTrim(medicalNotes),
      'createdAt': now.toUtc().toIso8601String(),
      'updatedAt': now.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toUpdateMap({required DateTime now}) {
    return {
      'allergiesJson': jsonEncode(allergies),
      'chronicMedsJson': jsonEncode(
        chronicMedications.map((m) => m.toJson()).toList(),
      ),
      'medicalNotes': _nullableTrim(medicalNotes),
      'updatedAt': now.toUtc().toIso8601String(),
    };
  }

  factory PharmacyCustomerExt.fromMap(Map<String, dynamic> row) {
    DateTime? parseDt(Object? raw) {
      if (raw == null) return null;
      try {
        return DateTime.parse(raw.toString());
      } catch (_) {
        return null;
      }
    }

    return PharmacyCustomerExt(
      id: (row['id'] as num?)?.toInt(),
      tenantId: (row['tenantId'] as num?)?.toInt() ?? 0,
      customerId: (row['customerId'] as num?)?.toInt() ?? 0,
      allergies: _decodeAllergies(row['allergiesJson']),
      chronicMedications: _decodeChronicMeds(row['chronicMedsJson']),
      medicalNotes: row['medicalNotes']?.toString().trim().isEmpty == true
          ? null
          : row['medicalNotes']?.toString().trim(),
      createdAt: parseDt(row['createdAt']),
      updatedAt: parseDt(row['updatedAt']),
    );
  }

  static List<String> _decodeAllergies(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<PharmacyChronicMedication> _decodeChronicMeds(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => PharmacyChronicMedication.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .where((m) => m.productId > 0 && m.productName.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String? _nullableTrim(String? value) {
    final t = value?.trim();
    if (t == null || t.isEmpty) return null;
    return t.length > maxMedicalNotesLength
        ? t.substring(0, maxMedicalNotesLength)
        : t;
  }
}
