/// أنواع الغسل الافتراضية — الأسعار بالفلس (1 دينار = 1000 فلس).
class CarWashType {
  const CarWashType({
    required this.id,
    required this.nameAr,
    required this.defaultPriceFils,
  });

  final String id;
  final String nameAr;
  final int defaultPriceFils;
}

abstract final class CarWashTypes {
  CarWashTypes._();

  static const exterior = CarWashType(
    id: 'exterior',
    nameAr: 'غسيل خارجي',
    defaultPriceFils: 5000 * 1000,
  );

  static const interior = CarWashType(
    id: 'interior',
    nameAr: 'غسيل داخلي',
    defaultPriceFils: 7000 * 1000,
  );

  static const full = CarWashType(
    id: 'full',
    nameAr: 'غسيل كامل',
    defaultPriceFils: 10000 * 1000,
  );

  static const List<CarWashType> all = [exterior, interior, full];

  static CarWashType? byId(String id) {
    final t = id.trim();
    for (final e in all) {
      if (e.id == t) return e;
    }
    return null;
  }

  static CarWashType? byNameAr(String name) {
    final n = name.trim();
    for (final e in all) {
      if (e.nameAr == n) return e;
    }
    return null;
  }
}
