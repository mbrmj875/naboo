import 'dart:convert';

import 'pharmacy_rx_schedule.dart';

/// سجل مرجعي للمادة الفعّالة — [pharmacy_drug_reference].
class PharmacyDrugReference {
  const PharmacyDrugReference({
    required this.id,
    required this.tenantId,
    required this.nameAr,
    required this.nameEn,
    this.atcCode,
    this.indications = const [],
    this.indicationsFreeText,
    this.ageBand = PharmacyAgeBand.both,
    this.interactionsPlaceholder = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int id;
  final int tenantId;
  final String nameAr;
  final String nameEn;
  final String? atcCode;
  final List<String> indications;
  final String? indicationsFreeText;
  final String ageBand;
  final List<String> interactionsPlaceholder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory PharmacyDrugReference.fromMap(Map<String, dynamic> map) {
    return PharmacyDrugReference(
      id: (map['id'] as num).toInt(),
      tenantId: (map['tenantId'] as num).toInt(),
      nameAr: (map['nameAr'] as String?) ?? '',
      nameEn: (map['nameEn'] as String?) ?? '',
      atcCode: map['atcCode'] as String?,
      indications: _decodeStringList(map['indicationsJson']),
      indicationsFreeText: map['indicationsFreeText'] as String?,
      ageBand: (map['ageBand'] as String?) ?? PharmacyAgeBand.both,
      interactionsPlaceholder:
          _decodeStringList(map['interactionsPlaceholderJson']),
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      deletedAt: map['deletedAt'] != null
          ? DateTime.tryParse(map['deletedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toInsertMap({
    required int tenantId,
    required DateTime now,
  }) {
    return {
      'tenantId': tenantId,
      'nameAr': nameAr.trim(),
      'nameEn': nameEn.trim(),
      'atcCode': atcCode?.trim().isEmpty == true ? null : atcCode?.trim(),
      'indicationsJson': jsonEncode(indications),
      'indicationsFreeText': indicationsFreeText?.trim(),
      'ageBand': ageBand,
      'interactionsPlaceholderJson': jsonEncode(interactionsPlaceholder),
      'createdAt': now.toUtc().toIso8601String(),
      'updatedAt': now.toUtc().toIso8601String(),
    };
  }

  static List<String> _decodeStringList(Object? raw) {
    if (raw == null) return const [];
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }
}
