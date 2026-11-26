import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/ui/assistant_car_photo_screen.dart';

// صورة PNG بنقطة واحدة.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  Future<Map<String, Object?>?> run(
    WidgetTester tester, {
    required AssistantCarPhotoRead read,
    AssistantKnownCar? known,
    String? editPlate,
  }) async {
    Map<String, Object?>? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: AssistantCarPhotoScreen(
            pick: () async => _png,
            read: (_) async => read,
            lookup: (p) async => p == '14 B 64190' ? known : null,
            open: (v) async => opened = v,
          ),
        ),
      ),
    );
    await tester.tap(find.text('صورة اللوحة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اقرأ الرقمين'));
    await tester.pumpAndSettle();
    if (editPlate != null) {
      await tester.enterText(find.widgetWithText(TextField, 'رقم اللوحة'), editPlate);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('افتح البطاقة'));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('م4-13: سيارة معروفة تعبّئ الزبون، والرقمان يمران كما راجعهما', (tester) async {
    final v = await run(
      tester,
      read: const AssistantCarPhotoRead(plate: '14 B 64190', odometer: 152300),
      known: const AssistantKnownCar(customer: 'أبو حسين', lastOdometer: 150000),
    );
    expect(find.textContaining('سيارة معروفة'), findsOneWidget);
    expect(v, {'plate': '14 B 64190', 'odometer': 152300, 'customer': 'أبو حسين'});
  });

  testWidgets('لوحة قديمة: «تأكد من الأرقام»، وبلا سيارة لا يُخمَّن زبون', (tester) async {
    final v = await run(tester, read: const AssistantCarPhotoRead(plate: 'R 14612', oldStyle: true));
    expect(find.textContaining('تأكد من الأرقام'), findsOneWidget);
    expect(find.textContaining('ما لقيت سيارة'), findsOneWidget);
    expect(v, {'plate': 'R 14612'});
  });

  testWidgets('تصحيح المستخدم للوحة يعيد البحث ويُعتمد هو', (tester) async {
    final v = await run(
      tester,
      read: const AssistantCarPhotoRead(plate: '14 B 64199'),
      known: const AssistantKnownCar(customer: 'أبو حسين'),
      editPlate: '14 B 64190',
    );
    expect(v, {'plate': '14 B 64190', 'customer': 'أبو حسين'});
  });

  testWidgets('فشل القراءة: الخانتان فارغتان ويكتبهما بيده', (tester) async {
    final v = await run(tester, read: const AssistantCarPhotoRead(error: 'network'));
    expect(find.textContaining('ما في إنترنت'), findsOneWidget);
    expect(v, isEmpty);
  });
}
