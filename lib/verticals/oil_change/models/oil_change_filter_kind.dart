import 'package:flutter/foundation.dart';

/// فئة فلتر في بطاقة غيار الزيت (مدمجة أو مضافة من المستخدم).
@immutable
class OilChangeFilterKind {
  const OilChangeFilterKind({
    required this.code,
    required this.label,
    this.id,
    this.isBuiltin = false,
    this.sortOrder = 0,
  });

  final int? id;
  final String code;
  final String label;
  final bool isBuiltin;
  final int sortOrder;

  static const engine = OilChangeFilterKind(
    code: 'engine',
    label: 'فلتر المحرك',
    isBuiltin: true,
    sortOrder: 1,
  );
  static const air = OilChangeFilterKind(
    code: 'air',
    label: 'فلتر الهواء',
    isBuiltin: true,
    sortOrder: 2,
  );
  static const gear = OilChangeFilterKind(
    code: 'gear',
    label: 'فلتر الكير',
    isBuiltin: true,
    sortOrder: 3,
  );

  /// الفئات الافتراضية الثلاث — تُزرع عند أول فتح للمحل.
  static const builtins = <OilChangeFilterKind>[engine, air, gear];

  /// توافق مؤقت مع الكود القديم الذي كان يعتمد `OilChangeFilterKind.all`.
  static const all = builtins;

  static OilChangeFilterKind? fromCode(String? raw) {
    final k = (raw ?? '').trim().toLowerCase();
    if (k.isEmpty) return null;
    for (final v in builtins) {
      if (v.code == k) return v;
    }
    return null;
  }

  /// يبني كائناً من صف DB أو من كود معروف.
  factory OilChangeFilterKind.fromMap(Map<String, dynamic> m) {
    final code = (m['code'] ?? '').toString().trim().toLowerCase();
    final label = (m['labelAr'] ?? m['label'] ?? '').toString().trim();
    final builtin = ((m['isBuiltin'] as num?)?.toInt() ?? 0) == 1;
    final known = fromCode(code);
    return OilChangeFilterKind(
      id: (m['id'] as num?)?.toInt(),
      code: code.isEmpty ? 'custom' : code,
      label: label.isNotEmpty
          ? label
          : (known?.label ?? 'فلتر'),
      isBuiltin: builtin || (known?.isBuiltin ?? false),
      sortOrder: (m['sortOrder'] as num?)?.toInt() ?? known?.sortOrder ?? 0,
    );
  }

  OilChangeFilterKind copyWith({
    int? id,
    String? code,
    String? label,
    bool? isBuiltin,
    int? sortOrder,
  }) {
    return OilChangeFilterKind(
      id: id ?? this.id,
      code: code ?? this.code,
      label: label ?? this.label,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OilChangeFilterKind && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
