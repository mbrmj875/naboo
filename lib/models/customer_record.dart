/// تمثيل صف عميل من جدول `customers` — للعرض والفرز في الواجهة فقط.
class CustomerRecord {
  const CustomerRecord({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    required this.balance,
    required this.loyaltyPoints,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final double balance;
  final int loyaltyPoints;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory CustomerRecord.fromMap(Map<String, dynamic> row) {
    DateTime? parseDt(Object? raw) {
      if (raw == null) return null;
      try {
        return DateTime.parse(raw.toString());
      } catch (_) {
        return null;
      }
    }

    return CustomerRecord(
      id: row['id'] as int,
      name: (row['name'] ?? '').toString().trim(),
      phone: row['phone']?.toString().trim().isEmpty == true
          ? null
          : row['phone']?.toString().trim(),
      email: row['email']?.toString().trim().isEmpty == true
          ? null
          : row['email']?.toString().trim(),
      address: row['address']?.toString().trim().isEmpty == true
          ? null
          : row['address']?.toString().trim(),
      notes: row['notes']?.toString().trim().isEmpty == true
          ? null
          : row['notes']?.toString().trim(),
      balance: (row['balance'] as num?)?.toDouble() ?? 0,
      loyaltyPoints: (row['loyaltyPoints'] as num?)?.toInt() ?? 0,
      createdAt: parseDt(row['createdAt']),
      updatedAt: parseDt(row['updatedAt']),
    );
  }

  Map<String, dynamic> toSaveMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'notes': notes,
    };
  }

  String get statusLabel {
    if (balance > 0.01) return 'مديون';
    if (balance < -0.01) return 'دائن';
    return 'مميز';
  }
}
