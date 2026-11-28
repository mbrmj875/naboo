import 'db_file_parking.dart';

/// الويب: القاعدة في IndexedDB ولا ملفات تُنقل، فيبقى السلوك القديم.
class DbFileParkingImpl implements DbFileParking {
  const DbFileParkingImpl();

  @override
  bool get supported => false;

  @override
  Future<String?> park(String dbPath, String ownerKey) async => null;

  @override
  Future<bool> restore(String dbPath, String ownerKey) async => false;
}
