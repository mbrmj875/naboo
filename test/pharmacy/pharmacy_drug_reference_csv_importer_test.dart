import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/pharmacy/models/pharmacy_rx_schedule.dart';
import 'package:naboo/verticals/pharmacy/services/drug_catalog_repository.dart';
import 'package:naboo/verticals/pharmacy/services/pharmacy_drug_reference_csv_importer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  const otherTenantId = 2;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PharmacyDrugReferenceCsvImporter', () {
    late DatabaseHelper dbHelper;
    late DrugCatalogRepository repo;
    late PharmacyDrugReferenceCsvImporter importer;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      repo = DrugCatalogRepository(
        db: dbHelper,
        scheduleSync: () {},
      );
      importer = PharmacyDrugReferenceCsvImporter(repository: repo);
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    test('empty template imports zero rows', () async {
      final result = await importer.importFromCsv(
        tenantId: tenantId,
        csvContent: PharmacyDrugReferenceCsvImporter.buildEmptyTemplate(),
      );

      expect(result.importedCount, 0);
      expect(result.skippedCount, 0);
      expect(result.errors, isEmpty);
    });

    test('invalid headers returns error and skips data rows', () async {
      final csv = '''
wrong_header,name_en,atc_code,indications_pipe,indications_free_text,age_band,interactions_placeholder_pipe
باراسيتامول,Paracetamol,N02BE01,,,both,
''';

      final result = await importer.importFromCsv(
        tenantId: tenantId,
        csvContent: csv,
      );

      expect(result.importedCount, 0);
      expect(result.skippedCount, 1);
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('invalid_csv_headers'));
      expect(await repo.listDrugReferences(tenantId: tenantId), isEmpty);
    });

    test('imports multiple rows in one pass', () async {
      final csv = '''
${PharmacyDrugReferenceCsvImporter.expectedHeaders.join(',')}
باراسيتامول,Paracetamol,N02BE01,,,both,
أموكسيسيلين,Amoxicillin,J01CA04,,,adult,
''';

      final result = await importer.importFromCsv(
        tenantId: tenantId,
        csvContent: csv,
      );

      expect(result.importedCount, 2);
      expect(result.errors, isEmpty);
      expect(await repo.listDrugReferences(tenantId: tenantId), hasLength(2));
    });

    test('skips comment lines and blank rows', () async {
      final csv = '''
${PharmacyDrugReferenceCsvImporter.expectedHeaders.join(',')}
# تعليق — يُتخطى
,,,,,,
باراسيتامول,Paracetamol,N02BE01,,,both,

''';

      final result = await importer.importFromCsv(
        tenantId: tenantId,
        csvContent: csv,
      );

      expect(result.importedCount, 1);
      expect(result.skippedCount, 2);
      expect(result.errors, isEmpty);
    });

    test('skips rows with empty Arabic and English names', () async {
      final csv = '''
${PharmacyDrugReferenceCsvImporter.expectedHeaders.join(',')}
,,N02BE01,,,both,
باراسيتامول,Paracetamol,N02BE01,,,both,
''';

      final result = await importer.importFromCsv(
        tenantId: tenantId,
        csvContent: csv,
      );

      expect(result.importedCount, 1);
      expect(result.skippedCount, 1);
      expect(await repo.listDrugReferences(tenantId: tenantId), hasLength(1));
    });

    test('normalizes unknown age_band to both', () async {
      final csv = '''
${PharmacyDrugReferenceCsvImporter.expectedHeaders.join(',')}
باراسيتامول,Paracetamol,N02BE01,,,unknown,
''';

      await importer.importFromCsv(tenantId: tenantId, csvContent: csv);

      final rows = await repo.listDrugReferences(tenantId: tenantId);
      expect(rows.single.ageBand, PharmacyAgeBand.both);
    });

    test('imports pipe-separated indications and interactions', () async {
      final csv = '''
${PharmacyDrugReferenceCsvImporter.expectedHeaders.join(',')}
باراسيتامول,Paracetamol,N02BE01,حمى|ألم,نص حر,both,warfarin|alcohol
''';

      final result = await importer.importFromCsv(
        tenantId: tenantId,
        csvContent: csv,
      );

      expect(result.importedCount, 1);
      final row = (await repo.searchDrugReferences(
        tenantId: tenantId,
        query: 'paracet',
      )).single;
      expect(row.indications, ['حمى', 'ألم']);
      expect(row.indicationsFreeText, 'نص حر');
      expect(row.interactionsPlaceholder, ['warfarin', 'alcohol']);
    });

    test('tenant isolation on import', () async {
      final csv = '''
${PharmacyDrugReferenceCsvImporter.expectedHeaders.join(',')}
دواء أ,Drug A,N02BE01,,,both,
''';

      await importer.importFromCsv(tenantId: tenantId, csvContent: csv);

      expect(await repo.listDrugReferences(tenantId: tenantId), hasLength(1));
      expect(await repo.listDrugReferences(tenantId: otherTenantId), isEmpty);
    });

    test('whitespace-only content reports csv_empty', () async {
      final result = await importer.importFromCsv(
        tenantId: tenantId,
        csvContent: '   \n  ',
      );

      expect(result.importedCount, 0);
      expect(result.errors, ['csv_empty']);
    });
  });
}
