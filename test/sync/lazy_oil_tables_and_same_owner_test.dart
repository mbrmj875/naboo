import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/providers/auth_provider.dart';
import 'package:naboo/services/database_helper.dart';

import '../integration/helpers/vertical_test_harness.dart';

/// البند 1.9: لا تضيع بيانات الزيوت بعد مسح القاعدة، ولا تُمسح لنفس الحساب.
void main() {
  group('جداول الزيوت عند فتح القاعدة', () {
    setUpAll(initVerticalTestEnvironment);

    test('قاعدة جديدة تحوي الجداول الثلاثة قبل أي شاشة', () async {
      final helper = DatabaseHelper();
      await helper.closeAndDeleteDatabaseFile();
      final db = await helper.database;
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
        "('oil_change_services','car_wash_services','oil_change_filter_kinds')",
      );
      final names = rows.map((r) => r['name']).toSet();
      expect(
        names,
        {'oil_change_services', 'car_wash_services', 'oil_change_filter_kinds'},
        reason: 'الاستيراد يتخطى أي جدول غير موجود، فيُرفع فارغاً لاحقاً',
      );
    });
  });

  group('صاحب البيانات عند الدخول', () {
    const owner = 'cloud:aaaa';
    const other = 'cloud:bbbb';

    test('الحساب نفسه وهو مربوط: لا مسح', () {
      expect(
        AuthProvider.isSameDataOwner(
            active: owner, lastAfterUnlink: null, incoming: owner),
        isTrue,
      );
    });

    test('الحساب نفسه بعد فك الربط: لا مسح', () {
      expect(
        AuthProvider.isSameDataOwner(
            active: null, lastAfterUnlink: owner, incoming: owner),
        isTrue,
      );
    });

    test('حساب آخر بعد فك الربط: مسح', () {
      expect(
        AuthProvider.isSameDataOwner(
            active: null, lastAfterUnlink: owner, incoming: other),
        isFalse,
      );
    });

    test('حساب آخر وهو مربوط: مسح حتى لو تذكّرنا صاحباً قديماً', () {
      expect(
        AuthProvider.isSameDataOwner(
            active: owner, lastAfterUnlink: other, incoming: other),
        isFalse,
      );
    });

    test('جهاز لا نعرف صاحب بياناته: مسح', () {
      expect(
        AuthProvider.isSameDataOwner(
            active: null, lastAfterUnlink: null, incoming: owner),
        isFalse,
      );
    });
  });
}
