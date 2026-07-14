import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/verticals/pharmacy/services/drug_catalog_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const tenantId = 1;
  const otherTenantId = 2;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DrugCatalogRepository', () {
    late DatabaseHelper dbHelper;
    late DrugCatalogRepository repo;

    setUp(() async {
      dbHelper = DatabaseHelper();
      await dbHelper.closeAndDeleteDatabaseFile();
      repo = DrugCatalogRepository(
        db: dbHelper,
        scheduleSync: () {},
      );
      await repo.ensureSchema();
    });

    tearDown(() async {
      await dbHelper.closeAndDeleteDatabaseFile();
    });

    test('searchDrugReferences matches Arabic name', () async {
      await repo.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
        atcCode: 'N02BE01',
      );
      await repo.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'أموكسيسيلين',
        nameEn: 'Amoxicillin',
        atcCode: 'J01CA04',
      );

      final hits = await repo.searchDrugReferences(
        tenantId: tenantId,
        query: 'باراس',
      );

      expect(hits, hasLength(1));
      expect(hits.single.nameAr, 'باراسيتامول');
    });

    test('searchDrugReferences matches English name and ATC', () async {
      await repo.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'باراسيتامول',
        nameEn: 'Paracetamol',
        atcCode: 'N02BE01',
      );
      await repo.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'أموكسيسيلين',
        nameEn: 'Amoxicillin',
        atcCode: 'J01CA04',
      );

      final byEn = await repo.searchDrugReferences(
        tenantId: tenantId,
        query: 'amox',
      );
      expect(byEn, hasLength(1));
      expect(byEn.single.nameEn, 'Amoxicillin');

      final byAtc = await repo.searchDrugReferences(
        tenantId: tenantId,
        query: 'n02be',
      );
      expect(byAtc, hasLength(1));
      expect(byAtc.single.atcCode, 'N02BE01');
    });

    test('tenant isolation for drug references', () async {
      await repo.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'دواء المستأجر الأول',
        nameEn: 'Tenant One Drug',
      );
      await repo.insertDrugReference(
        tenantId: otherTenantId,
        nameAr: 'دواء المستأجر الثاني',
        nameEn: 'Tenant Two Drug',
      );

      final tenantOne = await repo.listDrugReferences(tenantId: tenantId);
      final tenantTwo = await repo.listDrugReferences(tenantId: otherTenantId);

      expect(tenantOne, hasLength(1));
      expect(tenantOne.single.nameAr, 'دواء المستأجر الأول');
      expect(tenantTwo, hasLength(1));
      expect(tenantTwo.single.nameAr, 'دواء المستأجر الثاني');

      final crossSearch = await repo.searchDrugReferences(
        tenantId: tenantId,
        query: 'المستأجر الثاني',
      );
      expect(crossSearch, isEmpty);
    });

    test('softDeleteDrugReference hides row from list and search', () async {
      final id = await repo.insertDrugReference(
        tenantId: tenantId,
        nameAr: 'محذوف',
        nameEn: 'Deleted',
      );
      await repo.softDeleteDrugReference(tenantId: tenantId, id: id);

      expect(await repo.getDrugReferenceById(tenantId: tenantId, id: id), isNull);
      expect(await repo.listDrugReferences(tenantId: tenantId), isEmpty);
      expect(
        await repo.searchDrugReferences(tenantId: tenantId, query: 'محذوف'),
        isEmpty,
      );
    });

    test('insertManufacturer and listManufacturers are tenant-scoped', () async {
      await repo.insertManufacturer(
        tenantId: tenantId,
        name: 'شركة أ',
        qualityTier: 'A',
      );
      await repo.insertManufacturer(
        tenantId: otherTenantId,
        name: 'شركة ب',
      );

      expect(await repo.listManufacturers(tenantId: tenantId), hasLength(1));
      expect(
        await repo.listManufacturers(tenantId: otherTenantId),
        hasLength(1),
      );
    });
  });
}
