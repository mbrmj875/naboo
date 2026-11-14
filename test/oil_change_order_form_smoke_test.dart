import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:naboo/verticals/oil_change/screens/oil_change_form_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('بطاقة غيار زيت جديدة — لا crash وحقول أساسية', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: OilChangeFormScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('بيانات العميل'), findsOneWidget);
    expect(find.text('بيانات السيارة'), findsOneWidget);
    expect(find.text('تغيير الزيت'), findsOneWidget);
    expect(find.text('رقم اللوحة'), findsOneWidget);
  });
}
