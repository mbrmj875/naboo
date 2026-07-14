import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// الويب (Safari على iOS / Chrome): SQLite عبر IndexedDB + WASM.
void initSqliteForPlatform() {
  databaseFactory = databaseFactoryFfiWeb;
}
