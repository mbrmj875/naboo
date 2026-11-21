import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/providers/shift_provider.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/tenant_context.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/oil_change_test_harness.dart';

Future<int> _openShift(int staffId, String name) {
  return DatabaseHelper().openWorkShift(
    sessionUserId: staffId,
    shiftStaffUserId: staffId,
    systemBalanceAtOpen: 0,
    declaredPhysicalCash: 0,
    addedCashAtOpen: 0,
    shiftStaffName: name,
    shiftStaffPin: '',
  );
}

Future<void> _seedStaff(int id) async {
  final db = await DatabaseHelper().database;
  final columns = await db.rawQuery('PRAGMA table_info(users)');
  final row = <String, Object?>{'id': id};
  for (final c in columns) {
    final name = c['name']! as String;
    if (name == 'id' || c['notnull'] != 1 || c['dflt_value'] != null) continue;
    final type = (c['type']! as String).toUpperCase();
    row[name] = type.contains('INT') || type.contains('REAL') ? 1 : 'u$id';
  }
  await db.insert('users', row);
}

Future<void> _settle(ShiftProvider shift) async {
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await shift.refresh();
}

void main() {
  setUpAll(() async {
    initOilChangeTestEnvironment();
    SharedPreferences.setMockInitialValues({});
    // فتح الوردية يطلب مزامنة: خادم لا يجيب كما في انقطاع الاتصال.
    await Supabase.initialize(
      url: 'http://127.0.0.1:9',
      anonKey: 'offline-test',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
        autoRefreshToken: false,
      ),
    );
  });

  setUp(() async {
    await OilChangeTestHarness.instance.reset();
    await OilChangeTestHarness.instance.configureServiceOnly();
    TenantContext.instance.set('shift-scope-test-tenant');
    await _seedStaff(11);
    await _seedStaff(22);
    await _openShift(11, 'علي');
    await _openShift(22, 'سارة');
  });

  test('موظف جلسته 11 يقرأ ورديته لا أحدث وردية في المتجر', () async {
    final shift = ShiftProvider()..syncSessionStaff(11);
    await _settle(shift);

    expect(shift.activeShift?['shiftStaffName'], 'علي');
    expect(shift.activeShift?['shiftStaffUserId'], 11);
  });

  test('التحديث بلا معامل لا يعيد القراءة إلى وردية زميل', () async {
    final shift = ShiftProvider()..syncSessionStaff(11);
    await _settle(shift);
    await shift.refresh();

    expect(shift.activeShift?['shiftStaffUserId'], 11);
  });

  test('موظف بلا وردية لا يرث وردية زميله', () async {
    final shift = ShiftProvider()..syncSessionStaff(33);
    await _settle(shift);

    expect(shift.hasOpenShift, isFalse);
  });

  test('تبديل الموظف يبدّل الوردية', () async {
    final shift = ShiftProvider()..syncSessionStaff(11);
    await _settle(shift);

    shift.syncSessionStaff(22);
    await _settle(shift);

    expect(shift.activeShift?['shiftStaffUserId'], 22);
  });

  test('المالك يبقى على أحدث وردية في المتجر', () async {
    final shift = ShiftProvider()..syncSessionStaff(null);
    await _settle(shift);

    expect(shift.hasOpenShift, isTrue);
  });
}
