/*
  البند 1.8: لا يُعاد رفع ما وصل من الخادم للتو، ولا يضيع ما لم يُرفع بعد.
*/

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/sync_echo_guard.dart';
import 'package:naboo/services/sync_safety.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../oil_change/helpers/oil_change_test_harness.dart';
import 'support/multi_device_fleet.dart';

void main() {
  group('فحص الصفوف', () {
    const gidCols = {'id', 'global_id', 'updatedAt', 'name'};

    test('كل صف محلي موجود في الخادم بالطابع نفسه: لا رفع', () {
      expect(
        SyncEchoGuard.tableCovered(
          localCols: gidCols,
          local: [
            {'id': 1, 'global_id': 'a', 'updatedAt': '2026-11-10T10:00:00.000'},
          ],
          remote: [
            {'id': 7, 'global_id': 'a', 'updatedAt': '2026-11-10T10:00:00.000'},
          ],
        ),
        isTrue,
        reason: 'الرقم المحلي يختلف بين الأجهزة، والهوية global_id',
      );
    });

    test('صف محلي غير موجود في الخادم: رفع', () {
      expect(
        SyncEchoGuard.tableCovered(
          localCols: gidCols,
          local: [
            {'id': 1, 'global_id': 'a', 'updatedAt': '2026-11-10T10:00:00.000'},
            {'id': 2, 'global_id': 'new', 'updatedAt': '2026-11-10T09:00:00.000'},
          ],
          remote: [
            {'id': 1, 'global_id': 'a', 'updatedAt': '2026-11-10T10:00:00.000'},
          ],
        ),
        isFalse,
      );
    });

    test('تعديل محلي أحدث من نسخة الخادم، حتى لو لم يتغير أحدث طابع في الجدول: رفع',
        () {
      // هذه الحالة تفوت فحص «العدد وأحدث طابع» وحده.
      expect(
        SyncEchoGuard.tableCovered(
          localCols: gidCols,
          local: [
            {'id': 1, 'global_id': 'x', 'updatedAt': '2026-11-10T09:30:00.000'},
            {'id': 2, 'global_id': 'y', 'updatedAt': '2026-11-10T10:00:00.000'},
          ],
          remote: [
            {'id': 1, 'global_id': 'x', 'updatedAt': '2026-11-10T09:00:00.000'},
            {'id': 2, 'global_id': 'y', 'updatedAt': '2026-11-10T10:00:00.000'},
          ],
        ),
        isFalse,
      );
    });

    test('جدول بلا طابع: يُقارن المحتوى بالرقم', () {
      const cols = {'id', 'name', 'priceFils'};
      expect(
        SyncEchoGuard.tableCovered(
          localCols: cols,
          local: [
            {'id': 3, 'name': 'غسيل', 'priceFils': 5000},
          ],
          remote: [
            {'id': 3, 'name': 'غسيل', 'priceFils': 5000.0},
          ],
        ),
        isTrue,
      );
      expect(
        SyncEchoGuard.tableCovered(
          localCols: cols,
          local: [
            {'id': 3, 'name': 'غسيل', 'priceFils': 6000},
          ],
          remote: [
            {'id': 3, 'name': 'غسيل', 'priceFils': 5000},
          ],
        ),
        isFalse,
      );
    });

    test('طابع لا يُقرأ أو صف بلا هوية: رفع', () {
      expect(
        SyncEchoGuard.tableCovered(
          localCols: gidCols,
          local: [
            {'id': 1, 'global_id': 'a', 'updatedAt': 'أمس'},
          ],
          remote: [
            {'id': 1, 'global_id': 'a', 'updatedAt': 'اليوم'},
          ],
        ),
        isFalse,
      );
      expect(
        SyncEchoGuard.tableCovered(
          localCols: const {'name'},
          local: [
            {'name': 'بلا هوية'},
          ],
          remote: [
            {'name': 'بلا هوية'},
          ],
        ),
        isFalse,
      );
    });
  });

  group('أسطول أجهزة', () {
    late Directory tmp;
    late Fleet f;
    const slow = Timeout(Duration(minutes: 5));

    setUpAll(initOilChangeTestEnvironment);

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('naboo_echo_');
      SharedPreferences.setMockInitialValues({});
      TenantContext.instance.set('1');
      SyncSafety.enabled = true;
      f = await Fleet.create(2, tmp);
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
    });

    tearDown(() async {
      f.dispose();
      SyncSafety.enabled = true;
      await tmp.delete(recursive: true);
    });

    test('ص1: الجهاز المستلم لا يعيد رفع ما وصله', () async {
      await f.createCard(f['A'], 'A-1');
      await f.syncDevice(f['A']);
      final afterA = f.cloud.pushes;
      await f.syncDevice(f['B']);
      expect(await f.plates(f['B']), contains('A-1'));
      expect(f.cloud.pushes, afterA, reason: 'رفع B هنا صدى لا يحمل جديداً');
    }, timeout: slow);

    test('ص2: بطاقة لم تُرفع تبقى وتُرفع بعد السحب', () async {
      await f.createCard(f['B'], 'B-offline');
      await f.createCard(f['A'], 'A-1');
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
      final cloudPlates = await f.cloud.currentPayload().then(
            (p) => ((p!['tables'] as Map)['service_orders'] as List)
                .map((r) => (r as Map)['deviceSerial'].toString())
                .toSet(),
          );
      expect(cloudPlates, containsAll(['A-1', 'B-offline']));
      await f.converge();
      final byDevice = await f.platesByDevice();
      for (final e in byDevice.entries) {
        expect(e.value, containsAll(['A-1', 'B-offline']), reason: e.key);
      }
    }, timeout: slow);

    test('ص3: تعديل محلي على بطاقة قديمة لا يضيع بعد سحب تعديل آخر', () async {
      final id = await f.createCard(f['A'], 'OLD');
      await f.converge();
      // B يعدّل البطاقة القديمة دون رفع، وA يضيف بطاقة أحدث ويرفع.
      final db = await f.activate(f['B']);
      final stamp = DateTime.now().toIso8601String();
      await db.rawUpdate(
        "UPDATE service_orders SET deviceSerial = 'OLD-EDITED', updatedAt = ? "
        "WHERE deviceSerial = 'OLD'",
        [stamp],
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await f.createCard(f['A'], 'NEWER');
      await f.syncDevice(f['A']);
      await f.syncDevice(f['B']);
      final cloudPlates = await f.cloud.currentPayload().then(
            (p) => ((p!['tables'] as Map)['service_orders'] as List)
                .map((r) => (r as Map)['deviceSerial'].toString())
                .toSet(),
          );
      expect(cloudPlates, contains('OLD-EDITED'), reason: 'id=$id');
      expect(cloudPlates, contains('NEWER'));
    }, timeout: slow);

    test('ص4: مع إطفاء الإصلاحات يبقى السلوك القديم', () async {
      f['B'].legacy = true;
      await f.createCard(f['A'], 'A-1');
      await f.syncDevice(f['A']);
      final afterA = f.cloud.pushes;
      await f.syncDevice(f['B']);
      expect(f.cloud.pushes, greaterThan(afterA));
    }, timeout: slow);
  });
}
