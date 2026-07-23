/// خدمة غسل في الكتالوج المحلي (اسم + سعر بالفلس).
class CarWashServiceItem {
  const CarWashServiceItem({
    required this.id,
    required this.name,
    required this.priceFils,
    this.sortOrder = 0,
  });

  final int id;
  final String name;
  final int priceFils;
  final int sortOrder;

  factory CarWashServiceItem.fromMap(Map<String, dynamic> row) {
    return CarWashServiceItem(
      id: (row['id'] as num?)?.toInt() ?? 0,
      name: (row['name'] ?? '').toString().trim(),
      priceFils: (row['priceFils'] as num?)?.toInt() ?? 0,
      sortOrder: (row['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}
