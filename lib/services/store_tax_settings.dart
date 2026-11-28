import 'package:flutter/foundation.dart';

import 'app_settings_repository.dart';
import 'database_helper.dart';

/// مفتاح «تفعيل الضريبة» للمحل كله.
///
/// حين يكون مطفأً تختفي حقول الضريبة من كل الشاشات (إضافة منتج، البيع،
/// الإعدادات) وتُثبَّت ضريبة البيع على 0. يُحفظ في `app_settings`، فينتقل
/// بين الأجهزة مع المزامنة.
///
/// لا قيمة محفوظة: مطفأ، إلا إن كان المحل قد استعمل ضريبة في فاتورة سابقة.
/// الافتراض لا يُكتب في الجدول، فقيمة يختارها صاحب المحل على جهاز تغلب.
class StoreTaxSettings {
  StoreTaxSettings._();

  static const String key = 'store.tax_enabled';

  /// القيمة الحالية؛ تتحدّث عند [load] و[set].
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static bool? parse(String? raw) {
    final v = raw?.trim();
    if (v == '1' || v == 'true') return true;
    if (v == '0' || v == 'false') return false;
    return null;
  }

  static Future<bool> load() async {
    bool on;
    try {
      final saved = parse(await AppSettingsRepository.instance.get(key));
      on = saved ?? await _usedTaxBefore();
    } catch (_) {
      on = enabled.value;
    }
    enabled.value = on;
    return on;
  }

  static Future<void> set(bool on) async {
    enabled.value = on;
    await AppSettingsRepository.instance.set(key, on ? '1' : '0');
  }

  static Future<bool> _usedTaxBefore() async {
    final db = await DatabaseHelper().database;
    try {
      final rows = await db.rawQuery(
        'SELECT 1 FROM invoices WHERE IFNULL(tax, 0) > 0 LIMIT 1',
      );
      return rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
