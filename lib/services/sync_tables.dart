import 'local_device.dart';
import 'stock_ledger.dart';

/// الجداول التي تنتقل بين الأجهزة، في النسخة الكاملة وفي سجل التعديلات.
class SyncTables {
  SyncTables._();

  /// جداول محلية لكل جهاز: لا تُرفع ولا تُلتقط تعديلاتها.
  static const localOnly = <String>{
    'android_metadata',
    'sqlite_sequence',
    'users', // secrets في user_profiles.pinHash/pinSalt — لا نرفع users مباشرة
    'sync_queue', // طابور المزامنة محلي لكل جهاز — لا يُرفع في اللقطة
    'product_warehouse_stock',
    StockLedger.ctlTable, // إيقاف المشغّل محلي لكل جهاز
    LocalDevice.table, // معرّف الجهاز محلي، لا يُنسخ إلى جهاز آخر
    // سجل التعديلات (المرحلة 3) ومؤشر الاستلام: محليان لكل جهاز.
    'sync_outbox',
    'sync_outbox_ctl',
    'sync_cursor',
  };

  /// تبقى في النسخة الكاملة، ولا تُلتقط تعديلاتها: سجل أخطاء الترقية خاص
  /// بكل جهاز، وقيمته في وصوله للخادم داخل النسخة لتشخيص الهاتف.
  static const notCaptured = <String>{'local_migration_issues'};

  static bool isCaptured(String table) =>
      isSynced(table) && !notCaptured.contains(table);

  static bool isSynced(String table) =>
      table.isNotEmpty &&
      !table.startsWith('sqlite_') &&
      !localOnly.contains(table);
}
