import 'dart:io' show Platform;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ويندوز ولينكس: SQLite عبر FFI (sqflite لا يوفّر مكوّناً أصلياً لهما).
void initSqliteForPlatform() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}
