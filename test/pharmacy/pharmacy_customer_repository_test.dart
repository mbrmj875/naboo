import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_customer_ext.dart';
import 'package:naboo/verticals/pharmacy/services/pharmacy_customer_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  const otherTenantId = 2;
  const customerId = 42;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PharmacyCustomerRepository', () {
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

    test('insert and update customer ext', () async {
      final saved = await repo.upsert(
        PharmacyCustomerExt(
          tenantId: tenantId,
          customerId: customerId,
          allergies: const ['Penicillin'],
          medicalNotes: 'سكري',
        ),
      );
      expect(saved.id, isNotNull);
      expect(saved.allergies, ['Penicillin']);
      expect(saved.medicalNotes, 'سكري');

      final updated = await repo.upsert(
        saved.copyWith(medicalNotes: 'ضغط + سكري'),
      );
      expect(updated.medicalNotes, 'ضغط + سكري');

      final loaded = await repo.getByCustomerId(
        tenantId: tenantId,
        customerId: customerId,
      );
      expect(loaded?.medicalNotes, 'ضغط + سكري');
    });

    test('allergies JSON round-trip', () async {
      await repo.upsertAllergies(
        tenantId: tenantId,
        customerId: customerId,
        allergies: const ['Aspirin', 'Codeine'],
      );
      final loaded = await repo.listAllergies(
        tenantId: tenantId,
        customerId: customerId,
      );
      expect(loaded, ['Aspirin', 'Codeine']);
    });

    test('chronic medications list persists', () async {
      final meds = [
        PharmacyChronicMedication(
          productId: 7,
          productName: 'Metformin 500mg',
          startDate: DateTime(2025, 1, 15),
        ),
        PharmacyChronicMedication(
          productId: 8,
          productName: 'Lisinopril 10mg',
          startDate: DateTime(2024, 6, 1),
          lastPurchaseDate: DateTime(2026, 5, 1),
        ),
      ];
      await repo.updateChronicMedications(
        tenantId: tenantId,
        customerId: customerId,
        medications: meds,
      );
      final ext = await repo.getByCustomerId(
        tenantId: tenantId,
        customerId: customerId,
      );
      expect(ext?.chronicMedications, hasLength(2));
      expect(ext!.chronicMedications.first.productName, 'Metformin 500mg');
      expect(ext.chronicMedications.last.lastPurchaseDate, isNotNull);
    });

    test('tenant isolation', () async {
      await repo.upsertAllergies(
        tenantId: tenantId,
        customerId: customerId,
        allergies: const ['Penicillin'],
      );
      await repo.upsertAllergies(
        tenantId: otherTenantId,
        customerId: customerId,
        allergies: const ['NSAIDs'],
      );

      final t1 = await repo.listAllergies(
        tenantId: tenantId,
        customerId: customerId,
      );
      final t2 = await repo.listAllergies(
        tenantId: otherTenantId,
        customerId: customerId,
      );
      expect(t1, ['Penicillin']);
      expect(t2, ['NSAIDs']);
    });

    test('recordRefillsFromSale updates last purchase date', () async {
      await repo.updateChronicMedications(
        tenantId: tenantId,
        customerId: customerId,
        medications: [
          PharmacyChronicMedication(
            productId: 11,
            productName: 'Atorvastatin',
            startDate: DateTime(2025, 3, 1),
          ),
        ],
      );
      final purchasedAt = DateTime(2026, 6, 11, 14, 30);
      await repo.recordRefillsFromSale(
        tenantId: tenantId,
        customerId: customerId,
        productIds: const [11, 99],
        purchasedAt: purchasedAt,
      );
      final ext = await repo.getByCustomerId(
        tenantId: tenantId,
        customerId: customerId,
      );
      expect(ext?.chronicMedications.single.lastPurchaseDate?.year, 2026);
      expect(ext?.chronicMedications.single.lastPurchaseDate?.month, 6);
      expect(ext?.chronicMedications.single.lastPurchaseDate?.day, 11);
    });
  });
}
