import 'dart:io' show Platform;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ويندوز ولينكس: SQLite عبر FFI (sqflite لا يوفّر مكوّناً أصلياً لهما).
/// sqlite3.dll يُرفق عبر حزمة sqlite3_flutter_libs في pubspec.
void initSqliteForPlatform() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
