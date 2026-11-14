import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_customer_ext.dart';
import 'package:naboo/verticals/pharmacy/screens/pharmacy_customer_detail_sheet.dart';
import 'package:naboo/verticals/pharmacy/services/pharmacy_customer_repository.dart';
import 'package:naboo/verticals/pharmacy/widgets/allergy_badge.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  const customerId = 55;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PharmacyCustomerDetailSheet', () {
    late DatabaseHelper dbHelper;
    late PharmacyCustomerRepository repo;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      repo = PharmacyCustomerRepository(db: dbHelper, scheduleSync: () {});
      await repo.ensureSchema();
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    Future<void> pumpSheet(
      WidgetTester tester, {
      PharmacyCustomerExt? initialData,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PharmacyCustomerDetailSheet(
              tenantId: tenantId,
              customerId: customerId,
              customerName: 'أحمد محمد',
              customerPhone: '07911223344',
              repository: repo,
              initialData: initialData,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('displays saved allergies', (tester) async {
      await pumpSheet(
        tester,
        initialData: PharmacyCustomerExt(
          tenantId: tenantId,
          customerId: customerId,
          allergies: const ['Penicillin', 'Aspirin'],
        ),
      );
      expect(find.text('أحمد محمد'), findsOneWidget);
      expect(find.text('07911223344'), findsOneWidget);
      expect(find.byType(AllergyBadge), findsNWidgets(2));
      expect(find.text('بنسلين'), findsOneWidget);
      expect(find.text('أسبرين'), findsOneWidget);
    });

    testWidgets('add allergy from dialog', (tester) async {
      await pumpSheet(
        tester,
        initialData: PharmacyCustomerExt(
          tenantId: tenantId,
          customerId: customerId,
        ),
      );
      await tester.tap(find.text('إضافة حساسية'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('إضافة').last);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(AllergyBadge), findsOneWidget);
    });

    testWidgets('delete allergy chip', (tester) async {
      await pumpSheet(
        tester,
        initialData: PharmacyCustomerExt(
          tenantId: tenantId,
          customerId: customerId,
          allergies: const ['Codeine'],
        ),
      );
      expect(find.byType(AllergyBadge), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AllergyBadge), findsNothing);
    });

    testWidgets('shows chronic medications and delete', (tester) async {
      await pumpSheet(
        tester,
        initialData: PharmacyCustomerExt(
          tenantId: tenantId,
          customerId: customerId,
          chronicMedications: [
            PharmacyChronicMedication(
              productId: 3,
              productName: 'Metformin 500mg',
              startDate: DateTime(2025, 1, 1),
            ),
          ],
        ),
      );
      expect(find.text('Metformin 500mg'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Metformin 500mg'), findsNothing);
    });

    testWidgets('save persists medical notes', (tester) async {
      var savedNotes = '';
      final trackingRepo = _TrackingCustomerRepository(
        db: dbHelper,
        delegate: repo,
        onUpsert: (ext) => savedNotes = ext.medicalNotes ?? '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PharmacyCustomerDetailSheet(
              tenantId: tenantId,
              customerId: customerId,
              customerName: 'أحمد محمد',
              repository: trackingRepo,
              initialData: PharmacyCustomerExt(
                tenantId: tenantId,
                customerId: customerId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ضغط مرتفع');
      await tester.tap(find.text('حفظ'));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        if (savedNotes == 'ضغط مرتفع') break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(savedNotes, 'ضغط مرتفع');
    });
  });
}

class _TrackingCustomerRepository extends PharmacyCustomerRepository {
  _TrackingCustomerRepository({
    required super.db,
    required this.delegate,
    required this.onUpsert,
  }) : super(scheduleSync: () {});

  final PharmacyCustomerRepository delegate;
  final void Function(PharmacyCustomerExt ext) onUpsert;

  @override
  Future<PharmacyCustomerExt> upsert(PharmacyCustomerExt ext) async {
    onUpsert(ext);
    return delegate.upsert(ext);
  }
}
