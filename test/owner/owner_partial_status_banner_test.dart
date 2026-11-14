import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/owner/models/owner_section_result.dart';
import 'package:naboo/owner/widgets/owner_partial_status_banner.dart';

void main() {
  testWidgets('shows banner only for partial status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerPartialStatusBanner(
            status: CommandCenterScreenStatus.partial,
          ),
        ),
      ),
    );
    expect(
      find.textContaining('تعذّر تحميل بعض البطاقات'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerPartialStatusBanner(
            status: CommandCenterScreenStatus.ready,
          ),
        ),
      ),
    );
    expect(
      find.textContaining('تعذّر تحميل بعض البطاقات'),
      findsNothing,
    );
  });
}
