/// جهة اتصال عميل — نموذج جاهز للتسلسل وربط قاعدة البيانات لاحقاً.
class CustomerContact {
  const CustomerContact({
    required this.id,
    required this.code,
    required this.name,
    this.phone,
    this.email,
    this.notes,
  });

  final int id;
  /// كود العرض (مثل 000002 أو 1) كما يُخزَّن ويُعرض بعد #.
  final String code;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;

  String get displayLine => '$name - #$code';

  CustomerContact copyWith({
    int? id,
    String? code,
    String? name,
    String? phone,
    String? email,
    String? notes,
  }) {
    return CustomerContact(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'name': name,
        'phone': phone,
        'email': email,
        'notes': notes,
      };

  factory CustomerContact.fromMap(Map<String, dynamic> m) {
    return CustomerContact(
      id: m['id'] as int,
      code: m['code'] as String,
      name: m['name'] as String,
      phone: m['phone'] as String?,
      email: m['email'] as String?,
      notes: m['notes'] as String?,
    );
  }
}
