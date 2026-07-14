/// خدمة إضافية في كتالوج غيار الزيت (اسم + سعر بالفلس).
class OilChangeServiceItem {
  const OilChangeServiceItem({
    required this.id,
    required this.name,
    required this.priceFils,
    this.sortOrder = 0,
  });

  final int id;
  final String name;
  final int priceFils;
  final int sortOrder;

  factory OilChangeServiceItem.fromMap(Map<String, dynamic> row) {
    return OilChangeServiceItem(
      id: (row['id'] as num?)?.toInt() ?? 0,
      name: (row['name'] ?? '').toString().trim(),
      priceFils: (row['priceFils'] as num?)?.toInt() ?? 0,
      sortOrder: (row['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}
