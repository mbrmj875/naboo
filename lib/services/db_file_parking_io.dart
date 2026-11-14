import 'dart:io';

import 'package:path/path.dart' as p;

import 'db_file_parking.dart';

/// نقل ملف القاعدة جانباً باسم صاحبه، بدل حذفه عند تبديل الحساب (البند 5.1).
class DbFileParkingImpl implements DbFileParking {
  const DbFileParkingImpl();

  static const _suffixes = ['', '-wal', '-shm', '-journal'];

  @override
  bool get supported => true;

  @override
  Future<String?> park(String dbPath, String ownerKey) async {
    final main = File(dbPath);
    if (!await main.exists()) return null;
    final target = DbFileParking.parkedPath(dbPath, ownerKey);
    // ملف محفوظ سابقاً لنفس الحساب لم يُستعد: يبقى باسم مؤرخ، لا يُحذف.
    if (await File(target).exists()) {
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      await _move(target, p.setExtension(target, '.$stamp.db'));
    }
    await _move(dbPath, target);
    return target;
  }

  @override
  Future<bool> restore(String dbPath, String ownerKey) async {
    final source = DbFileParking.parkedPath(dbPath, ownerKey);
    if (!await File(source).exists()) return false;
    // الملف الحالي فارغ أو لحساب آخر سبق حفظه؛ لا يُكتب فوقه دون حفظه.
    if (await File(dbPath).exists()) {
      final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
      await _move(
        dbPath,
        DbFileParking.parkedPath(dbPath, 'replaced-$stamp'),
      );
    }
    await _move(source, dbPath);
    return true;
  }

  Future<void> _move(String from, String to) async {
    for (final s in _suffixes) {
      final f = File('$from$s');
      if (await f.exists()) {
        final dest = File('$to$s');
        if (await dest.exists()) await dest.delete();
        await f.rename(dest.path);
      }
    }
  }
}
